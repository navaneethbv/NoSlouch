import CoreAudio
import Foundation

protocol AudioOutputMonitoring: AnyObject {
    var airPodsActive: Bool { get }
    var onChange: ((Bool) -> Void)? { get set }

    func start()
}

final class AudioOutputMonitor: AudioOutputMonitoring {
    private(set) var airPodsActive = false
    var onChange: ((Bool) -> Void)?

    private let queue = DispatchQueue(label: "NoSlouch.AudioOutputMonitor")
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
            queue,
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
            queue,
            listenerBlock
        )
    }

    private func refresh() {
        let active = defaultOutputName().map(Self.isAirPodsName) ?? false
        guard active != airPodsActive else {
            return
        }

        airPodsActive = active
        onChange?(active)
    }

    private func defaultOutputName() -> String? {
        var address = propertyAddress
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

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

        return stringProperty(kAudioObjectPropertyName, for: deviceID)
            ?? stringProperty(kAudioDevicePropertyDeviceUID, for: deviceID)
    }

    private func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size > 0
        else {
            return nil
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<CFString>.alignment
        )
        defer {
            buffer.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            buffer
        )

        guard status == noErr else {
            return nil
        }

        let value = buffer.load(as: CFString.self)
        return value as String
    }

    private static func isAirPodsName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("airpods") || lowercased.contains("beats fit pro")
    }
}
