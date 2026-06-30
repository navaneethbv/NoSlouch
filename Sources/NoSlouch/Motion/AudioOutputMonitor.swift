import CoreAudio
import Foundation

protocol AudioOutputMonitoring: AnyObject {
  var airPodsActive: Bool { get }
  var deviceName: String { get }
  var onChange: ((Bool) -> Void)? { get set }

  func start()
}

final class AudioOutputMonitor: AudioOutputMonitoring {
  private(set) var airPodsActive = false
  private(set) var deviceName = ""
  var onChange: ((Bool) -> Void)?

  private var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  private var listenerBlock: AudioObjectPropertyListenerBlock?

  func start() {
    refresh()

    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.refresh()
    }
    listenerBlock = block

    var address = propertyAddress
    let status = AudioObjectAddPropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      block
    )

    if status != noErr {
      listenerBlock = nil
    }
  }

  deinit {
    guard let listenerBlock else {
      return
    }

    var address = propertyAddress
    AudioObjectRemovePropertyListenerBlock(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      DispatchQueue.main,
      listenerBlock
    )
  }

  private func refresh() {
    guard let deviceID = defaultOutputDeviceID() else {
      let wasActive = airPodsActive
      airPodsActive = false
      deviceName = ""
      if wasActive { onChange?(false) }
      return
    }

    let name = nameFor(deviceID: deviceID) ?? ""
    let transport = transportTypeFor(deviceID: deviceID)
    let active = Self.isHeadphones(name: name, transport: transport)
    deviceName = active ? name : ""

    guard active != airPodsActive else { return }
    airPodsActive = active
    onChange?(active)
  }

  private func defaultOutputDeviceID() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = propertyAddress

    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceID
    )

    guard status == noErr, deviceID != kAudioObjectUnknown else {
      return nil
    }

    return deviceID
  }

  private func nameFor(deviceID: AudioDeviceID) -> String? {
    stringProperty(kAudioObjectPropertyName, for: deviceID)
      ?? stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID)
  }

  private func transportTypeFor(deviceID: AudioDeviceID) -> UInt32 {
    var transport = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    _ = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
    return transport
  }

  private func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID)
    -> String?
  {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var unmanagedString: Unmanaged<CFString>? = nil
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

    let status = AudioObjectGetPropertyData(
      deviceID,
      &address,
      0,
      nil,
      &size,
      &unmanagedString
    )

    guard status == noErr, let unmanaged = unmanagedString else {
      return nil
    }

    return unmanaged.takeRetainedValue() as String
  }

  private static func isHeadphones(name: String, transport: UInt32) -> Bool {
    let lower = name.lowercased()
    return lower.contains("airpods")
      || lower.contains("beats")
      || lower.contains("headphone")
      || transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }
}
