//
//  OutputDeviceAccess.swift
//  Cascade
//

import AppKit
import CoreAudio

/// OutputDeviceAccess keeps the output picker's HAL calls off the main actor. The calls
/// themselves live in `AudioOutputHAL`, which the volume bar's service shares.
actor OutputDeviceAccess {

    func selectOutput(_ selected: AudioDeviceID) -> Bool {
        AudioOutputHAL.setDefaultOutputDevice(selected)
    }

    func defaultOutput() -> AudioDeviceID {
        AudioOutputHAL.defaultOutputDevice()
    }

    func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        AudioOutputHAL.outputDevices()
    }
}
