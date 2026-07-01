import Foundation

public struct AirPodsBatteryInfo: Codable, Equatable {
  public var leftPercentage: Int?
  public var rightPercentage: Int?
  public var casePercentage: Int?

  public init(leftPercentage: Int? = nil, rightPercentage: Int? = nil, casePercentage: Int? = nil) {
    self.leftPercentage = leftPercentage
    self.rightPercentage = rightPercentage
    self.casePercentage = casePercentage
  }

  public var hasData: Bool {
    leftPercentage != nil || rightPercentage != nil || casePercentage != nil
  }
}

public protocol AirPodsBatteryMonitoring: AnyObject {
  var onBatteryUpdate: ((AirPodsBatteryInfo) -> Void)? { get set }
  func start()
  func stop()
}

/// Best-effort AirPods battery reader.
///
/// NOTE (NB-6): this shells out to `system_profiler`, which is **not** permitted
/// under the App Sandbox (Mac App Store). Under sandboxing the call fails and the
/// widget simply shows no data. It works for Developer ID / unsandboxed builds.
public final class AirPodsBatteryMonitor: AirPodsBatteryMonitoring {
  public var onBatteryUpdate: ((AirPodsBatteryInfo) -> Void)?

  /// `system_profiler` is expensive (a subprocess that enumerates the whole BT
  /// stack), so we poll infrequently rather than every 30 s (NB-4).
  private let pollInterval: TimeInterval = 300.0
  private var timer: Timer?
  private let queue = DispatchQueue(label: "NoSlouch.AirPodsBatteryMonitor")

  public init() {}

  public func start() {
    timer?.invalidate()
    pollBattery()
    timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      self?.pollBattery()
    }
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func pollBattery() {
    if NSClassFromString("XCTestCase") != nil {
      return
    }

    queue.async { [weak self] in
      guard let self else { return }
      let info = self.fetchBatteryInfo()
      DispatchQueue.main.async {
        self.onBatteryUpdate?(info)
      }
    }
  }

  private func fetchBatteryInfo() -> AirPodsBatteryInfo {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType"]

    let pipe = Pipe()
    process.standardOutput = pipe

    do {
      try process.run()
      process.waitUntilExit()

      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        return parseBatteryOutput(output)
      }
    } catch {
      // Ignore process errors
    }

    return AirPodsBatteryInfo()
  }

  public func parseBatteryOutput(_ output: String) -> AirPodsBatteryInfo {
    let lines = output.components(separatedBy: .newlines)
    // Prefer battery lines scoped to an AirPods/Beats device section so a different
    // Bluetooth device's levels aren't picked up (NB-5). If no such section is
    // identifiable (e.g. a bare fragment), fall back to scanning all lines.
    let scoped = airPodsSectionLines(in: lines)
    return parseLevels(from: scoped.isEmpty ? lines : scoped)
  }

  private func airPodsSectionLines(in lines: [String]) -> [String] {
    var result: [String] = []
    var inSection = false
    var sectionIndent = 0

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        continue
      }

      let indent = line.prefix { $0 == " " }.count
      let lower = trimmed.lowercased()
      let isHeader = trimmed.hasSuffix(":") && !lower.contains("battery level")

      if isHeader {
        if lower.contains("airpods") || lower.contains("beats") {
          inSection = true
          sectionIndent = indent
        } else if inSection && indent <= sectionIndent {
          inSection = false
        }
        continue
      }

      if inSection {
        result.append(trimmed)
      }
    }

    return result
  }

  private func parseLevels(from lines: [String]) -> AirPodsBatteryInfo {
    var left: Int?
    var right: Int?
    var casePct: Int?

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("Left Battery Level:") {
        left = parsePercentage(trimmed)
      } else if trimmed.hasPrefix("Right Battery Level:") {
        right = parsePercentage(trimmed)
      } else if trimmed.hasPrefix("Case Battery Level:") {
        casePct = parsePercentage(trimmed)
      }
    }

    return AirPodsBatteryInfo(leftPercentage: left, rightPercentage: right, casePercentage: casePct)
  }

  private func parsePercentage(_ line: String) -> Int? {
    let parts = line.components(separatedBy: ":")
    guard parts.count > 1 else { return nil }
    let valueStr = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(
      of: "%", with: "")
    return Int(valueStr)
  }
}
