//
//  SharedDrainObservation.swift
//  CascadeKit
//

@testable import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing

/// SharedDrainObservation records SDK entry and return without scheduling an actor job.
/// Only the test coordinator waits for observations; observed callers are never held here.
final class SharedDrainObservation: @unchecked Sendable {

    enum Caller: CaseIterable, Hashable, Sendable {

        case firstClose
        case secondClose
        case mutation
    }

    private let lock                = NSLock()
    private var participants       : Set<Caller> = []
    private var returned           : Set<Caller> = []
    private var premature          : Set<Caller> = []
    private var completionSnapshot : Set<Caller>?
    private var awaitedParticipants: Set<Caller> = []
    private var waiter             : CheckedContinuation<Void, Never>?

    var returnedCallers            : Set<Caller> { lock.withLock { returned } }
    var earlyReturns               : Set<Caller> { lock.withLock { premature } }
    var callersAtPhysicalCompletion: Set<Caller>? { lock.withLock { completionSnapshot } }

    func entered(_ caller: Caller) {
        let continuation = lock.withLock {
            participants.insert(caller)
            guard awaitedParticipants.isSubset(of: participants) else {
                return nil as CheckedContinuation<Void, Never>?
            }

            defer { waiter = nil }

            return waiter
        }

        continuation?.resume()
    }

    func returned(_ caller: Caller) {
        lock.withLock {
            returned.insert(caller)
            if completionSnapshot == nil { premature.insert(caller) }
        }
    }

    func physicalCloseCompleted() {
        lock.withLock { completionSnapshot = returned }
    }

    /// waitFor acknowledges distinct callers, not invocation count: a mutation can rejoin
    /// drain during conclusion and must never stand in for a missing second close caller.
    func waitFor(_ callers: Set<Caller>) async {
        await withCheckedContinuation { continuation in
            let alreadyEntered = lock.withLock {
                if callers.isSubset(of: participants) { return true }

                precondition(waiter == nil, "Only one test coordinator may wait.")
                awaitedParticipants = callers
                waiter              = continuation

                return false
            }

            if alreadyEntered { continuation.resume() }
        }
    }
}
