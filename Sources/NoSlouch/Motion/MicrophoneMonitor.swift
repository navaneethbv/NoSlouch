import CoreAudio
import Foundation

protocol MicrophoneMonitoring: AnyObject {
  var isMicActive: Bool { get }
  var onChange: ((Bool) -> Void)? { get set }

  func start()
}

final class MicrophoneMonitor: MicrophoneMonitoring {
  private(set) var isMicActive = false
  var onChange: ((Bool) -> Void)?

  private var propertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  private var listenerBlock: AudioObjectPropertyListenerBlock?
  private var inputDeviceListenerBlock: AudioObjectPropertyListenerBlock?
  private var currentInputDeviceID: AudioDeviceID?

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
    removeInputDeviceListener()
    if let listenerBlock {
      var address = propertyAddress
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        DispatchQueue.main,
        listenerBlock
      )
    }
  }

  private func refresh() {
    guard let deviceID = defaultInputDeviceID() else {
      updateState(active: false)
      removeInputDeviceListener()
      return
    }

    if deviceID != currentInputDeviceID {
      removeInputDeviceListener()
      currentInputDeviceID = deviceID
      addInputDeviceListener(for: deviceID)
    }

    let running = isDeviceRunning(deviceID: deviceID)
    updateState(active: running)
  }

  private func updateState(active: Bool) {
    guard active != isMicActive else { return }
    isMicActive = active
    onChange?(active)
  }

  private func defaultInputDeviceID() -> AudioDeviceID? {
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

  private func isDeviceRunning(deviceID: AudioDeviceID) -> Bool {
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
    return status == noErr && running != 0
  }

  private func addInputDeviceListener(for deviceID: AudioDeviceID) {
    let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.refresh()
    }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectAddPropertyListenerBlock(
      deviceID,
      &address,
      DispatchQueue.main,
      block
    )
    // Only record the block if registration succeeded, so removeInputDeviceListener
    // never tries to remove a listener that was never installed (BUG-6).
    inputDeviceListenerBlock = (status == noErr) ? block : nil
  }

  private func removeInputDeviceListener() {
    guard let currentInputDeviceID, let inputDeviceListenerBlock else {
      return
    }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )

    AudioObjectRemovePropertyListenerBlock(
      currentInputDeviceID,
      &address,
      DispatchQueue.main,
      inputDeviceListenerBlock
    )

    self.currentInputDeviceID = nil
    self.inputDeviceListenerBlock = nil
  }
}
