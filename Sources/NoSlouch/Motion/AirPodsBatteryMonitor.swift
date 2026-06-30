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

public final class AirPodsBatteryMonitor: AirPodsBatteryMonitoring {
  public var onBatteryUpdate: ((AirPodsBatteryInfo) -> Void)?

  private var timer: Timer?
  private let queue = DispatchQueue(label: "NoSlouch.AirPodsBatteryMonitor")

  public init() {}

  public func start() {
    timer?.invalidate()
    pollBattery()
    // Poll every 30 seconds
    timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
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
    var left: Int?
    var right: Int?
    var casePct: Int?

    let lines = output.components(separatedBy: .newlines)
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
