//
//  FakeSystemAudioHardware.swift
//  CascadeTests
//

import CascadeKit
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

        var setVolumeCalls  : [(level: Double, deviceID: UInt32)] = []
        var setMutedCalls   : [(isMuted: Bool, deviceID: UInt32)] = []
        var setDefaultCalls : [String] = []
        var listenCount     = 0
        var stopCount       = 0
        var callCount       = 0
        var mainThreadCalls = 0
        var onChange        : (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    func edit(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func read<Value>(_ read: (State) -> Value) -> Value {
        state.withLock { read($0) }
    }

    /// fireChange plays a listener callback. The test calls it on the service's queue, where the
    /// real listener blocks run.
    func fireChange() {
        let onChange = state.withLock { $0.onChange }
        onChange?()
    }

    func outputDevices() -> [AudioOutputDevice] {
        state.withLock {
            $0.note()
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
            return true
        }
    }

    func setMuted(
        _ isMuted: Bool,
        of deviceID: UInt32
    ) -> Bool {
        state.withLock {
            $0.note()
            $0.setMutedCalls.append((isMuted, deviceID))
            return true
        }
    }

    func setDefaultOutput(uid: String) -> Bool {
        state.withLock {
            $0.note()
            $0.setDefaultCalls.append(uid)
            return true
        }
    }

    func subDeviceUIDs(ofAggregate uid: String) -> [String]? {
        state.withLock {
            $0.note()
            return $0.aggregateSubDevices[uid]
        }
    }

    func listen(_ onChange: @escaping @Sendable () -> Void) {
        state.withLock {
            $0.note()
            $0.listenCount += 1
            $0.onChange = onChange
        }
    }

    func stopListening() {
        state.withLock {
            $0.note()
            $0.stopCount += 1
            $0.onChange = nil
        }
    }
}

extension FakeSystemAudioHardware.State {

    fileprivate mutating func note() {
        callCount += 1
        if Thread.isMainThread { mainThreadCalls += 1 }
    }
}
