//
//  ProcessMetricsDelegatedCPUAccountingTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ProcessMetricsDelegatedCPUAccountingTests {
    @Test func onePhysicalIntervalChargesProviderAndEachVerifiedConsumer() async throws {
        let provider = try identity("provider")
        let first = try identity("first")
        let second = try identity("second")
        let binding = metricBinding(1)
        let source = DelegatedReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1)),
            .sample(observation(binding, cpu: 40_000_000, window: 2))
        ]])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(binding, at: .zero, eventDrivenOwner: provider)
        let attribution = [ProcessMetricDelegatedAttribution(
            binding  : binding,
            consumers: [first, second]
        )]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: attribution)
        let batch = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(1),
            attribution: attribution
        )
        #expect(batch.samples.count == 1)
        #expect(source.bindings == [binding, binding])
        #expect(batch.cpuAccounting.count == 3)
        for owner in [provider, first, second] {
            let result = try #require(batch.cpuAccounting.first(where: { $0.owner == owner }))
            guard case .complete(let snapshot) = result.result else {
                Issue.record("Each verified owner needs one complete accounting result.")
                return
            }
            #expect(snapshot.balance == .milliseconds(60))
            #expect(result.classification == .noNewViolation)
        }
    }

    @Test func directAndDelegatedRowsSumOncePerOwnerAcrossPhysicalProviders() async throws {
        let consumer = try identity("consumer")
        let provider = try identity("provider")
        let ownBinding = metricBinding(1)
        let providerBinding = metricBinding(2)
        let source = DelegatedReadSource([
            ownBinding.token: [
                .sample(observation(ownBinding, cpu: 0, window: 1)),
                .sample(observation(ownBinding, cpu: 40_000_000, window: 2))
            ],
            providerBinding.token: [
                .sample(observation(providerBinding, cpu: 0, window: 1)),
                .sample(observation(providerBinding, cpu: 70_000_000, window: 2))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(ownBinding, at: .zero, eventDrivenOwner: consumer)
        _ = try await coordinator.register(providerBinding, at: .zero, eventDrivenOwner: provider)
        let attribution = [
            ProcessMetricDelegatedAttribution(
                binding  : ownBinding,
                consumers: [consumer, consumer]
            ),
            ProcessMetricDelegatedAttribution(
                binding  : providerBinding,
                consumers: [consumer, consumer]
            )
        ]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: attribution)
        let batch = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(1),
            attribution: attribution
        )
        #expect(batch.samples.count == 2)
        #expect(batch.cpuAccounting.count == 2)
        let account = try #require(batch.cpuAccounting.first(where: { $0.owner == consumer }))
        guard case .complete(let snapshot) = account.result else {
            Issue.record("The direct and delegated CPU charges should consolidate.")
            return
        }
        #expect(snapshot.balance == .milliseconds(-10))
        #expect(account.classification == .moderate)
        let providerAccount = try #require(batch.cpuAccounting.first(where: { $0.owner == provider }))
        guard case .complete(let providerSnapshot) = providerAccount.result else {
            Issue.record("Provider accounting should remain independent.")
            return
        }
        #expect(providerSnapshot.balance == .milliseconds(30))
    }

    @Test func missingContributorKeepsConsumerIncompleteButFreshOverspendIsModerate() async throws {
        let consumer = try identity("consumer")
        let valid = metricBinding(1)
        let missing = metricBinding(2)
        let source = DelegatedReadSource([
            valid.token: [
                .sample(observation(valid, cpu: 0, window: 1)),
                .sample(observation(valid, cpu: 150_000_000, window: 2))
            ],
            missing.token: [
                .sample(observation(missing, cpu: 0, window: 1)),
                .unavailable(.readFailed(5))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(valid, at: .zero)
        _ = try await coordinator.register(missing, at: .zero)
        let attribution = [
            ProcessMetricDelegatedAttribution(binding: valid, consumers: [consumer]),
            ProcessMetricDelegatedAttribution(binding: missing, consumers: [consumer])
        ]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: attribution)
        let batch = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(1),
            attribution: attribution
        )
        #expect(batch.samples.count == 2)
        #expect(batch.cpuAccounting == [ProcessMetricCPUAccounting(
            owner         : consumer,
            result        : .incomplete,
            classification: .moderate
        )])
    }

    @Test func anUnownedPhysicalRowCanChargeItsVerifiedConsumer() async throws {
        let consumer = try identity("consumer")
        let binding = metricBinding(1)
        let source = DelegatedReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1)),
            .sample(observation(binding, cpu: 40_000_000, window: 2))
        ]])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(binding, at: .zero)
        let attribution = [ProcessMetricDelegatedAttribution(binding: binding, consumers: [consumer])]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: attribution)
        let batch = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(1),
            attribution: attribution
        )
        #expect(batch.samples.count == 1)
        #expect(batch.cpuAccounting.count == 1)
        guard case .complete(let snapshot) = batch.cpuAccounting.first?.result else {
            Issue.record("A verified consumer of an unowned row must be accounted.")
            return
        }
        #expect(snapshot.balance == .milliseconds(60))
    }

    @Test func invalidAttributionIsAtomicAndNotDueDoesNotAdmitAccounts() async throws {
        let provider = try identity("provider")
        let consumer = try identity("consumer")
        let extra = try identity("extra")
        let binding = metricBinding(1)
        let forged = metricBinding(2)
        let source = DelegatedReadSource([binding.token: [
            .sample(observation(binding, cpu: 0, window: 1)),
            .sample(observation(binding, cpu: 40_000_000, window: 2))
        ]])
        let coordinator = ProcessMetricsCoordinator(
            accountCapacity: 2,
            read           : source.read
        )
        _ = try await coordinator.register(binding, at: .zero, eventDrivenOwner: provider)
        let valid = [ProcessMetricDelegatedAttribution(binding: binding, consumers: [extra])]
        let tooMany = [ProcessMetricDelegatedAttribution(binding: binding, consumers: [consumer, extra])]
        #expect(try await coordinator.sampleIfDue(at: .milliseconds(500), attribution: tooMany) == nil)
        #expect(source.bindings.isEmpty)
        await #expect(throws: ProcessMetricsCoordinator.Failure.accountCapacityReached) {
            try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(500), attribution: tooMany)
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidAttribution) {
            try await coordinator.sampleAll(
                reason     : .jobBoundary,
                at         : .milliseconds(500),
                attribution: [ProcessMetricDelegatedAttribution(binding: forged, consumers: [consumer])]
            )
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.duplicateAttribution) {
            try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(500), attribution: valid + valid)
        }
        let invalid = VerifiedAddonIdentity(
            publisher: "   ",
            addonID  : consumer.addonID
        )
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidEventDrivenOwner) {
            try await coordinator.sampleAll(
                reason     : .jobBoundary,
                at         : .milliseconds(500),
                attribution: [ProcessMetricDelegatedAttribution(binding: binding, consumers: [invalid])]
            )
        }
        #expect(source.bindings.isEmpty)
        #expect(await coordinator.nextDeadline == .seconds(1))
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(500), attribution: valid)
        let batch = try await coordinator.sampleIfDue(at: .seconds(1), attribution: valid)
        #expect(batch?.samples.count == 1)
        #expect(batch?.cpuAccounting.first(where: { $0.owner == extra })?.classification == .noNewViolation)
    }

    @Test func delegatedDebtSurvivesProviderRestartAndWakeBaseline() async throws {
        let consumer = try identity("consumer")
        let old = metricBinding(1)
        let replacement = metricBinding(2)
        let source = DelegatedReadSource([
            old.token: [
                .sample(observation(old, cpu: 0, window: 1)),
                .sample(observation(old, cpu: 150_000_000, window: 2))
            ],
            replacement.token: [
                .sample(observation(replacement, cpu: 0, window: 1)),
                .sample(observation(replacement, cpu: 0, window: 2))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(old, at: .zero)
        let oldAttribution = [ProcessMetricDelegatedAttribution(binding: old, consumers: [consumer])]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: oldAttribution)
        let overspend = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(1),
            attribution: oldAttribution
        )
        #expect(overspend.cpuAccounting.first?.classification == .moderate)
        #expect(await coordinator.unregister(old))
        _ = try await coordinator.register(replacement, at: .seconds(1))
        try await coordinator.resetAfterWake(at: .seconds(2))
        let freshAttribution = [ProcessMetricDelegatedAttribution(binding: replacement, consumers: [consumer])]
        let baseline = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(2),
            attribution: freshAttribution
        )
        #expect(baseline.cpuAccounting.first?.result == .incomplete)
        let after = try await coordinator.sampleAll(
            reason     : .jobBoundary,
            at         : .seconds(3),
            attribution: freshAttribution
        )
        guard case .complete(let snapshot) = after.cpuAccounting.first?.result else {
            Issue.record("The consumer account should survive source replacement.")
            return
        }
        #expect(snapshot.balance == .milliseconds(-40))
        #expect(after.cpuAccounting.first?.classification == .noNewViolation)
    }

    @Test func combinedDebitAboveUInt64MaxCanRemainWithinDebtBound() async throws {
        let consumer = try identity("consumer")
        let first = metricBinding(1)
        let second = metricBinding(2)
        let source = DelegatedReadSource([
            first.token: [
                .sample(observation(first, cpu: 0, window: 1)),
                .sample(observation(first, cpu: .max, window: 2))
            ],
            second.token: [
                .sample(observation(second, cpu: 0, window: 1)),
                .sample(observation(second, cpu: 1, window: 2))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(first, at: .zero)
        _ = try await coordinator.register(second, at: .zero)
        let attribution = [
            ProcessMetricDelegatedAttribution(binding: first, consumers: [consumer]),
            ProcessMetricDelegatedAttribution(binding: second, consumers: [consumer])
        ]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: attribution)
        let batch = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1), attribution: attribution)
        #expect(batch.samples.count == 2)
        #expect(source.bindings.count == 4)
        #expect(batch.cpuAccounting.count == 1)
        guard case .complete(let snapshot) = batch.cpuAccounting.first?.result else {
            Issue.record("Charges totaling UInt64.max + 1 should fit within the retained debt bound.")
            return
        }
        #expect(snapshot.balance == .milliseconds(100) - AddonCPUBudget.maximumDebt - .nanoseconds(1))
        #expect(batch.cpuAccounting.first?.classification == .moderate)
    }

    @Test func chargesBeyondDebtBoundFailAccountWithoutResettingIt() async throws {
        let consumer = try identity("consumer")
        let first = metricBinding(1)
        let second = metricBinding(2)
        let source = DelegatedReadSource([
            first.token: [
                .sample(observation(first, cpu: 0, window: 1)),
                .sample(observation(first, cpu: .max, window: 2)),
                .sample(observation(first, cpu: .max, window: 3))
            ],
            second.token: [
                .sample(observation(second, cpu: 0, window: 1)),
                .sample(observation(second, cpu: .max, window: 2)),
                .sample(observation(second, cpu: .max, window: 3))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        _ = try await coordinator.register(first, at: .zero)
        _ = try await coordinator.register(second, at: .zero)
        let attribution = [
            ProcessMetricDelegatedAttribution(binding: first, consumers: [consumer]),
            ProcessMetricDelegatedAttribution(binding: second, consumers: [consumer])
        ]
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .zero, attribution: attribution)
        let failed = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1), attribution: attribution)
        #expect(failed.cpuAccounting.first?.result == .accountingFailed)
        #expect(failed.cpuAccounting.first?.classification == .unavailable)
        let stillFailed = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(2), attribution: attribution)
        #expect(stillFailed.cpuAccounting.first?.result == .accountingFailed)
        #expect(stillFailed.cpuAccounting.first?.classification == .unavailable)
        #expect(stillFailed.samples.count == 2)
    }

    private func identity(_ name: String) throws -> VerifiedAddonIdentity {
        VerifiedAddonIdentity(
            publisher: "verified.publisher",
            addonID  : try #require(AddonID(rawValue: "com.example.\(name)"))
        )
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
