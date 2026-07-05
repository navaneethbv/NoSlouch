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
  /// Bumped on every stop() (main thread) so an in-flight fetch started before
  /// the stop cannot repopulate state for AirPods that are no longer connected
  /// (NB-21). Read/written on main only.
  private var generation = 0
  /// Test seam (NB-7): production fetches via `system_profiler`; tests inject a
  /// canned-output fetcher instead of the removed `XCTestCase` runtime check.
  private let fetchRawOutput: () -> Data?

  public init(fetchRawOutput: (() -> Data?)? = nil) {
    self.fetchRawOutput = fetchRawOutput ?? AirPodsBatteryMonitor.runSystemProfiler
  }

  public func start() {
    guard timer == nil else {
      return
    }
    pollBattery()
    timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      self?.pollBattery()
    }
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
    generation += 1
  }

  private func pollBattery() {
    let startedGeneration = generation
    queue.async { [weak self] in
      guard let self else { return }
      let data = self.fetchRawOutput()
      let info = data.flatMap { AirPodsBatteryMonitor.parseBatteryJSON($0) } ?? AirPodsBatteryInfo()
      DispatchQueue.main.async {
        guard startedGeneration == self.generation else {
          return
        }
        self.onBatteryUpdate?(info)
      }
    }
  }

  /// Runs `system_profiler -json SPBluetoothDataType`, draining the pipe BEFORE
  /// waiting for exit (draining after is the classic pipe-buffer deadlock, NB-11),
  /// and killing the child if it wedges past the timeout.
  private static func runSystemProfiler() -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["-json", "SPBluetoothDataType"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
    } catch {
      return nil
    }

    let killSwitch = DispatchWorkItem {
      if process.isRunning {
        process.terminate()
      }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 15.0, execute: killSwitch)

    // readDataToEndOfFile returns at EOF — either normal exit or the kill above
    // closing the child's stdout — so waitUntilExit afterwards cannot deadlock.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    killSwitch.cancel()

    guard process.terminationReason == .exit, process.terminationStatus == 0 else {
      return nil
    }
    return data
  }

  /// Parses `system_profiler -json SPBluetoothDataType` output. The JSON keys
  /// (`device_batteryLevelLeft` etc.) are locale-independent, unlike the
  /// human-readable text labels (NB-12). Only devices that report a left or
  /// right bud level are considered, and AirPods/Beats-named devices win over
  /// other battery-reporting headsets (NB-13) — there is deliberately no
  /// whole-output fallback.
  public static func parseBatteryJSON(_ data: Data) -> AirPodsBatteryInfo? {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let sections = root["SPBluetoothDataType"] as? [[String: Any]]
    else {
      return nil
    }

    var best: (info: AirPodsBatteryInfo, isAirPods: Bool)?
    for section in sections {
      for deviceList in section.values {
        guard let devices = deviceList as? [[String: Any]] else {
          continue
        }
        for entry in devices {
          for (name, value) in entry {
            guard let properties = value as? [String: Any] else {
              continue
            }
            let left = percentage(properties["device_batteryLevelLeft"])
            let right = percentage(properties["device_batteryLevelRight"])
            guard left != nil || right != nil else {
              continue
            }
            let info = AirPodsBatteryInfo(
              leftPercentage: left,
              rightPercentage: right,
              casePercentage: percentage(properties["device_batteryLevelCase"])
            )
            let lowered = name.lowercased()
            let isAirPods = lowered.contains("airpods") || lowered.contains("beats")
            if isAirPods {
              return info
            }
            if best == nil {
              best = (info, false)
            }
          }
        }
      }
    }
    return best?.info
  }

  private static func percentage(_ value: Any?) -> Int? {
    guard let string = value as? String else {
      return nil
    }
    return Int(string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
  }
}
