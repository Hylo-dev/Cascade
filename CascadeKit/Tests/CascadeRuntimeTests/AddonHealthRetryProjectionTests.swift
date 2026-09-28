//
//  AddonHealthRetryProjectionTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonHealthRetryProjectionTests {
    private let wall = Date(timeIntervalSince1970: 2_000_000_000)

    private func identity(_ suffix: String, version: Int = 1) throws -> AddonVersionIdentity {
        try AddonVersionIdentity(
            verifiedIdentity: VerifiedAddonIdentity(
                publisher: "Example Publisher",
                addonID: AddonID(rawValue: "com.example.\(suffix)")!
            ),
            version: SemanticVersion(version, 0, 0)
        )
    }

    private func instant(_ seconds: Double) -> RuntimeInstant {
        RuntimeInstant(
            wall: wall.addingTimeInterval(seconds),
            monotonic: .seconds(seconds)
        )
    }

    private func retry(
        _ store: inout AddonHealthStore,
        identity: AddonVersionIdentity,
        at seconds: Double
    ) throws -> AddonRetryTicket {
        _ = try store.register(identity)
        let session = try store.bind(identity, generation: ConnectionGeneration())
        guard case .retryAt(let ticket) = try store.crashed(
            session,
            demandExists: true,
            at: instant(seconds)
        ) else {
            Issue.record("A demanded crash must issue a retry ticket.")
            throw AddonFailure(code: .invalidPayload, reason: "Missing retry ticket.")
        }
        return ticket
    }

    @Test func pendingRetryProjectionIsBoundedOrderedAndDropsConsumedTickets() throws {
        var store = AddonHealthStore()
        #expect(store.pendingRetryTickets.isEmpty)

        let first = try retry(&store, identity: identity("first"), at: 0)
        #expect(store.pendingRetryTickets == [first])

        let second = try retry(&store, identity: identity("second"), at: 10)
        #expect(store.pendingRetryTickets == [first, second])
        #expect(try store.consume(
            first,
            demandExists: true,
            isEnabled: true,
            at: instant(1)
        ))
        #expect(store.pendingRetryTickets == [second])
    }

    @Test func cancelPendingRetriesKeepsSessionsAndDurableHealthState() throws {
        var store = AddonHealthStore()
        let firstRetry = try retry(&store, identity: identity("retry-first"), at: 0)
        _ = try retry(&store, identity: identity("retry-second"), at: 10)

        let history = try identity("history")
        _ = try store.register(history)
        let historySession = try store.bind(history, generation: ConnectionGeneration())
        #expect(try store.record(.moderate, from: historySession, at: instant(0)) == .keep)
        #expect(try store.record(.moderate, from: historySession, at: instant(1)) == .keep)

        let quarantined = try identity("quarantined")
        _ = try store.register(quarantined)
        let quarantinedSession = try store.bind(quarantined, generation: ConnectionGeneration())
        _ = try store.record(.moderate, from: quarantinedSession, at: instant(0))
        _ = try store.record(.moderate, from: quarantinedSession, at: instant(1))
        #expect(try store.record(.moderate, from: quarantinedSession, at: instant(2)) == .quarantine)

        let active = try identity("active")
        _ = try store.register(active)
        let activeSession = try store.bind(active, generation: ConnectionGeneration())
        let retainedBytes = store.retainedBytes

        store.cancelPendingRetries()

        #expect(store.pendingRetryTickets.isEmpty)
        #expect(store.nextDeadline == nil)
        #expect(store.retainedBytes == retainedBytes)
        #expect(store.snapshot(for: firstRetry.version)?.crashRetryCount == 1)
        #expect(store.snapshot(for: history)?.moderateIncidentCount == 2)
        #expect(store.snapshot(for: history)?.crashRetryCount == 0)
        #expect(store.snapshot(for: quarantined)?.isQuarantined == true)
        #expect(try store.record(.moderate, from: activeSession, at: instant(3)) == .keep)
        #expect(try store.consume(
            firstRetry,
            demandExists: true,
            isEnabled: true,
            at: instant(1)
        ) == false)
    }
}
