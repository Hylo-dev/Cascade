//
//  AudioOutputHAL.swift
//  Cascade
//

import CoreAudio
import Foundation

/// AudioOutputHAL is the one place that reads and writes the HAL's output devices: the device
/// list, the default output and the facts about a device (uid, transport, aggregate members).
/// `OutputDeviceAccess` (the picker's actor) and `CoreAudioSystemHardware` (the volume bar's
/// service) both call it, so neither carries its own copy of the property plumbing.
///
/// Every function is a synchronous HAL call and stateless, so it is `nonisolated` and runs on
/// whatever thread calls it. The callers own that choice: the service calls it on its serial
/// queue, the actor on its executor. None of them may call it on the main thread.
nonisolated enum AudioOutputHAL {

    static func defaultOutputDevice() -> AudioDeviceID {
        var device : AudioDeviceID = 0
        var size    = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultOutputAddress

        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    static func setDefaultOutputDevice(_ selected: AudioDeviceID) -> Bool {
        var device  = selected
        var address = defaultOutputAddress

        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &device
        ) == noErr
    }

    /// outputDevices lists every device with output streams, by name. Aggregates are included:
    /// hiding Cascade's own is a decision of the service, not of the HAL reader.
    static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size <= 65_536
        else { return [] }

        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else { return [] }

        return devices.compactMap { device in
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope   : kAudioDevicePropertyScopeOutput,
                mElement : kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr,
                  streamSize > 0,
                  let name = string(kAudioObjectPropertyName, of: device)
            else { return nil }

            return (device, name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func uid(of device: AudioDeviceID) -> String? {
        string(kAudioDevicePropertyDeviceUID, of: device)
    }

    /// transportType is the raw `kAudioDeviceTransportType*` four-char code, zero if unreadable.
    static func transportType(of device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return 0 }

        return value
    }

    /// device finds the HAL device that owns a uid, or nil when none does.
    static func device(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        var device: AudioDeviceID = kAudioObjectUnknown
        var size    = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cfUID   = uid as CFString

        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                qualifier,
                &size,
                &device
            )
        }
        guard status == noErr, device != kAudioObjectUnknown else { return nil }

        return device
    }

    /// subDeviceUIDs lists the members of an aggregate device in the order it was built, or nil
    /// when the device is not an aggregate (or cannot be read).
    static func subDeviceUIDs(ofAggregate device: AudioDeviceID) -> [String]? {
        var classAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyClass,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        var deviceClass: AudioClassID = 0
        var classSize = UInt32(MemoryLayout<AudioClassID>.size)
        guard AudioObjectGetPropertyData(device, &classAddress, 0, nil, &classSize, &deviceClass) == noErr,
              deviceClass == kAudioAggregateDeviceClassID
        else { return nil }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyFullSubDeviceList,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        var list: Unmanaged<CFArray>?
        var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
        let status = withUnsafeMutablePointer(to: &list) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let list else { return nil }

        return (list.takeRetainedValue() as? [String]) ?? []
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
    }

    private static func string(
        _ selector: AudioObjectPropertySelector,
        of device : AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }

        return value.takeRetainedValue() as String
    }
}
