//
//  ServiceBrokerTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct BrokerFixture {

    let owner    = VerifiedAddonIdentity(
        publisher: "publisher",
        addonID  : AddonID(rawValue: "com.test.first")!
    )
    let other    = VerifiedAddonIdentity(
        publisher: "publisher",
        addonID  : AddonID(rawValue: "com.test.second")!
    )
    let provider = VerifiedAddonIdentity(
        publisher: "provider",
        addonID  : AddonID(rawValue: "com.test.provider")!
    )
    let now      = RuntimeInstant(wall: Date(timeIntervalSince1970: 1_000), monotonic: .seconds(10))

    func permission(
        _ consumer: VerifiedAddonIdentity? = nil,
        feature   : String = "main",
        partition : String = "account-a",
        version   : SemanticVersion = SemanticVersion(1, 0, 0),
        consent   : Bool = true
    ) -> HostServicePermission {
        let consumer = consumer ?? owner

        return HostServicePermission(
            consumer             : consumer,
            binding              : ServiceBinding(
                requirementID   : "requirement",
                consumer        : consumer.addonID,
                provider        : provider.addonID,
                providerIdentity: provider,
                contractVersion : version,
                digest          : "sha256-verified",
                featureID       : feature
            ),
            serviceID            : "test.service",
            partition            : partition,
            operation            : "read",
            crossPublisherConsent: consent
        )
    }

    func invocation(operation: String = "read") throws -> ServiceInvocation {
        try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : "test.service",
            operation    : operation,
            payload      : Data([1]),
            deadline     : now.wall.addingTimeInterval(20)
        )
    }
}

func expectServiceResourceDenied<T>(_ operation: () async throws -> T) async throws {
    do {
        _ = try await operation()
        Issue.record("Expected resourceDenied before work admission.")
    } catch let failure as AddonFailure {
        #expect(failure.code == .resourceDenied)
    }
}

extension BrokerFixture {

    func connect(_ broker: ServiceBroker) async throws -> (ServiceSession, ServiceAcquisition) {
        _ = try await broker.authorize(permission())

        let session = try await broker.registerSession(identity: owner)
        let grant   = try await broker.acquire(
            session      : session,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : now,
            lifetime     : .seconds(3_600)
        )

        return (session, grant)
    }
}

@Suite
struct ServiceBrokerTests {

    @Test
    func authorityRevisionExhaustionFailsClosedWithoutWrapping() {
        #expect(ServiceBroker.nextAuthorityRevision(after: UInt64.max - 1) == UInt64.max)
        #expect(ServiceBroker.nextAuthorityRevision(after: UInt64.max) == nil)

        let exhausted = ServiceBroker.advancedAuthorityState(revision: UInt64.max, isExhausted: false)
        #expect(exhausted.revision == UInt64.max)
        #expect(exhausted.isExhausted)

        let stillExhausted = ServiceBroker.advancedAuthorityState(
            revision   : exhausted.revision,
            isExhausted: exhausted.isExhausted
        )
        #expect(stillExhausted.revision == UInt64.max)
        #expect(stillExhausted.isExhausted)
    }

    @Test
    func exhaustedAuthorityRefusesExistingSourceAndInvocationDecisions() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(
            governor                : governor,
            resourceAccess          : governor,
            initialAuthorityRevision: .max
        )
        let (session, acquisition) = try await fixture.connect(broker)
        let work = try await broker.beginInvocation(
            session   : session,
            grantID   : acquisition.grant.id,
            invocation: fixture.invocation(),
            now       : fixture.now
        )

        _ = await broker.expire(now: fixture.now)

        await #expect(throws: AddonFailure.self) {
            try await broker.consumeSourceStart(acquisition.sourceID, now: fixture.now)
        }
        await #expect(throws: AddonFailure.self) {
            try await broker.consumeInvocation(work.id, now: fixture.now)
        }

        _ = await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func canonicalGrantRejectsTheftAndWrongOperation() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        _ = try await broker.authorize(fixture.permission())

        let session  = try await broker.registerSession(identity: fixture.owner)
        let thief    = try await broker.registerSession(identity: fixture.other)
        let acquired = try await broker.acquire(
            session      : session,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : thief,
                grantID   : acquired.grant.id,
                invocation: fixture.invocation(),
                now       : fixture.now
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : acquired.grant.id,
                invocation: fixture.invocation(operation: "write"),
                now       : fixture.now
            )
        }

        let work = try await broker.beginInvocation(
            session   : session,
            grantID   : acquired.grant.id,
            invocation: fixture.invocation(),
            now       : fixture.now
        )
        #expect(work.sourceID == acquired.sourceID)
    }

    @Test
    func compatibleConsumersShareOneSourceAndOnlyLastReleaseStopsIt() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor)
        _ = try await broker.authorize(fixture.permission())
        _ = try await broker.authorize(fixture.permission(fixture.other))

        let firstSession  = try await broker.registerSession(identity: fixture.owner)
        let secondSession = try await broker.registerSession(identity: fixture.other)
        let scope         = try ServiceScope(featureID: "main", operation: "read")
        let first         = try await broker.acquire(
            session      : firstSession,
            requirementID: "requirement",
            scope        : scope,
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        let second = try await broker.acquire(
            session      : secondSession,
            requirementID: "requirement",
            scope        : scope,
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        #expect(first.sourceID == second.sourceID)
        #expect(first.decisions == [.startSource(first.sourceID)])
        #expect(second.decisions.isEmpty)
        #expect(try await broker.unsubscribe(session: firstSession, interestID: first.interestID).isEmpty)

        let stopped = try await broker.unsubscribe(session: secondSession, interestID: second.interestID)
        #expect(stopped == [.stopSource(first.sourceID)])

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func partitionsAndFeatureVersionsNeverShareSources() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        _ = try await broker.authorize(fixture.permission())
        _ = try await broker.authorize(fixture.permission(feature: "second", version: SemanticVersion(2, 0, 0)))
        _ = try await broker.authorize(fixture.permission(fixture.other, partition: "account-b"))

        let firstSession  = try await broker.registerSession(identity: fixture.owner)
        let secondSession = try await broker.registerSession(identity: fixture.other)
        let first         = try await broker.acquire(
            session      : firstSession,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        let second = try await broker.acquire(
            session      : firstSession,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "second", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        let third = try await broker.acquire(
            session      : secondSession,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        #expect(Set([first.sourceID, second.sourceID, third.sourceID]).count == 3)
    }

    @Test
    func disconnectedInterestCoalescesWakeAndReconnectGetsNewGrant() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        _ = try await broker.authorize(fixture.permission())

        let firstSession = try await broker.registerSession(identity: fixture.owner)
        let scope        = try ServiceScope(featureID: "main", operation: "read")
        let first        = try await broker.acquire(
            session      : firstSession,
            requirementID: "requirement",
            scope        : scope,
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        await broker.disconnect(firstSession)
        #expect(await broker.sourceChanged(first.sourceID, now: fixture.now) == [.wakeConsumer(fixture.owner)])
        #expect(await broker.sourceChanged(first.sourceID, now: fixture.now).isEmpty)

        let secondSession = try await broker.registerSession(identity: fixture.owner)
        let second        = try await broker.acquire(
            session      : secondSession,
            requirementID: "requirement",
            scope        : scope,
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        #expect(first.sourceID == second.sourceID)
        #expect(first.interestID == second.interestID)
        #expect(first.grant.id != second.grant.id)
        #expect(first.grant.generation != second.grant.generation)
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : secondSession,
                grantID   : first.grant.id,
                invocation: fixture.invocation(),
                now       : fixture.now
            )
        }
    }

    @Test
    func wholePathAdmissionRejectsBeforeWorkAndReleasesOnlyItsOwnReservations() async throws {
        let fixture   = BrokerFixture()
        let governor  = ResourceGovernor()
        let broker    = ServiceBroker(governor: governor)
        let unrelated = try await governor.admit(.job, owner: fixture.owner.addonID)
        let providers = (1...4).map {
            VerifiedAddonIdentity(publisher: "p", addonID: AddonID(rawValue: "com.test.p\($0)")!)
        }

        try await expectServiceResourceDenied { try await broker.admitPath(providers) }
        #expect(await governor.usage(.providers) == 0)
        #expect(await governor.usage(.jobs) == 1)

        let path = try await broker.admitPath(Array(providers.prefix(3)))
        #expect(await governor.usage(.providers) == 3)
        #expect(await governor.usage(.jobs) == 1)

        await broker.releasePathAfterExit(path.id)
        #expect(await governor.usage(.providers) == 0)

        try await governor.release(unrelated.id, owner: fixture.owner.addonID)
    }

    @Test
    func queuedDecisionsMustBeConsumedCanonicallyAndCannotExecuteAfterRevocation() async throws {
        let fixture    = BrokerFixture()
        let broker     = ServiceBroker()
        let permission = try await broker.authorize(fixture.permission(version: SemanticVersion(2, 0, 0)))
        let session    = try await broker.registerSession(identity: fixture.owner)
        let value      = try await broker.acquire(
            session      : session,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )

        let descriptor = try await broker.consumeSourceStart(value.sourceID, now: fixture.now)
        #expect(descriptor.provider == fixture.provider)
        #expect(descriptor.contractVersion == "2.0.0")
        #expect(descriptor.partition == "account-a")
        await #expect(throws: AddonFailure.self) {
            try await broker.consumeSourceStart(value.sourceID, now: fixture.now)
        }

        let work = try await broker.beginInvocation(
            session   : session,
            grantID   : value.grant.id,
            invocation: fixture.invocation(),
            now       : fixture.now
        )
        #expect(try await broker.consumeInvocation(work.id, now: fixture.now) == value.sourceID)
        await #expect(throws: AddonFailure.self) { try await broker.consumeInvocation(work.id, now: fixture.now) }

        let queued = try await broker.beginInvocation(
            session   : session,
            grantID   : value.grant.id,
            invocation: fixture.invocation(),
            now       : fixture.now
        )
        _ = await broker.revoke(permissionID: permission)
        await #expect(throws: AddonFailure.self) { try await broker.consumeInvocation(queued.id, now: fixture.now) }
        await #expect(throws: AddonFailure.self) {
            try await broker.consumeSourceStart(value.sourceID, now: fixture.now)
        }
    }

    @Test
    func sourceStartQueuedUntilAfterExpiryCannotBeConsumed() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        _ = try await broker.authorize(fixture.permission())

        let session = try await broker.registerSession(identity: fixture.owner)
        let value   = try await broker.acquire(
            session      : session,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        let expired = RuntimeInstant(wall: fixture.now.wall, monotonic: .seconds(41))
        await #expect(throws: AddonFailure.self) { try await broker.consumeSourceStart(value.sourceID, now: expired) }
    }

    @Test
    func concurrentConsumersNeverEmitDuplicateSourceStarts() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor)
        _ = try await broker.authorize(fixture.permission())
        _ = try await broker.authorize(fixture.permission(fixture.other))

        let firstSession  = try await broker.registerSession(identity: fixture.owner)
        let secondSession = try await broker.registerSession(identity: fixture.other)
        let scope         = try ServiceScope(featureID: "main", operation: "read")
        let results       = await withTaskGroup(
            of       : ServiceAcquisition?.self,
            returning: [ServiceAcquisition].self
        ) { group in
            for session in [firstSession, secondSession] {
                group.addTask {
                    try? await broker.acquire(
                        session      : session,
                        requirementID: "requirement",
                        scope        : scope,
                        now          : fixture.now,
                        lifetime     : .seconds(30)
                    )
                }
            }

            var result: [ServiceAcquisition] = []
            for await value in group { if let value { result.append(value) } }
            return result
        }
        #expect(!results.isEmpty)
        #expect(Set(results.map(\.sourceID)).count == 1)
        #expect(results.flatMap(\.decisions).count == 1)

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func defaultOwnerGrantLimitRejectsTheSixtyFifthWithoutAdditionalCharge() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor)
        _ = try await broker.authorize(fixture.permission())

        let session = try await broker.registerSession(identity: fixture.owner)
        let scope   = try ServiceScope(featureID: "main", operation: "read")
        for _ in 0..<64 {
            _ = try await broker.acquire(
                session      : session,
                requirementID: "requirement",
                scope        : scope,
                now          : fixture.now,
                lifetime     : .seconds(30)
            )
        }

        let before = await governor.usage(.retainedStateBytes)
        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(
                session      : session,
                requirementID: "requirement",
                scope        : scope,
                now          : fixture.now,
                lifetime     : .seconds(30)
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == before)

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func shutdownReturnsStopDecisionsAndKeepsProcessAdmissionUntilObservedExit() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor)
        _ = try await broker.authorize(fixture.permission())

        let session = try await broker.registerSession(identity: fixture.owner)
        let value   = try await broker.acquire(
            session      : session,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        let path = try await broker.admitPath([fixture.provider])
        #expect(await broker.shutdown() == [.stopSource(value.sourceID)])
        #expect(await governor.usage(.providers) == 1)

        await broker.releasePathAfterExit(path.id)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func identicalAndChangedLogicalRequestsCannotEmitSecondWork() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        let (session, grant) = try await fixture.connect(broker)
        let request = try fixture.invocation()
        let work    = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: request,
                now       : fixture.now
            )
        }

        let changed = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : request.requestID,
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data([99]),
            deadline     : request.deadline
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: changed,
                now       : fixture.now
            )
        }
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == .pending)

        #expect(try await broker.consumeInvocation(work.id, now: fixture.now) == grant.sourceID)
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == .dispatched)
        await #expect(throws: AddonFailure.self) { try await broker.consumeInvocation(work.id, now: fixture.now) }
    }

    @Test
    func completedLogicalRequestSurvivesReconnectAndRequiresCurrentAuthorityToRecover() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        let (session, grant) = try await fixture.connect(broker)
        let request = try fixture.invocation()
        let work    = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        _ = try await broker.consumeInvocation(work.id, now: fixture.now)

        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data([7])
        )
        _ = try await broker.completeInvocation(
            work.id,
            response: response,
            now     : fixture.now
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: request,
                now       : fixture.now
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await broker.completeInvocation(work.id, response: response, now: fixture.now)
        }

        await broker.disconnect(session)
        let replacement = try await broker.registerSession(identity: fixture.owner)
        let fresh       = try await broker.acquire(
            session      : replacement,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "main", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : replacement,
                grantID   : fresh.grant.id,
                invocation: request,
                now       : fixture.now
            )
        }
        #expect(try await broker.requestOutcome(
            session  : replacement,
            grantID  : fresh.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == .completed(response))
        await #expect(throws: AddonFailure.self) {
            try await broker.requestOutcome(
                session  : session,
                grantID  : grant.grant.id,
                requestID: request.requestID,
                now      : fixture.now
            )
        }

        _ = await broker.disableAddon(fixture.owner)
        await #expect(throws: AddonFailure.self) {
            try await broker.requestOutcome(
                session  : replacement,
                grantID  : fresh.grant.id,
                requestID: request.requestID,
                now      : fixture.now
            )
        }
    }

    @Test
    func disconnectKeepsUnknownAndUnsentRequestsDistinctAndNeverRetriesThem() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        let (session, grant) = try await fixture.connect(broker)
        let sent   = try fixture.invocation()
        let unsent = try fixture.invocation()
        let work   = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: sent,
            now       : fixture.now
        )
        _ = try await broker.consumeInvocation(work.id, now: fixture.now)
        _ = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: unsent,
            now       : fixture.now
        )

        _ = await broker.disableAddon(fixture.owner)
        let (replacement, fresh) = try await fixture.connect(broker)
        #expect(try await broker.requestOutcome(
            session  : replacement,
            grantID  : fresh.grant.id,
            requestID: sent.requestID,
            now      : fixture.now
        ) == .unknown)
        #expect(try await broker.requestOutcome(
            session  : replacement,
            grantID  : fresh.grant.id,
            requestID: unsent.requestID,
            now      : fixture.now
        ) == .unsent)

        for request in [sent, unsent] {
            await #expect(throws: AddonFailure.self) {
                try await broker.beginInvocation(
                    session   : replacement,
                    grantID   : fresh.grant.id,
                    invocation: request,
                    now       : fixture.now
                )
            }
        }

        await #expect(throws: AddonFailure.self) {
            try await broker.completeInvocation(
                work.id,
                response: ServiceResponse(
                    schemaVersion: 1,
                    contractID   : sent.contractID,
                    operation    : sent.operation,
                    payload      : Data([8])
                ),
                now     : fixture.now
            )
        }
        #expect(try await broker.requestOutcome(
            session  : replacement,
            grantID  : fresh.grant.id,
            requestID: sent.requestID,
            now      : fixture.now
        ) == .unknown)
    }

    @Test
    func requestHistoryFailsClosedAtCapacityAndExpiresWithoutReservationLeaks() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor, limits: ServiceBrokerLimits(requestsPerOwner: 1))
        let (session, grant) = try await fixture.connect(broker)
        let baseline = await governor.usage(.retainedStateBytes)
        let request  = try fixture.invocation()
        _ = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )

        let retained = await governor.usage(.retainedStateBytes)
        try await expectServiceResourceDenied {
            try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: fixture.invocation(),
                now       : fixture.now
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == retained)

        let expired = RuntimeInstant(wall: fixture.now.wall.addingTimeInterval(601), monotonic: .seconds(611))
        _ = await broker.expire(now: expired)
        #expect(await governor.usage(.retainedStateBytes) == baseline)
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : expired
        ) == nil)
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: request,
                now       : expired
            )
        }

        let fresh = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data(),
            deadline     : expired.wall.addingTimeInterval(20)
        )
        _ = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: fresh,
            now       : expired
        )

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func commandWindowIsThirtySecondsAndFreshRequestsWorkAfterClockRollback() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        let (session, grant) = try await fixture.connect(broker)
        let request = try fixture.invocation()
        let tooLong = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data(),
            deadline     : fixture.now.wall.addingTimeInterval(31)
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: tooLong,
                now       : fixture.now
            )
        }

        let work = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        _ = try await broker.consumeInvocation(work.id, now: fixture.now)

        let shifted = RuntimeInstant(
            wall     : fixture.now.wall.addingTimeInterval(-5_000),
            monotonic: .seconds(31)
        )
        _ = await broker.expire(now: shifted)
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : shifted
        ) == .unknown)

        let fresh = try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data(),
            deadline     : shifted.wall.addingTimeInterval(20)
        )
        _ = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: fresh,
            now       : shifted
        )
    }

    @Test
    func requestHistoryBindsRecoveryAndAdmissionToCanonicalFeatureAndProvider() async throws {
        let fixture = BrokerFixture()
        let broker  = ServiceBroker()
        let (session, grant) = try await fixture.connect(broker)
        let request = try fixture.invocation()
        let work    = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        _ = try await broker.consumeInvocation(work.id, now: fixture.now)

        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data([4])
        )
        _ = try await broker.completeInvocation(
            work.id,
            response: response,
            now     : fixture.now
        )
        _ = try await broker.authorize(fixture.permission(feature: "other", version: SemanticVersion(2, 0, 0)))

        let other = try await broker.acquire(
            session      : session,
            requirementID: "requirement",
            scope        : ServiceScope(featureID: "other", operation: "read"),
            now          : fixture.now,
            lifetime     : .seconds(30)
        )
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(
                session   : session,
                grantID   : other.grant.id,
                invocation: request,
                now       : fixture.now
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await broker.requestOutcome(
                session  : session,
                grantID  : other.grant.id,
                requestID: request.requestID,
                now      : fixture.now
            )
        }
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == .completed(response))
    }

    @Test
    func responseCapacityIsAdmittedBeforeDispatchAndRemainsAvailableAtFullBudget() async throws {
        let fixture     = BrokerFixture()
        let constrained = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 30_000))
        let small       = ServiceBroker(governor: constrained)
        let (smallSession, smallGrant) = try await fixture.connect(small)
        let before  = await constrained.usage(.retainedStateBytes)
        let request = try fixture.invocation()
        try await expectServiceResourceDenied {
            try await small.beginInvocation(
                session   : smallSession,
                grantID   : smallGrant.grant.id,
                invocation: request,
                now       : fixture.now
            )
        }
        #expect(await constrained.usage(.retainedStateBytes) == before)
        #expect(try await small.requestOutcome(
            session  : smallSession,
            grantID  : smallGrant.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == nil)

        await small.shutdown()
        #expect(await constrained.usage(.retainedStateBytes) == 0)

        let governor = ResourceGovernor()
        let funded   = ServiceBroker(governor: governor)
        let (session, grant) = try await fixture.connect(funded)
        let work = try await funded.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        let used   = await governor.usage(.retainedStateBytes)
        let filler = try await governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - used - 1_024),
            owner: fixture.other.addonID
        )
        _ = try await funded.consumeInvocation(work.id, now: fixture.now)

        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data(repeating: 7, count: 65_536)
        )
        #expect(try await funded.completeInvocation(work.id, response: response, now: fixture.now) == response)
        #expect(try await funded.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == .completed(response))
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024)

        await funded.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 8 * 1_024 * 1_024 - used)

        try await governor.release(filler.id, owner: fixture.other.addonID)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func tinyCompletionReclaimsCapacityAtFullBudgetButPreservesResultAndOriginalHistory() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor)
        let (session, grant) = try await fixture.connect(broker)
        let request = try fixture.invocation()
        let work    = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        #expect(await governor.usage(.retainedStateBytes) == 90_113)

        let filler = try await governor.admit(.state(bytes: 8_297_471), owner: fixture.other.addonID)
        #expect(await governor.usage(.retainedStateBytes) == 8_388_608)

        _ = try await broker.consumeInvocation(work.id, now: fixture.now)
        #expect(await governor.usage(.retainedStateBytes) == 8_388_608)

        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data([7, 8, 9])
        )
        #expect(try await broker.completeInvocation(work.id, response: response, now: fixture.now) == response)
        #expect(await governor.usage(.retainedStateBytes) == 8_323_075)

        let reclaimed = try await governor.admit(.state(bytes: 64_509), owner: fixture.owner.addonID)
        #expect(await governor.usage(.retainedStateBytes) == 8_388_608)

        let beforeExpiry = RuntimeInstant(
            wall     : fixture.now.wall.addingTimeInterval(599),
            monotonic: .seconds(609)
        )
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : beforeExpiry
        ) == .completed(response))

        do {
            _ = try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: request,
                now       : beforeExpiry
            )
            Issue.record("A retained logical request must not emit new work after response compaction.")
        } catch let failure as AddonFailure { #expect(failure.code == .invalidPayload) }

        let expired = RuntimeInstant(wall: fixture.now.wall.addingTimeInterval(600), monotonic: .seconds(610))
        _ = await broker.expire(now: expired)
        #expect(await governor.usage(.retainedStateBytes) == 8_379_388)
        #expect(try await broker.requestOutcome(
            session  : session,
            grantID  : grant.grant.id,
            requestID: request.requestID,
            now      : expired
        ) == nil)

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 8_364_028)

        try await governor.release(filler.id, owner: filler.owner)
        try await governor.release(reclaimed.id, owner: reclaimed.owner)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    private enum TerminalEvent: CaseIterable {

        case disconnect, revoke, disableFeature, disableAddon, providerLoss
        case expire, recoveryTimeout, completionTimeout, validationFailure
    }

    @Test
    func allTerminalEventsRefundOnlyResultCapacityAndKeepReplayAndProcessProtection() async throws {
        for event in TerminalEvent.allCases {
            let fixture    = BrokerFixture()
            let governor   = ResourceGovernor()
            let broker     = ServiceBroker(governor: governor)
            let permission = try await broker.authorize(fixture.permission())
            var session    = try await broker.registerSession(identity: fixture.owner)
            let scope      = try ServiceScope(featureID: "main", operation: "read")
            var grant      = try await broker.acquire(
                session      : session,
                requirementID: "requirement",
                scope        : scope,
                now          : fixture.now,
                lifetime     : .seconds(3_600)
            )
            let path      = try await broker.admitPath([fixture.provider])
            let unrelated = try await governor.admit(.job, owner: fixture.other.addonID)
            let sent      = try fixture.invocation()
            let unsent    = try fixture.invocation()
            let work      = try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: sent,
                now       : fixture.now
            )
            let queued = try await broker.beginInvocation(
                session   : session,
                grantID   : grant.grant.id,
                invocation: unsent,
                now       : fixture.now
            )
            _ = try await broker.consumeInvocation(work.id, now: fixture.now)
            #expect(await governor.usage(.retainedStateBytes) == 166_914)

            let later = RuntimeInstant(wall: fixture.now.wall.addingTimeInterval(21), monotonic: .seconds(31))
            switch event {
                case .disconnect: await broker.disconnect(session)
                case .revoke: _ = await broker.revoke(permissionID: permission)
                case .disableFeature: _ = await broker.disable(consumer: fixture.owner, featureID: "main")
                case .disableAddon: _ = await broker.disableAddon(fixture.owner)
                case .providerLoss: _ = await broker.providerUnavailable(fixture.provider)
                case .expire: _ = await broker.expire(now: later)

                case .recoveryTimeout:
                    for request in [sent, unsent] {
                        _ = try await broker.requestOutcome(
                            session  : session,
                            grantID  : grant.grant.id,
                            requestID: request.requestID,
                            now      : later
                        )
                    }

                case .completionTimeout, .validationFailure:
                    let response = try ServiceResponse(
                        schemaVersion: 1,
                        contractID   : "wrong.contract",
                        operation    : "read",
                        payload      : Data()
                    )
                    for id in [work.id, queued.id] {
                        await #expect(throws: AddonFailure.self) {
                            try await broker.completeInvocation(
                                id,
                                response: response,
                                now     : event == .completionTimeout ? later : fixture.now
                            )
                        }
                    }
            }

            switch event {
                case .disconnect: #expect(await governor.usage(.retainedStateBytes) == 31_746)

                case .revoke, .disableFeature, .providerLoss:
                    #expect(await governor.usage(.retainedStateBytes) == 22_530)

                case .disableAddon: #expect(await governor.usage(.retainedStateBytes) == 20_482)
                default: #expect(await governor.usage(.retainedStateBytes) == 35_842)
            }

            #expect(await governor.usage(.providers) == 1)
            #expect(await governor.usage(.admittedMemoryBytes) == 67_108_864)
            #expect(await governor.usage(.jobs) == 1)

            switch event {
                case .revoke, .disableFeature, .disableAddon, .providerLoss:
                    _ = try await broker.authorize(fixture.permission())

                default: break
            }

            if event == .disconnect || event == .disableAddon {
                session = try await broker.registerSession(identity: fixture.owner)
            }

            switch event {
                case .disconnect, .revoke, .disableFeature, .disableAddon, .providerLoss:
                    grant = try await broker.acquire(
                        session      : session,
                        requirementID: "requirement",
                        scope        : scope,
                        now          : later,
                        lifetime     : .seconds(3_600)
                    )

                default: break
            }

            #expect(await governor.usage(.retainedStateBytes) == 35_842)
            #expect(try await broker.requestOutcome(
                session  : session,
                grantID  : grant.grant.id,
                requestID: sent.requestID,
                now      : later
            ) == .unknown)
            #expect(try await broker.requestOutcome(
                session  : session,
                grantID  : grant.grant.id,
                requestID: unsent.requestID,
                now      : later
            ) == .unsent)

            for request in [sent, unsent] {
                do {
                    _ = try await broker.beginInvocation(
                        session   : session,
                        grantID   : grant.grant.id,
                        invocation: request,
                        now       : later
                    )
                    Issue.record("A terminal request cannot emit a second work decision.")
                } catch let failure as AddonFailure { #expect(failure.code == .invalidPayload) }
            }

            let expiry = RuntimeInstant(
                wall     : fixture.now.wall.addingTimeInterval(600),
                monotonic: .seconds(610)
            )
            _ = await broker.expire(now: expiry)
            #expect(await governor.usage(.retainedStateBytes) == 17_408)

            await broker.shutdown()
            #expect(await governor.usage(.retainedStateBytes) == 2_048)
            #expect(await governor.usage(.providers) == 1)

            await broker.releasePathAfterExit(path.id)
            #expect(await governor.usage(.retainedStateBytes) == 1_024)

            try await governor.release(unrelated.id, owner: unrelated.owner)
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
    }

    @Test
    func concurrentCompletionExpiryAndShutdownNeverResurrectHistoryOrReleaseUnrelatedWork() async throws {
        let fixture  = BrokerFixture()
        let governor = ResourceGovernor()
        let broker   = ServiceBroker(governor: governor)
        let (session, grant) = try await fixture.connect(broker)
        let job     = try await governor.admit(.job, owner: fixture.other.addonID)
        let state   = try await governor.admit(.state(bytes: 100), owner: fixture.owner.addonID)
        let path    = try await broker.admitPath([fixture.provider])
        let request = try fixture.invocation()
        let work    = try await broker.beginInvocation(
            session   : session,
            grantID   : grant.grant.id,
            invocation: request,
            now       : fixture.now
        )
        _ = try await broker.consumeInvocation(work.id, now: fixture.now)

        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID   : request.contractID,
            operation    : request.operation,
            payload      : Data([9])
        )
        let expired = RuntimeInstant(wall: fixture.now.wall.addingTimeInterval(600), monotonic: .seconds(610))
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                do {
                    #expect(
                        try await broker.completeInvocation(work.id, response: response, now: fixture.now) == response
                    )
                } catch let failure as AddonFailure {
                    #expect(failure.code == .sessionRevoked)
                } catch { Issue.record("Unexpected completion error: \(error)") }
            }
            group.addTask { _ = await broker.expire(now: expired) }
            group.addTask { _ = await broker.shutdown() }
            await group.waitForAll()
        }

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 3_172)
        #expect(await governor.usage(.jobs) == 1)
        #expect(await governor.usage(.providers) == 1)

        let (freshSession, freshGrant) = try await fixture.connect(broker)
        #expect(try await broker.requestOutcome(
            session  : freshSession,
            grantID  : freshGrant.grant.id,
            requestID: request.requestID,
            now      : fixture.now
        ) == nil)

        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 3_172)

        await broker.releasePathAfterExit(path.id)
        #expect(await governor.usage(.retainedStateBytes) == 2_148)

        try await governor.release(job.id, owner: job.owner)
        try await governor.release(state.id, owner: state.owner)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}
