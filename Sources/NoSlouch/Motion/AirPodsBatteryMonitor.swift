import Foundation

/// Info about the battery status of connected AirPods.
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
  func start(deviceName: String)
  func stop()
}

public final class AirPodsBatteryMonitor: AirPodsBatteryMonitoring {
  public var onBatteryUpdate: ((AirPodsBatteryInfo) -> Void)?

  private var timer: Timer?
  private let queue = DispatchQueue(label: "NoSlouch.AirPodsBatteryMonitor")
  private let shellRunner: () -> String?
  private var activeDeviceName: String = ""

  public init(shellRunner: @escaping () -> String? = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
    process.arguments = ["SPBluetoothDataType", "-json"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
      try process.run()
      process.waitUntilExit()
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      return String(data: data, encoding: .utf8)
    } catch {
      return nil
    }
  }) {
    self.shellRunner = shellRunner
  }

  public func start(deviceName: String) {
    timer?.invalidate()
    activeDeviceName = deviceName
    pollBattery()
    // Poll every 300 seconds (5 minutes) to reduce CPU overhead
    timer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
      self?.pollBattery()
    }
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func pollBattery() {
    let deviceName = activeDeviceName
    queue.async { [weak self] in
      guard let self else { return }
      guard let output = self.shellRunner() else { return }
      let info = self.parseBatteryOutput(output, deviceName: deviceName)
      DispatchQueue.main.async {
        self.onBatteryUpdate?(info)
      }
    }
  }

  public func parseBatteryOutput(_ output: String, deviceName: String) -> AirPodsBatteryInfo {
    guard let data = output.data(using: .utf8) else { return AirPodsBatteryInfo() }
    do {
      guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let spBluetooth = json["SPBluetoothDataType"] as? [[String: Any]],
            let firstObj = spBluetooth.first else {
        return AirPodsBatteryInfo()
      }

      // Check both connected and not connected devices
      let connectedList = firstObj["device_connected"] as? [[String: Any]] ?? []
      let notConnectedList = firstObj["device_not_connected"] as? [[String: Any]] ?? []
      let allDevices = connectedList + notConnectedList

      for deviceDict in allDevices {
        for (key, val) in deviceDict {
          if key == deviceName || key.contains(deviceName) || deviceName.contains(key) {
            if let deviceAttrs = val as? [String: Any] {
              let caseStr = deviceAttrs["device_batteryLevelCase"] as? String
              let leftStr = deviceAttrs["device_batteryLevelLeft"] as? String
              let rightStr = deviceAttrs["device_batteryLevelRight"] as? String

              let left = parsePercentageValue(leftStr)
              let right = parsePercentageValue(rightStr)
              let casePct = parsePercentageValue(caseStr)

              return AirPodsBatteryInfo(leftPercentage: left, rightPercentage: right, casePercentage: casePct)
            }
          }
        }
      }
    } catch {
      // Ignore JSON parsing errors
    }
    return AirPodsBatteryInfo()
  }

  private func parsePercentageValue(_ value: String?) -> Int? {
    guard let value = value else { return nil }
    let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
    return Int(cleaned)
  }
}

