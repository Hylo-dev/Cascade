//
//  QuarantineTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct QuarantineTests {

    let addonID = AddonID(rawValue: "com.example.health")!
    let wall    = Date(timeIntervalSince1970: 2_000_000_000)

    func version(
        _ major  : Int = 1,
        publisher: String = "Example Publisher"
    ) throws -> AddonVersionIdentity {
        try AddonVersionIdentity(
            verifiedIdentity: VerifiedAddonIdentity(publisher: publisher, addonID: addonID),
            version         : SemanticVersion(major, 0, 0)
        )
    }

    func instant(_ seconds: Double) -> RuntimeInstant {
        RuntimeInstant(wall: wall.addingTimeInterval(seconds), monotonic: .seconds(seconds))
    }

    @Test
    func thirdModerateViolationWithinClosedFiveMinuteWindowQuarantines() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)
        let session = try store.bind(release, generation: ConnectionGeneration())

        #expect(try store.record(.moderate, from: session, at: instant(0)) == .keep)
        #expect(try store.record(.moderate, from: session, at: instant(120)) == .keep)
        #expect(try store.record(.moderate, from: session, at: instant(300)) == .quarantine)
        #expect(store.snapshot(for: release)?.isQuarantined == true)
    }

    @Test
    func incidentOlderThanFiveMinutesFallsOutWithoutGrowingHistory() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)
        let session = try store.bind(release, generation: ConnectionGeneration())

        #expect(try store.record(.moderate, from: session, at: instant(0)) == .keep)
        #expect(try store.record(.moderate, from: session, at: instant(120)) == .keep)
        #expect(try store.record(.moderate, from: session, at: instant(300.001)) == .keep)
        #expect(store.snapshot(for: release)?.moderateIncidentCount == 2)
        #expect(store.snapshot(for: release)?.isQuarantined == false)
    }

    @Test
    func severeViolationStopsCurrentSessionImmediately() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)
        let session = try store.bind(release, generation: ConnectionGeneration())

        #expect(try store.record(.severe, from: session, at: instant(1)) == .stop)
        #expect(try store.record(.moderate, from: session, at: instant(2)) == nil)
        #expect(store.snapshot(for: release)?.isQuarantined == false)
    }

    @Test
    func publisherOriginCannotSelectDifferentHealthThresholds() throws {
        for publisher in ["Cascade Team", "External Publisher"] {
            var store   = AddonHealthStore()
            let release = try version(publisher: publisher)
            _ = try store.register(release)
            let session = try store.bind(release, generation: ConnectionGeneration())

            #expect(try store.record(.moderate, from: session, at: instant(0)) == .keep)
            #expect(try store.record(.moderate, from: session, at: instant(1)) == .keep)
            #expect(try store.record(.moderate, from: session, at: instant(2)) == .quarantine)
        }
    }

    @Test
    func crashRetriesUseOneFiveThirtySecondDeadlinesAndConsumeOnce() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)

        for (crashTime, expectedDeadline) in [(10.0, 11.0), (20.0, 25.0), (30.0, 60.0)] {
            let session = try store.bind(release, generation: ConnectionGeneration())
            guard case .retryAt(let retry) = try store.crashed(
                session,
                demandExists: true,
                at          : instant(crashTime)
            ) else {
                Issue.record("A demanded crash must issue the next bounded retry")
                return
            }

            #expect(retry.deadline == .seconds(expectedDeadline))
            #expect(store.nextDeadline == .seconds(expectedDeadline))
            #expect(try store.consume(
                retry,
                demandExists: true,
                isEnabled   : true,
                at          : instant(expectedDeadline - 0.001)
            ) == false)
            #expect(
                try store.consume(retry, demandExists: true, isEnabled: true, at: instant(expectedDeadline)) == true
            )
            #expect(
                try store.consume(retry, demandExists: true, isEnabled: true, at: instant(expectedDeadline)) == false
            )
        }

        let finalSession = try store.bind(release, generation: ConnectionGeneration())
        #expect(try store.crashed(finalSession, demandExists: true, at: instant(70)) == .quarantine)
        #expect(store.nextDeadline == nil)
    }

    @Test
    func retryRequiresDemandAndDisableCancelsLateCallbacks() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)

        let idleSession = try store.bind(release, generation: ConnectionGeneration())
        #expect(try store.crashed(idleSession, demandExists: false, at: instant(1)) == .stop)
        #expect(store.nextDeadline == nil)

        let demandedSession = try store.bind(release, generation: ConnectionGeneration())
        guard case .retryAt(let noDemandRetry) = try store.crashed(
            demandedSession,
            demandExists: true,
            at          : instant(2)
        ) else {
            Issue.record("A demanded crash must schedule a retry")
            return
        }

        #expect(try store.consume(noDemandRetry, demandExists: false, isEnabled: true, at: instant(3)) == false)
        #expect(try store.consume(noDemandRetry, demandExists: true, isEnabled: true, at: instant(3)) == false)

        let disabledSession = try store.bind(release, generation: ConnectionGeneration())
        guard case .retryAt(let disabledRetry) = try store.crashed(
            disabledSession,
            demandExists: true,
            at          : instant(4)
        ) else {
            Issue.record("A demanded crash must schedule a retry")
            return
        }

        store.cancel(owner: addonID)
        #expect(store.nextDeadline == nil)
        #expect(try store.consume(disabledRetry, demandExists: true, isEnabled: true, at: instant(9)) == false)
        #expect(try store.record(.moderate, from: disabledSession, at: instant(9)) == nil)
    }

    @Test
    func lateRetryConsumptionAdvancesVersionMonotonicTime() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)

        let failedSession = try store.bind(release, generation: ConnectionGeneration())
        guard case .retryAt(let retry) = try store.crashed(
            failedSession,
            demandExists: true,
            at          : instant(1)
        ) else {
            Issue.record("A demanded crash must schedule a retry")
            return
        }

        #expect(try store.consume(retry, demandExists: true, isEnabled: true, at: instant(10)) == true)

        let replacementSession = try store.bind(release, generation: ConnectionGeneration())

        #expect(throws: AddonFailure.self) {
            try store.record(.moderate, from: replacementSession, at: instant(9))
        }
        #expect(store.snapshot(for: release)?.moderateIncidentCount == 0)
    }

    @Test
    func staleGenerationCannotMutateReplacementVersionOrConsumeItsRetry() throws {
        var store       = AddonHealthStore()
        let first       = try version(1)
        let replacement = try version(2)
        _ = try store.register(first)
        _ = try store.register(replacement)

        let oldSession = try store.bind(first, generation: ConnectionGeneration())
        guard case .retryAt(let oldRetry) = try store.crashed(
            oldSession,
            demandExists: true,
            at          : instant(0)
        ) else {
            Issue.record("A demanded crash must schedule a retry")
            return
        }

        let newSession = try store.bind(replacement, generation: ConnectionGeneration())
        #expect(try store.record(.moderate, from: oldSession, at: instant(1)) == nil)
        #expect(try store.consume(oldRetry, demandExists: true, isEnabled: true, at: instant(1)) == false)
        #expect(try store.record(.moderate, from: newSession, at: instant(1)) == .keep)
        #expect(store.snapshot(for: first)?.moderateIncidentCount == 0)
        #expect(store.snapshot(for: replacement)?.moderateIncidentCount == 1)
    }

    @Test
    func resettingQuarantinedOldVersionDoesNotInvalidateActiveReplacement() throws {
        var store       = AddonHealthStore()
        let first       = try version(1)
        let replacement = try version(2)
        _ = try store.register(first)
        _ = try store.register(replacement)

        let firstSession = try store.bind(first, generation: ConnectionGeneration())
        _ = try store.record(
            .moderate,
            from: firstSession,
            at  : instant(0)
        )
        _ = try store.record(
            .moderate,
            from: firstSession,
            at  : instant(1)
        )
        _ = try store.record(
            .moderate,
            from: firstSession,
            at  : instant(2)
        )

        let replacementSession = try store.bind(replacement, generation: ConnectionGeneration())

        #expect(store.administrativelyReset(first) == true)
        #expect(try store.record(.moderate, from: replacementSession, at: instant(3)) == .keep)
        #expect(store.snapshot(for: first)?.isQuarantined == false)
        #expect(store.snapshot(for: replacement)?.moderateIncidentCount == 1)
    }

    @Test
    func recordsAndAccountIndexAreChargedAndCapacityNeverEvictsQuarantine() throws {
        var store = AddonHealthStore(maximumRecords: 1, maximumRetainedBytes: 8 * 1_024)

        let first = try version(1)
        _ = try store.register(first)
        let registrationBytes = store.retainedBytes
        let session           = try store.bind(first, generation: ConnectionGeneration())
        #expect(store.retainedBytes > registrationBytes)

        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(0)
        )
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(1)
        )
        #expect(try store.record(.moderate, from: session, at: instant(2)) == .quarantine)

        #expect(throws: AddonFailure.self) { try store.register(version(2)) }
        #expect(store.snapshot(for: first)?.isQuarantined == true)
        #expect(store.count == 1)
        #expect(store.retainedBytes <= 8 * 1_024)
    }

    @Test
    func byteCapacityRefusesAdmissionWithoutPartialState() throws {
        var store = AddonHealthStore(maximumRecords: 4, maximumRetainedBytes: 1)

        #expect(throws: AddonFailure.self) { try store.register(version()) }
        #expect(store.count == 0)
        #expect(store.retainedBytes == 0)
    }

    @Test
    func reregisterDoesNotResetQuarantineButAdministrationCan() throws {
        var store   = AddonHealthStore()
        let release = try version()
        _ = try store.register(release)

        let session = try store.bind(release, generation: ConnectionGeneration())
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(0)
        )
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(1)
        )
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(2)
        )

        #expect(try store.register(release).isQuarantined == true)
        #expect(throws: AddonFailure.self) { try store.bind(release, generation: ConnectionGeneration()) }
        #expect(store.administrativelyReset(release) == true)
        #expect(try store.register(release).isQuarantined == false)

        _ = try store.bind(release, generation: ConnectionGeneration())
    }

    @Test
    func versionIdentityRejectsUnvalidatedPublisherAndSemanticVersion() throws {
        #expect(throws: AddonFailure.self) {
            try AddonVersionIdentity(
                verifiedIdentity: VerifiedAddonIdentity(publisher: "", addonID: addonID),
                version         : SemanticVersion(1, 0, 0)
            )
        }
        #expect(throws: AddonFailure.self) {
            try AddonVersionIdentity(
                verifiedIdentity: VerifiedAddonIdentity(publisher: "Example Publisher", addonID: addonID),
                version         : SemanticVersion(-1, 0, 0)
            )
        }
    }

    @Test
    func noncanonicalVersionCannotAliasQuarantinedCanonicalVersion() throws {
        var store     = AddonHealthStore()
        let canonical = try AddonVersionIdentity(
            verifiedIdentity: VerifiedAddonIdentity(publisher: "Example Publisher", addonID: addonID),
            version         : SemanticVersion(1, 0, 0, prerelease: "alpha", buildMetadata: "build")
        )

        _ = try store.register(canonical)
        let session = try store.bind(canonical, generation: ConnectionGeneration())
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(0)
        )
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(1)
        )
        _ = try store.record(
            .moderate,
            from: session,
            at  : instant(2)
        )

        #expect(throws: AddonFailure.self) {
            try AddonVersionIdentity(
                verifiedIdentity: VerifiedAddonIdentity(publisher: "Example Publisher", addonID: addonID),
                version         : SemanticVersion(1, 0, 0, prerelease: "alpha+build")
            )
        }

        let alternateBuild = try AddonVersionIdentity(
            verifiedIdentity: VerifiedAddonIdentity(publisher: "Example Publisher", addonID: addonID),
            version         : SemanticVersion(1, 0, 0, prerelease: "alpha", buildMetadata: "other")
        )
        #expect(try store.register(alternateBuild).isQuarantined == true)
        #expect(store.count == 1)
    }
}
