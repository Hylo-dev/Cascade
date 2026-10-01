//
//  ProcessMetricsLedgerIntegrationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ProcessMetricsLedgerIntegrationTests {
    @Test func transitiveDiamondChargesEachVerifiedOwnerOncePerPhysicalRead() async throws {
        let owners = try identities("a", "b", "c", "d")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let source = LedgerReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1)),
            .sample(observation(binding, cpu: 120_000_000, window: 2))
        ]])
        let coordinator = ProcessMetricsCoordinator(attributionLedger: ledger, read: source.read)
        _ = try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[1], provider: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[1])
        _ = try ledger.addInterest(UUID(), consumer: owners[3], provider: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[3])
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero)
        let batch = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1))
        #expect(source.bindings == [binding, binding])
        #expect(batch.samples.count == 1)
        #expect(batch.samples[0].chargedOwners == owners)
        #expect(batch.cpuAccounting.count == 4)
        for owner in owners {
            let account = try #require(batch.cpuAccounting.first(where: { $0.owner == owner }))
            guard case .complete(let snapshot) = account.result else {
                Issue.record("Every contributor needs one complete budget result.")
                return
            }
            #expect(snapshot.balance == .milliseconds(-20))
            #expect(account.classification == .moderate)
        }
    }

    @Test func interestBornAndRetiredBetweenReadsChargesOnlyThatInterval() async throws {
        let owners = try identities("a", "b", "c")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let source = LedgerReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1)),
            .sample(observation(binding, cpu: 30_000_000, window: 2)),
            .sample(observation(binding, cpu: 50_000_000, window: 3))
        ]])
        let coordinator = ProcessMetricsCoordinator(attributionLedger: ledger, read: source.read)
        _ = try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[0])
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero)
        let first = UUID()
        let second = UUID()
        _ = try ledger.addInterest(first, consumer: owners[1], provider: owners[0])
        _ = try ledger.addInterest(second, consumer: owners[2], provider: owners[1])
        #expect(ledger.removeInterest(first))
        #expect(ledger.removeInterest(second))
        let overlapped = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1))
        #expect(overlapped.samples[0].chargedOwners == owners)
        let later = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(2))
        #expect(later.samples[0].chargedOwners == [owners[0]])
        #expect(later.cpuAccounting.map(\.owner) == [owners[0]])
        #expect(source.bindings.count == 3)
    }

    @Test func unavailableReductionRetainsExactContributorProvenanceAndRetiresTerminalRow() async throws {
        let owners = try identities("a", "b", "c")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let source = LedgerReadSource([binding.token: [
            .unavailable(.readFailed(5)),
            .unavailable(.exited)
        ]])
        let coordinator = ProcessMetricsCoordinator(attributionLedger: ledger, read: source.read)
        _ = try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[1], provider: owners[0])
        _ = try ledger.addInterest(UUID(), consumer: owners[2], provider: owners[1])
        let unavailable = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero)
        #expect(unavailable.samples[0].chargedOwners == owners)
        #expect(unavailable.cpuAccounting.map(\.result) == Array(repeating: .incomplete, count: 3))
        let exit = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1))
        #expect(exit.samples[0].chargedOwners == owners)
        #expect(await coordinator.registeredCount == 0)
        #expect(await coordinator.nextDeadline == nil)
        #expect(throws: ServiceCPUAttributionLedger.Failure.unregisteredBinding) {
            try ledger.withObservation(for: binding) { $0 }
        }
        #expect(source.bindings == [binding, binding])
    }

    @Test func allDomainAccountsPreflightBeforeLedgerRegistrationOrNativeRead() async throws {
        let owners = try identities("a", "b")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let source = LedgerReadSource([:])
        let coordinator = ProcessMetricsCoordinator(
            accountCapacity  : 1,
            attributionLedger: ledger,
            read             : source.read
        )
        await #expect(throws: ProcessMetricsCoordinator.Failure.accountCapacityReached) {
            try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[0])
        }
        #expect(await coordinator.registeredCount == 0)
        #expect(await coordinator.nextDeadline == nil)
        #expect(source.bindings.isEmpty)
        #expect(throws: ServiceCPUAttributionLedger.Failure.unregisteredBinding) {
            try ledger.withObservation(for: binding) { $0 }
        }
    }

    @Test func invalidPhysicalOwnerAndMixedAttributionRejectAtomically() async throws {
        let owners = try identities("a", "b", "outsider")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: Array(owners.prefix(2)))
        let binding = metricBinding(1)
        let source = LedgerReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1))
        ]])
        let coordinator = ProcessMetricsCoordinator(attributionLedger: ledger, read: source.read)
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidEventDrivenOwner) {
            try await coordinator.register(binding, at: .zero)
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidEventDrivenOwner) {
            try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[2])
        }
        #expect(await coordinator.registeredCount == 0)
        _ = try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[0])
        let forged = [ProcessMetricDelegatedAttribution(binding: binding, consumers: [owners[1]])]
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidAttribution) {
            try await coordinator.sampleIfDue(at: .milliseconds(500), attribution: forged)
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidAttribution) {
            try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: forged)
        }
        #expect(source.bindings.isEmpty)
        #expect(await coordinator.nextDeadline == .seconds(1))
        let batch = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero)
        #expect(batch.samples[0].chargedOwners == [owners[0]])
    }

    @Test func duplicateRegistrationPreservesPendingAndWakeDropsOldHistory() async throws {
        let owners = try identities("a", "b")
        let ledger = try ServiceCPUAttributionLedger(authorizedOwners: owners)
        let binding = metricBinding(1)
        let source = LedgerReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1)),
            .sample(observation(binding, cpu: 0, window: 2))
        ]])
        let coordinator = ProcessMetricsCoordinator(attributionLedger: ledger, read: source.read)
        #expect(try await coordinator.register(binding, at: .zero, eventDrivenOwner: owners[0]) == .registered)
        let ended = UUID()
        _ = try ledger.addInterest(ended, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(ended))
        #expect(try await coordinator.register(
            binding,
            at              : .zero,
            eventDrivenOwner: owners[0]
        ) == .duplicate)
        #expect(await coordinator.nextDeadline == .seconds(1))
        let preserved = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero)
        #expect(preserved.samples[0].chargedOwners == owners)
        _ = try ledger.addInterest(ended, consumer: owners[1], provider: owners[0])
        #expect(ledger.removeInterest(ended))
        try await coordinator.resetAfterWake(at: .seconds(1))
        let reset = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1))
        #expect(reset.samples[0].chargedOwners == [owners[0]])
        #expect(reset.samples[0].reduction.status == .baseline)
        #expect(await coordinator.unregister(binding))
        #expect(!ledger.unregister(binding))
    }

    private func identities(_ names: String...) throws -> [VerifiedAddonIdentity] {
        try names.map { name in
            VerifiedAddonIdentity(
                publisher: "verified.publisher",
                addonID  : try #require(AddonID(rawValue: "com.example.\(name)"))
            )
        }
    }

    private func metricBinding(_ index: UInt8) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid               : Int32(40 + index),
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)),
            token             : UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, index)),
            clockDomain       : UUID(uuid: (3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3))
        )
    }

    private func observation(
        _ binding: ProcessMetricBinding,
        cpu      : UInt64,
        window   : UInt64
    ) -> ProcessMetricObservation {
        ProcessMetricObservation(
            binding       : binding,
            userTicks     : cpu,
            systemTicks   : 0,
            footprintBytes: 4_096,
            window        : ProcessMetricWindow(
                startTicks: 100 * window + 100,
                endTicks  : 100 * window + 101
            ),
            timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
        )
    }
}
