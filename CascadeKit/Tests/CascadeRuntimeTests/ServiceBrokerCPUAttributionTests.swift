//
//  ServiceBrokerCPUAttributionTests.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ServiceBrokerCPUAttributionTests {
    @Test func newInterestPublishesOneLedgerEdgeAndReuseDoesNotDuplicateIt() async throws {
        let fixture = BrokerFixture()
        let ledger = try ledger(for: fixture)
        let binding = metricBinding()
        _ = try ledger.register(binding, physicalOwner: fixture.provider)
        let broker = broker(fixture: fixture, ledger: ledger)
        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        let scope = try ServiceScope(featureID: "main", operation: "read")

        let first = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : scope,
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        let second = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : scope,
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: false
        )

        #expect(first.createdNewConsumerInterest)
        #expect(!second.createdNewConsumerInterest)
        #expect(first.interestID == second.interestID)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        await broker.rollbackAcquisition(second)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
    }

    @Test func rollbackAndTerminalRemovalPreserveOnlyTheOpenIntervalHistory() async throws {
        let fixture = BrokerFixture()
        let ledger = try ledger(for: fixture)
        let binding = metricBinding()
        _ = try ledger.register(binding, physicalOwner: fixture.provider)
        let broker = broker(fixture: fixture, ledger: ledger)
        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        let scope = try ServiceScope(featureID: "main", operation: "read")

        let rolledBack = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : scope,
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        await broker.rollbackAcquisition(rolledBack)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)

        let active = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : scope,
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        _ = try await broker.unsubscribe(session: session, interestID: active.interestID)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
    }

    @Test func pausedNewInterestFailsBeforeReservationsWhileReuseRemainsAvailable() async throws {
        let fixture = BrokerFixture()
        let governor = ResourceGovernor()
        let broker = ServiceBroker(
            governor       : governor,
            resourceAccess : governor
        )
        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        let scope = try ServiceScope(featureID: "main", operation: "read")
        let baseline = await governor.usage(.retainedStateBytes)

        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(
                session                : session,
                requirementID          : "requirement",
                scope                  : scope,
                now                    : fixture.now,
                lifetime               : .seconds(30),
                allowNewSourceStart    : true,
                allowNewConsumerInterest: false
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == baseline)

        _ = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : scope,
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        _ = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : scope,
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: false
        )
    }

    @Test func ledgerFailureDoesNotPublishCanonicalSourceOrRetainReservations() async throws {
        let fixture = BrokerFixture()
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: [fixture.provider])
        let governor = ResourceGovernor()
        let broker = ServiceBroker(
            governor             : governor,
            resourceAccess       : governor,
            cpuAttributionLedger : ledger
        )
        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        let baseline = await governor.usage(.retainedStateBytes)

        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(
                session                : session,
                requirementID          : "requirement",
                scope                  : try ServiceScope(featureID: "main", operation: "read"),
                now                    : fixture.now,
                lifetime               : .seconds(30),
                allowNewSourceStart    : true,
                allowNewConsumerInterest: true
            )
        }
        #expect(await broker.activeSourceIDs().isEmpty)
        #expect(await governor.usage(.retainedStateBytes) == baseline)
    }

    @Test func disconnectAndProviderExitPreserveTheActiveLedgerRelationship() async throws {
        let fixture = BrokerFixture()
        let ledger = try ledger(for: fixture)
        let binding = metricBinding()
        _ = try ledger.register(binding, physicalOwner: fixture.provider)
        let broker = broker(fixture: fixture, ledger: ledger)
        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        let acquired = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : try ServiceScope(featureID: "main", operation: "read"),
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )

        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        await broker.disconnect(session)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        await broker.providerExitedPreservingInterests(fixture.provider)
        #expect(await broker.activeSourceIDs() == Set([acquired.sourceID]))
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
    }

    @Test func brokerChainConservativelyAttributesThePhysicalProviderToAncestors() async throws {
        let fixture = BrokerFixture()
        let middle = fixture.other
        let ledger = try ServiceCPUAttributionLedger(
            authorizedOwners: [fixture.owner, middle, fixture.provider]
        )
        let binding = metricBinding()
        _ = try ledger.register(binding, physicalOwner: fixture.provider)
        let broker = broker(fixture: fixture, ledger: ledger)
        _ = try await broker.authorize(permission(
            consumer     : middle,
            provider     : fixture.provider,
            requirementID: "middle-to-provider"
        ))
        _ = try await broker.authorize(permission(
            consumer     : fixture.owner,
            provider     : middle,
            requirementID: "owner-to-middle"
        ))
        let middleSession = try await broker.registerSession(identity: middle)
        let ownerSession = try await broker.registerSession(identity: fixture.owner)
        _ = try await broker.acquire(
            session                : middleSession,
            requirementID          : "middle-to-provider",
            scope                  : try ServiceScope(featureID: "main", operation: "read"),
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        _ = try await broker.acquire(
            session                : ownerSession,
            requirementID          : "owner-to-middle",
            scope                  : try ServiceScope(featureID: "main", operation: "read"),
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )

        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner, middle])
    }

    @Test func revocationAndShutdownRemoveLedgerMembershipThroughTheCentralPath() async throws {
        let fixture = BrokerFixture()
        let ledger = try ledger(for: fixture)
        let binding = metricBinding()
        _ = try ledger.register(binding, physicalOwner: fixture.provider)
        let broker = broker(fixture: fixture, ledger: ledger)
        let permissionID = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        _ = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : try ServiceScope(featureID: "main", operation: "read"),
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        _ = await broker.revoke(permissionID: permissionID)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)

        _ = try await broker.authorize(fixture.permission())
        _ = try await broker.acquire(
            session                : session,
            requirementID          : "requirement",
            scope                  : try ServiceScope(featureID: "main", operation: "read"),
            now                    : fixture.now,
            lifetime               : .seconds(30),
            allowNewSourceStart    : true,
            allowNewConsumerInterest: true
        )
        _ = await broker.shutdown()
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
        #expect(try ledger.withObservation(for: binding) { $0 }.isEmpty)
    }

    @Test func brokerPublicationWaitsForTheBlockedPhysicalObservation() async throws {
        let fixture = BrokerFixture()
        let ledger = try ledger(for: fixture)
        let binding = metricBinding()
        _ = try ledger.register(binding, physicalOwner: fixture.provider)
        let broker = broker(fixture: fixture, ledger: ledger)
        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        let gate = BrokerObservationGate()
        let recipients = BrokerRecipientBox()

        DispatchQueue(label: "broker-ledger-observation").async {
            defer { gate.finishObservation() }
            do {
                recipients.store(try ledger.withObservation(for: binding) { values in
                    gate.enterObservation()
                    guard gate.waitForRelease() else {
                        Issue.record("Observation release timed out.")
                        return values
                    }
                    return values
                })
            } catch {
                Issue.record("Blocked observation failed: \(error)")
            }
        }
        defer { gate.releaseObservation() }
        guard gate.waitForObservation() else {
            Issue.record("Observation did not enter its synchronous body.")
            return
        }
        let acquiring = Task {
            gate.startAcquisition()
            defer { gate.finishAcquisition() }
            return try await broker.acquire(
                session                : session,
                requirementID          : "requirement",
                scope                  : try ServiceScope(featureID: "main", operation: "read"),
                now                    : fixture.now,
                lifetime               : .seconds(30),
                allowNewSourceStart    : true,
                allowNewConsumerInterest: true
            )
        }
        guard gate.waitForAcquisitionStart() else {
            Issue.record("Acquisition task did not start.")
            return
        }
        #expect(!gate.waitForAcquisitionFinish(within: .milliseconds(20)))
        gate.releaseObservation()
        guard gate.waitForObservationFinish() else {
            Issue.record("Observation did not finish after release.")
            return
        }
        #expect((try await acquiring.value).createdNewConsumerInterest)
        #expect(recipients.value.isEmpty)
        #expect(try ledger.withObservation(for: binding) { $0 } == [fixture.owner])
    }

    private func broker(
        fixture: BrokerFixture,
        ledger : ServiceCPUAttributionLedger
    ) -> ServiceBroker {
        let governor = ResourceGovernor()
        return ServiceBroker(
            governor             : governor,
            resourceAccess       : governor,
            cpuAttributionLedger : ledger
        )
    }

    private func ledger(for fixture: BrokerFixture) throws -> ServiceCPUAttributionLedger {
        try ServiceCPUAttributionLedger(authorizedOwners: [fixture.owner, fixture.provider])
    }

    private func metricBinding() -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid               : 91,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
    }

    private func permission(
        consumer     : VerifiedAddonIdentity,
        provider     : VerifiedAddonIdentity,
        requirementID: String
    ) throws -> HostServicePermission {
        HostServicePermission(
            consumer: consumer,
            binding : ServiceBinding(
                requirementID    : requirementID,
                consumer         : consumer.addonID,
                provider         : provider.addonID,
                providerIdentity : provider,
                contractVersion  : SemanticVersion(1, 0, 0),
                digest           : "sha256-verified",
                featureID        : "main"
            ),
            serviceID             : "test.service",
            partition             : "account-a",
            operation             : "read",
            crossPublisherConsent : true
        )
    }
}

private final class BrokerRecipientBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [VerifiedAddonIdentity] = []

    var value: [VerifiedAddonIdentity] {
        lock.withLock { stored }
    }

    func store(_ recipients: [VerifiedAddonIdentity]) {
        lock.withLock { stored = recipients }
    }
}

private final class BrokerObservationGate: @unchecked Sendable {
    private let observationStarted = DispatchSemaphore(value: 0)
    private let observationRelease = DispatchSemaphore(value: 0)
    private let observationFinished = DispatchSemaphore(value: 0)
    private let acquisitionStarted = DispatchSemaphore(value: 0)
    private let acquisitionFinished = DispatchSemaphore(value: 0)

    func enterObservation() {
        observationStarted.signal()
    }

    func releaseObservation() {
        observationRelease.signal()
    }

    func finishObservation() {
        observationFinished.signal()
    }

    func startAcquisition() {
        acquisitionStarted.signal()
    }

    func finishAcquisition() {
        acquisitionFinished.signal()
    }

    func waitForRelease() -> Bool {
        observationRelease.wait(timeout: .now() + 2) == .success
    }

    func waitForObservation() -> Bool {
        observationStarted.wait(timeout: .now() + 2) == .success
    }

    func waitForObservationFinish() -> Bool {
        observationFinished.wait(timeout: .now() + 2) == .success
    }

    func waitForAcquisitionStart() -> Bool {
        acquisitionStarted.wait(timeout: .now() + 2) == .success
    }

    func waitForAcquisitionFinish(within duration: DispatchTimeInterval) -> Bool {
        acquisitionFinished.wait(timeout: .now() + duration) == .success
    }
}
