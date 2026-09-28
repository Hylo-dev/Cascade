//
//  CoreAudioSystemVolume.swift
//  Cascade
//

import CoreAudio
import Foundation
import os

/// CoreAudioSystemVolume owns default-output properties on one serial queue.
/// CoreAudio retains each listener block until the matching remove call. This
/// object keeps the exact address, queue and block together for that teardown.
nonisolated final class CoreAudioSystemVolume: SystemVolumeControlling {
    private struct Registration {
        let objectID: AudioObjectID
        let address : AudioObjectPropertyAddress
        let block   : AudioObjectPropertyListenerBlock
    }

    private struct ScalarControl {
        let element: AudioObjectPropertyElement
        let value  : Float32
    }

    private struct MuteControl {
        let element: AudioObjectPropertyElement
        let value  : UInt32
    }

    private let queue : DispatchQueue
    private let logger = Logger(subsystem: "Cascade", category: "Volume")
    private var registrations: [Registration] = []
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var controls: [ScalarControl] = []
    private var changeHandler: (@Sendable () -> Void)?

    var supportsVolume: Bool {
        guard !controls.isEmpty, let mute = muteControls() else { return false }
        return Set(mute.map { $0.value != 0 }).count <= 1
    }

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// start registers the default-output listener before its silent baseline
    /// so a device switch cannot fall between enumeration and registration.
    func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        stop()
        changeHandler = onChange
        let registered = addListener(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address : Self.defaultOutputAddress,
            block   : { _, _ in onChange() }
        )
        refreshOutput()
        return registered
    }

    /// refreshOutput rebuilds device registrations only when the default
    /// output changes. Unsupported HDMI and fixed-level devices stay untouched.
    func refreshOutput() {
        let output = readUInt32(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address : Self.defaultOutputAddress
        ) ?? kAudioObjectUnknown
        guard output != deviceID else { return }

        removeListeners(keepingSystem: true)
        deviceID = output
        controls = scalarControls()
        guard deviceID != kAudioObjectUnknown, let changeHandler else { return }

        // Wildcard elements observe both a master control and devices exposing
        // independent channels; exact selector listeners avoid audio polling.
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            let address = Self.address(
                selector: selector,
                element : kAudioObjectPropertyElementWildcard
            )
            _ = addListener(
                objectID: deviceID,
                address : address,
                block   : { _, _ in changeHandler() }
            )
        }
    }

    func snapshot() -> SystemVolumeSnapshot? {
        guard deviceID != kAudioObjectUnknown else { return nil }
        controls = scalarControls()
        guard !controls.isEmpty, let mute = muteControls(),
              Set(mute.map { $0.value != 0 }).count <= 1 else { return nil }
        let scalar = controls.reduce(0.0) { $0 + Double($1.value) } / Double(controls.count)
        return SystemVolumeSnapshot(
            deviceID: deviceID,
            scalar  : scalar,
            isMuted : mute.first.map { $0.value != 0 } ?? false
        )
    }

    /// perform validates the live default device before touching it. Writes
    /// are transactional where CoreAudio permits: on an error, restore values
    /// already changed and let macOS receive the original key.
    func perform(
        _ command: VolumeKeyCommand,
        fineStep : Bool
    ) -> Bool {
        refreshOutput()
        guard let current = snapshot(), let mute = muteControls() else { return false }
        if command == .toggleMute {
            return writeMute(current.isMuted ? 0 : 1, controls: mute)
        }

        guard !current.isMuted || mute.allSatisfy({
            isSettable(Self.address(selector: kAudioDevicePropertyMute, element: $0.element))
        }) else { return false }
        let oldControls = controls
        let step = fineStep ? 1.0 / 64 : 1.0 / 16
        let direction = command == .increase ? 1.0 : -1.0
        let target = min(1, max(0, current.scalar + direction * step))
        let delta = target - current.scalar
        var written: [ScalarControl] = []
        for control in oldControls {
            let address = Self.address(selector: kAudioDevicePropertyVolumeScalar, element: control.element)
            let value = Float32(min(1, max(0, Double(control.value) + delta)))
            guard writeFloat(value, address: address) else {
                restore(written)
                return false
            }
            written.append(control)
        }
        if current.isMuted && !writeMute(0, controls: mute) {
            restore(written)
            return false
        }
        return true
    }

    func stop() {
        removeListeners(keepingSystem: false)
        deviceID = kAudioObjectUnknown
        controls = []
        changeHandler = nil
    }

    private func scalarControls() -> [ScalarControl] {
        guard deviceID != kAudioObjectUnknown else { return [] }
        let mainAddress = Self.address(selector: kAudioDevicePropertyVolumeScalar)
        if isSettable(mainAddress), let value = readFloat(mainAddress) {
            return [ScalarControl(element: kAudioObjectPropertyElementMain, value: value)]
        }

        // Preferred stereo channels are the public fallback for output devices
        // without a master scalar. Do not invent a software gain for fixed DACs.
        var result: [ScalarControl] = []
        for element in preferredOutputChannels() {
            var address = Self.address(selector: kAudioDevicePropertyVolumeScalar, element: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            guard isSettable(address), let value = readFloat(address) else { return [] }
            result.append(ScalarControl(element: element, value: value))
        }
        return result
    }

    /// preferredOutputChannels discovers physical channels independently of
    /// scalar controls: a master volume may coexist with per-channel mute.
    private func preferredOutputChannels() -> [AudioObjectPropertyElement] {
        var channels: [UInt32] = [1, 2]
        var address = Self.address(selector: kAudioDevicePropertyPreferredChannelsForStereo)
        var size = UInt32(MemoryLayout<UInt32>.size * channels.count)
        let status = channels.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return kAudioHardwareUnspecifiedError }
            return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, baseAddress)
        }
        if status != noErr { channels = [1, 2] }
        return Set(channels).filter { $0 != kAudioObjectPropertyElementMain }.sorted()
    }

    /// muteControls preserves per-channel mute state when no master exists.
    /// A failed read is unknown, never an invented unmuted state. Mixed channel
    /// mute states are rejected by snapshot because one icon cannot express them.
    private func muteControls() -> [MuteControl]? {
        var mainAddress = Self.address(selector: kAudioDevicePropertyMute)
        let elements: [AudioObjectPropertyElement]
        if AudioObjectHasProperty(deviceID, &mainAddress) {
            elements = [kAudioObjectPropertyElementMain]
        } else {
            elements = preferredOutputChannels()
        }
        var result: [MuteControl] = []
        for element in elements {
            var address = Self.address(selector: kAudioDevicePropertyMute, element: element)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            guard let value = readUInt32(objectID: deviceID, address: address) else { return nil }
            result.append(MuteControl(element: element, value: value))
        }
        return result
    }

    private func writeMute(
        _ value : UInt32,
        controls: [MuteControl]
    ) -> Bool {
        guard !controls.isEmpty, controls.allSatisfy({
            isSettable(Self.address(selector: kAudioDevicePropertyMute, element: $0.element))
        }) else { return false }
        var written: [MuteControl] = []
        for control in controls {
            let address = Self.address(selector: kAudioDevicePropertyMute, element: control.element)
            guard writeUInt32(value, address: address) else {
                for previous in written {
                    _ = writeUInt32(
                        previous.value,
                        address: Self.address(selector: kAudioDevicePropertyMute, element: previous.element)
                    )
                }
                return false
            }
            written.append(control)
        }
        return true
    }

    private func restore(_ controls: [ScalarControl]) {
        for control in controls {
            _ = writeFloat(
                control.value,
                address: Self.address(selector: kAudioDevicePropertyVolumeScalar, element: control.element)
            )
        }
    }

    private func isSettable(_ property: AudioObjectPropertyAddress) -> Bool {
        var address = property
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(deviceID, &address)
            && AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
    }

    private func readFloat(_ property: AudioObjectPropertyAddress) -> Float32? {
        var address = property
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              value.isFinite else { return nil }
        return value
    }

    private func readUInt32(
        objectID: AudioObjectID,
        address : AudioObjectPropertyAddress
    ) -> UInt32? {
        var property = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func writeFloat(
        _ value: Float32,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var property = address
        var scalar = value
        let status = AudioObjectSetPropertyData(deviceID, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar)
        if status != noErr { logger.error("Volume write failed: \(status)") }
        return status == noErr
    }

    private func writeUInt32(
        _ value: UInt32,
        address: AudioObjectPropertyAddress
    ) -> Bool {
        var property = address
        var scalar = value
        let status = AudioObjectSetPropertyData(deviceID, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &scalar)
        if status != noErr { logger.error("Mute write failed: \(status)") }
        return status == noErr
    }

    private func addListener(
        objectID: AudioObjectID,
        address : AudioObjectPropertyAddress,
        block   : @escaping AudioObjectPropertyListenerBlock
    ) -> Bool {
        var property = address
        let status = AudioObjectAddPropertyListenerBlock(objectID, &property, queue, block)
        guard status == noErr else {
            logger.error("Volume listener registration failed: \(status)")
            return false
        }
        registrations.append(Registration(objectID: objectID, address: address, block: block))
        return true
    }

    private func removeListeners(keepingSystem: Bool) {
        var remaining: [Registration] = []
        for registration in registrations {
            if keepingSystem && registration.objectID == AudioObjectID(kAudioObjectSystemObject) {
                remaining.append(registration)
                continue
            }
            var address = registration.address
            let status = AudioObjectRemovePropertyListenerBlock(registration.objectID, &address, queue, registration.block)
            if status != noErr { logger.error("Volume listener removal failed: \(status)") }
        }
        registrations = remaining
    }

    private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope   : kAudioObjectPropertyScopeGlobal,
            mElement : kAudioObjectPropertyElementMain
        )
    }

    private static func address(
        selector: AudioObjectPropertySelector,
        element : AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }
}
