//
//  FakeAudioHostConnection.swift
//  CascadeTests
//

import CascadeContracts
import Foundation
import Synchronization
@testable import Cascade

/// FakeAudioHostConnection is the AudioHost link the test plays: it records what the service
/// asked, from which thread, and answers on the test's terms.
///
/// Replies come back inline by default, which is safe because the service only hops onto its own
/// queue from them. A test that wants an unanswered command turns `repliesAutomatically` off,
/// and a test that wants a broken link calls `crash`, as XPC's interruption handler would.
final class FakeAudioHostConnection: AudioHostConnecting, Sendable {

    struct State: Sendable {

        var connectCount        = 0
        var helloCount          = 0
        var disconnectCount     = 0
        var killCount           = 0
        var sent                : [AudioHostCommand] = []
        var footprint           : UInt64?
        var helloPID            : Int32? = 4242
        var repliesAutomatically = true
        var refusesConnect      = false
        var mainThreadCalls     = 0
        var onSnapshot          : (@Sendable (AudioHostSnapshot) -> Void)?
        var onLoss              : (@Sendable () -> Void)?
    }

    private let state = Mutex(State())

    func edit(_ change: (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func read<Value>(_ read: (State) -> Value) -> Value {
        state.withLock { read($0) }
    }

    /// crash plays the link breaking without the service having asked.
    func crash() {
        let onLoss = state.withLock { $0.onLoss }
        onLoss?()
    }

    /// publish plays AudioHost publishing a snapshot.
    func publish(_ snapshot: AudioHostSnapshot) {
        let onSnapshot = state.withLock { $0.onSnapshot }
        onSnapshot?(snapshot)
    }

    func connect(
        onSnapshot: @escaping @Sendable (AudioHostSnapshot) -> Void,
        onLoss    : @escaping @Sendable () -> Void
    ) -> Bool {
        state.withLock { state in
            note(&state)
            state.connectCount += 1
            state.onSnapshot    = onSnapshot
            state.onLoss        = onLoss

            return !state.refusesConnect
        }
    }

    func hello(_ reply: @escaping @Sendable (Int32?) -> Void) {
        let answer = state.withLock { state -> (Bool, Int32?) in
            note(&state)
            state.helloCount += 1

            return (state.repliesAutomatically, state.helloPID)
        }

        if answer.0 {
            reply(answer.1)
        }
    }

    func send(
        _ command: AudioHostCommand,
        reply    : @escaping @Sendable (Bool?) -> Void
    ) {
        let repliesAutomatically = state.withLock { state -> Bool in
            note(&state)
            state.sent.append(command)

            return state.repliesAutomatically
        }

        if repliesAutomatically {
            reply(true)
        }
    }

    func footprint() -> UInt64? {
        state.withLock { state in
            note(&state)

            return state.footprint
        }
    }

    func kill() {
        state.withLock { state in
            note(&state)
            state.killCount += 1
        }
    }

    func disconnect() {
        state.withLock { state in
            note(&state)
            state.disconnectCount += 1
        }
    }

    private func note(_ state: inout State) {
        if Thread.isMainThread {
            state.mainThreadCalls += 1
        }
    }
}
