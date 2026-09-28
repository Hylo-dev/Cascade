//
//  OutputDeviceAccess.swift
//  Cascade
//

import AppKit
import CoreAudio

actor OutputDeviceAccess {

    func selectOutput(_ selected: AudioDeviceID) -> Bool {
        var device  = selected
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )

        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &device
        ) == noErr
    }

    func defaultOutput() -> AudioDeviceID {
        var device : AudioDeviceID = 0
        var size    = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )

        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    func outputDevices() -> [(id: AudioDeviceID, name: String)] {
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
                  streamSize > 0
            else { return nil }

            var property = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope   : kAudioObjectPropertyScopeGlobal,
                mElement : kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let result = withUnsafeMutablePointer(to: &name) {
                AudioObjectGetPropertyData(device, &property, 0, nil, &nameSize, $0)
            }
            guard result == noErr, let name else { return nil }

            return (device, name.takeRetainedValue() as String)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
