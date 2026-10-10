//
//  CoreAudioSystemHardware.swift
//  Cascade
//

import CascadeKit
import CoreAudio
import Foundation
import os

/// CoreAudioSystemHardware is `SystemAudioHardware` over Core Audio. Volume and mute go through
/// `CoreAudioSystemVolume`, which already owns the default output's controls and listeners and
/// knows the multi-output aggregate; devices and the default output go through `AudioOutputHAL`,
/// the reading code the output picker shares.
///
/// It is built for one serial queue and is only ever called on it. The queue is also the queue
/// every listener block is registered on, so a callback never races a call. That confinement is
/// the reason for the unchecked `Sendable`: the protocol asks for `Sendable` so the service can
/// hold it across isolation domains, but the mutable state below (the listener registrations and
/// the volume object) is touched by that one queue and nothing else.
nonisolated final class CoreAudioSystemHardware: SystemAudioHardware, @unchecked Sendable {

    private let queue : DispatchQueue
    private let volume: CoreAudioSystemVolume
    private let logger = Logger(subsystem: "Cascade", category: "SystemAudio")

    private var devicesListener: AudioObjectPropertyListenerBlock?

    init(queue: DispatchQueue) {
        self.queue  = queue
        self.volume = CoreAudioSystemVolume(queue: queue)
    }

    func outputDevices() -> [AudioOutputDevice] {
        AudioOutputHAL.outputDevices().compactMap { device in
            guard let uid = AudioOutputHAL.uid(of: device.id) else { return nil }

            return AudioOutputDevice(
                uid          : uid,
                name         : device.name,
                transportType: AudioOutputHAL.transportType(of: device.id),
                bluetooth    : nil
            )
        }
    }

    func defaultOutput() -> (deviceID: UInt32, uid: String)? {
        let device = AudioOutputHAL.defaultOutputDevice()
        guard device != kAudioObjectUnknown, let uid = AudioOutputHAL.uid(of: device) else { return nil }

        return (device, uid)
    }

    /// volume answers for the default output only. A snapshot of nil on the default output is
    /// an output with no usable volume control (HDMI, a fixed-level DAC), not a failure.
    func volume(of deviceID: UInt32) -> (level: Double, isMuted: Bool, supportsVolume: Bool)? {
        volume.refreshOutput()
        if let snapshot = volume.snapshot() {
            guard snapshot.deviceID == deviceID else { return nil }

            return (snapshot.scalar, snapshot.isMuted, true)
        }
        guard AudioOutputHAL.defaultOutputDevice() == deviceID else { return nil }

        return (0, false, false)
    }

    func setVolume(
        _ level    : Double,
        of deviceID: UInt32
    ) -> Bool {
        guard AudioOutputHAL.defaultOutputDevice() == deviceID else { return false }

        return volume.setScalar(level)
    }

    func setMuted(
        _ isMuted  : Bool,
        of deviceID: UInt32
    ) -> Bool {
        guard AudioOutputHAL.defaultOutputDevice() == deviceID else { return false }

        return volume.setMuted(isMuted)
    }

    func setDefaultOutput(uid: String) -> Bool {
        guard let device = AudioOutputHAL.device(forUID: uid) else { return false }

        return AudioOutputHAL.setDefaultOutputDevice(device)
    }

    func subDeviceUIDs(ofAggregate uid: String) -> [String]? {
        guard let device = AudioOutputHAL.device(forUID: uid) else { return nil }

        return AudioOutputHAL.subDeviceUIDs(ofAggregate: device)
    }

    /// listen watches the default output and the device list (`onDevicesChange`) and the
    /// controls of the device behind the default output (`onVolumeChange`, through the volume
    /// object, which rebuilds its device listeners when the default moves). Before a switch of
    /// output is reported, the volume object looks at the new default, so its listeners are on
    /// the new device before the service reads it.
    func listen(
        onDevicesChange: @escaping @Sendable () -> Void,
        onVolumeChange : @escaping @Sendable () -> Void
    ) {
        stopListening()

        let didStart = volume.start(
            onChange      : onVolumeChange,
            onOutputChange: { [weak self] in
                self?.volume.refreshOutput()
                onDevicesChange()
            }
        )
        if !didStart { logger.error("Default output listener was not registered") }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in onDevicesChange() }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
        if status == noErr {
            devicesListener = block
        } else {
            logger.error("Device list listener registration failed: \(status)")
        }
    }

    func stopListening() {
        volume.stop()

        guard let block = devicesListener else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
        let status = AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            block
        )
        if status != noErr { logger.error("Device list listener removal failed: \(status)") }
        devicesListener = nil
    }
}
