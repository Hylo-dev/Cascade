//
//  FakeSystemAudioHardware.swift
//  CascadeTests
//

import CascadeKit
import CoreAudio
import Foundation
import Synchronization
@testable import Cascade

/// FakeSystemAudioHardware is the audio hardware the test plays: it answers from a table the
/// test edits and records what the service asked, and from which thread.
///
/// Every call runs on whatever thread makes it, like the real hardware. Each one notes whether
/// that thread was the main one, so a test can prove that the service keeps the HAL off main.
final class FakeSystemAudioHardware: SystemAudioHardware, Sendable {

    struct Volume: Sendable {

        var level   : Double
        var isMuted : Bool
        var supports: Bool = true
    }

    struct State: Sendable {

        var devices            : [AudioOutputDevice] = []
        var defaultOutput      : (deviceID: UInt32, uid: String)?
        var volumes            : [UInt32: Volume] = [:]
        var aggregateSubDevices: [String: [String]] = [:]
        var deviceIDs          : [String: UInt32] = [:]

        var setVolumeCalls  : [(level: Double, deviceID: UInt32)] = []
        var setMutedCalls   : [(isMuted: Bool, deviceID: UInt32)] = []
        var setDefaultCalls : [String] = []
        var listenCount     = 0
        var enumerationCount = 0
        var refusesWrites   = false
        var refusesCreate   = false
        var createdAggregates  : [[String]] = []
        var destroyedAggregates: [String] = []
        var operations         : [String] = []
        var stopCount       = 0
        var callCount       = 0
        var mainThreadCalls = 0
        var onDevicesChange : (@Sendable () -> Void)?
        var onVolumeChange  : (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    func edit(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func read<Value>(_ read: (State) -> Value) -> Value {
        state.withLock { read($0) }
    }

    /// fireDevicesChange and fireVolumeChange play the listeners. The test calls them on the
    /// service's queue, where the real listener blocks run.
    func fireDevicesChange() {
        let onChange = state.withLock { $0.onDevicesChange }
        onChange?()
    }

    func fireVolumeChange() {
        let onChange = state.withLock { $0.onVolumeChange }
        onChange?()
    }

    func outputDevices() -> [AudioOutputDevice] {
        state.withLock {
            $0.note()
            $0.enumerationCount += 1
            return $0.devices
        }
    }

    func defaultOutput() -> (deviceID: UInt32, uid: String)? {
        state.withLock {
            $0.note()
            return $0.defaultOutput
        }
    }

    func volume(of deviceID: UInt32) -> (level: Double, isMuted: Bool, supportsVolume: Bool)? {
        state.withLock {
            $0.note()
            guard let volume = $0.volumes[deviceID] else { return nil }

            return (volume.level, volume.isMuted, volume.supports)
        }
    }

    func setVolume(
        _ level : Double,
        of deviceID: UInt32
    ) -> Bool {
        state.withLock {
            $0.note()
            $0.setVolumeCalls.append((level, deviceID))
            return !$0.refusesWrites
        }
    }

    func setMuted(
        _ isMuted: Bool,
        of deviceID: UInt32
    ) -> Bool {
        state.withLock {
            $0.note()
            $0.setMutedCalls.append((isMuted, deviceID))
            return !$0.refusesWrites
        }
    }

    func setDefaultOutput(uid: String) -> Bool {
        state.withLock {
            $0.note()
            $0.setDefaultCalls.append(uid)
            $0.operations.append("default:\(uid)")
            if let deviceID = $0.deviceIDs[uid] { $0.defaultOutput = (deviceID, uid) }
            return true
        }
    }

    /// createMultiOutput plays the HAL: the aggregate joins the device list, with an id and its
    /// members, like a real one.
    func createMultiOutput(subDeviceUIDs: [String]) -> String? {
        state.withLock {
            $0.note()
            guard !$0.refusesCreate else { return nil }

            let uid = "cascade.multi-output.created-\($0.createdAggregates.count)"
            $0.createdAggregates.append(subDeviceUIDs)
            $0.operations.append("create:\(uid)")
            $0.aggregateSubDevices[uid] = subDeviceUIDs
            $0.deviceIDs[uid]           = UInt32(100 + $0.createdAggregates.count)
            $0.devices.append(
                AudioOutputDevice(
                    uid          : uid,
                    name         : "Cascade Multi-Output",
                    transportType: kAudioDeviceTransportTypeAggregate,
                    bluetooth    : nil
                )
            )
            return uid
        }
    }

    /// destroyAggregate removes the aggregate from the list; if it was the default, the system
    /// has no default output until the service sets one, which a test can see.
    func destroyAggregate(uid: String) -> Bool {
        state.withLock {
            $0.note()
            guard $0.aggregateSubDevices[uid] != nil else { return false }

            $0.destroyedAggregates.append(uid)
            $0.operations.append("destroy:\(uid)")
            $0.aggregateSubDevices[uid] = nil
            $0.deviceIDs[uid]           = nil
            $0.devices.removeAll { $0.uid == uid }
            if $0.defaultOutput?.uid == uid { $0.defaultOutput = nil }
            return true
        }
    }

    func aggregateUIDs(withPrefix prefix: String) -> [String] {
        state.withLock {
            $0.note()
            return $0.aggregateSubDevices.keys.filter { $0.hasPrefix(prefix) }.sorted()
        }
    }

    func subDeviceUIDs(ofAggregate uid: String) -> [String]? {
        state.withLock {
            $0.note()
            return $0.aggregateSubDevices[uid]
        }
    }

    func listen(
        onDevicesChange: @escaping @Sendable () -> Void,
        onVolumeChange : @escaping @Sendable () -> Void
    ) {
        state.withLock {
            $0.note()
            $0.listenCount += 1
            $0.onDevicesChange = onDevicesChange
            $0.onVolumeChange  = onVolumeChange
        }
    }

    func stopListening() {
        state.withLock {
            $0.note()
            $0.stopCount += 1
            $0.onDevicesChange = nil
            $0.onVolumeChange  = nil
        }
    }
}

extension FakeSystemAudioHardware.State {

    fileprivate mutating func note() {
        callCount += 1
        if Thread.isMainThread { mainThreadCalls += 1 }
    }
}
