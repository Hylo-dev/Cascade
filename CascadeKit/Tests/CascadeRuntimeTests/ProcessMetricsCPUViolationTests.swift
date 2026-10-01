//
//  ProcessMetricsCPUViolationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ProcessMetricsCPUViolationTests {
    @Test func burstIsModerateOnceThenIdleDebtIsNotANewViolation() async throws {
        let binding = metricBinding()
        let owner = try metricOwner()
        let source = ViolationReadSource([
            binding.token: [
                .sample(observation(for: binding, user: 0, start: 200, end: 201)),
                .sample(observation(for: binding, user: 150_000_000, start: 300, end: 301)),
                .sample(observation(for: binding, user: 150_000_000, start: 400, end: 401)),
                .sample(observation(for: binding, user: 160_000_000, start: 500, end: 501))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(binding, at: .zero, eventDrivenOwner: owner)

        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        let burst = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        let idle = try #require(try await coordinator.sampleIfDue(at: .seconds(3)))
        let renewed = try #require(try await coordinator.sampleIfDue(at: .seconds(4)))
        #expect(violation(in: burst, owner: owner) == .moderate)
        #expect(violation(in: idle, owner: owner) == .noNewViolation)
        #expect(violation(in: renewed, owner: owner) == .moderate)
    }

    @Test func repaidWithinCreditAndExactZeroIntervalsHaveNoNewViolation() async throws {
        let binding = metricBinding()
        let owner = try metricOwner()
        let source = ViolationReadSource([
            binding.token: [
                .sample(observation(for: binding, user: 0, start: 200, end: 201)),
                .sample(observation(for: binding, user: 150_000_000, start: 300, end: 301)),
                .sample(observation(for: binding, user: 160_000_000, start: 400, end: 401)),
                .sample(observation(for: binding, user: 250_000_000, start: 500, end: 501)),
                .sample(observation(for: binding, user: 260_000_000, start: 600, end: 601))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(binding, at: .zero, eventDrivenOwner: owner)

        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        _ = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        let withinCredit = try #require(try await coordinator.sampleIfDue(at: .seconds(31)))
        let exactZero = try #require(try await coordinator.sampleIfDue(at: .seconds(32)))
        let renewed = try #require(try await coordinator.sampleIfDue(at: .seconds(33)))
        #expect(violation(in: withinCredit, owner: owner) == .noNewViolation)
        #expect(violation(in: exactZero, owner: owner) == .noNewViolation)
        #expect(try completeSnapshot(in: exactZero, owner: owner).balance == .zero)
        #expect(violation(in: renewed, owner: owner) == .moderate)
    }

    @Test func ownerGetsOneAssessmentAcrossMultipleProcessesAndOwnersStayIsolated() async throws {
        let first = metricBinding(token: metricToken(1))
        let second = metricBinding(pid: 43, token: metricToken(2))
        let third = metricBinding(pid: 44, token: metricToken(3))
        let firstOwner = try metricOwner(addonID: "com.example.first")
        let secondOwner = try metricOwner(addonID: "com.example.second")
        let source = ViolationReadSource([
            first.token: [
                .sample(observation(for: first, user: 0, start: 200, end: 201)),
                .sample(observation(for: first, user: 60_000_000, start: 300, end: 301))
            ],
            second.token: [
                .sample(observation(for: second, user: 0, start: 200, end: 201)),
                .sample(observation(for: second, user: 50_000_000, start: 300, end: 301))
            ],
            third.token: [
                .sample(observation(for: third, user: 0, start: 200, end: 201)),
                .sample(observation(for: third, user: 20_000_000, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(first, at: .zero, eventDrivenOwner: firstOwner)
        try await coordinator.register(second, at: .zero, eventDrivenOwner: firstOwner)
        try await coordinator.register(third, at: .zero, eventDrivenOwner: secondOwner)

        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        #expect(batch.cpuAccounting.map(\.classification) == [
            .moderate,
            .noNewViolation
        ])
    }

    @Test func incompleteBatchKeepsKnownOverspendButNeverInventsHealthyResult() async throws {
        let overspent = metricBinding(token: metricToken(1))
        let missing = metricBinding(pid: 43, token: metricToken(2))
        let quiet = metricBinding(pid: 44, token: metricToken(3))
        let failed = metricBinding(pid: 45, token: metricToken(4))
        let overspentOwner = try metricOwner(addonID: "com.example.overspent")
        let quietOwner = try metricOwner(addonID: "com.example.quiet")
        let failedOwner = try metricOwner(addonID: "com.example.failed")
        let source = ViolationReadSource([
            overspent.token: [
                .sample(observation(for: overspent, user: 0, start: 200, end: 201)),
                .sample(observation(for: overspent, user: 150_000_000, start: 300, end: 301))
            ],
            missing.token: [
                .sample(observation(for: missing, user: 0, start: 200, end: 201)),
                .unavailable(.readFailed(5))
            ],
            quiet.token: [
                .sample(observation(for: quiet, user: 0, start: 200, end: 201)),
                .unavailable(.readFailed(5))
            ],
            failed.token: [
                .sample(observation(for: failed, user: 0, start: 200, end: 201)),
                .sample(observation(for: failed, user: .max, start: 300, end: 301)),
                .sample(observation(for: failed, user: .max, system: 100_000_000, start: 400, end: 401)),
                .sample(observation(for: failed, user: .max, system: 110_000_001, start: 500, end: 501))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(overspent, at: .zero, eventDrivenOwner: overspentOwner)
        try await coordinator.register(missing, at: .zero, eventDrivenOwner: overspentOwner)
        try await coordinator.register(quiet, at: .zero, eventDrivenOwner: quietOwner)
        try await coordinator.register(failed, at: .zero, eventDrivenOwner: failedOwner)

        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        let incomplete = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        _ = try await coordinator.sampleIfDue(at: .seconds(3))
        let failedBatch = try #require(try await coordinator.sampleIfDue(at: .seconds(4)))
        #expect(violation(in: incomplete, owner: overspentOwner) == .moderate)
        #expect(violation(in: incomplete, owner: quietOwner) == .unavailable)
        #expect(violation(in: failedBatch, owner: failedOwner) == .unavailable)
    }

    @Test func explicitAndPeriodicBatchesClassifyFreshIntervalsAndIgnoreDuplicates() async throws {
        let binding = metricBinding()
        let owner = try metricOwner()
        let source = ViolationReadSource([
            binding.token: [
                .sample(observation(for: binding, user: 0, start: 200, end: 201)),
                .sample(observation(for: binding, user: 150_000_000, start: 300, end: 301)),
                .sample(observation(for: binding, user: 160_000_000, start: 400, end: 401)),
                .sample(observation(for: binding, user: 160_000_000, start: 400, end: 401))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(binding, at: .zero, eventDrivenOwner: owner)

        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(500))
        let explicit = try await coordinator.sampleAll(reason: .memoryPressure, at: .seconds(1))
        let periodic = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        let repeated = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(1))
        #expect(violation(in: explicit, owner: owner) == .moderate)
        #expect(violation(in: periodic, owner: owner) == .moderate)
        #expect(violation(in: repeated, owner: owner) == .unavailable)
    }

    private func metricOwner(
        addonID: String = "com.example.cpu"
    ) throws -> VerifiedAddonIdentity {
        VerifiedAddonIdentity(
            publisher: "TEST-ONLY.publisher",
            addonID  : try #require(AddonID(rawValue: addonID))
        )
    }

    private func metricBinding(
        pid  : Int32 = 42,
        token: UUID? = nil
    ) -> ProcessMetricBinding {
        let resolvedToken = token ?? metricToken(0)
        return ProcessMetricBinding(
            pid                : pid,
            birthAbsoluteTicks : 100,
            executableUUID     : UUID(uuid: (0x11, 0x11, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33, 0x44, 0x44, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55)),
            token              : resolvedToken,
            clockDomain        : UUID(uuid: (0x12, 0x34, 0x56, 0x78, 0x12, 0x34, 0x12, 0x34, 0x12, 0x34, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC))
        )
    }

    private func metricToken(_ value: UInt8) -> UUID {
        UUID(uuid: (0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xCC, 0xCC, 0xDD, 0xDD, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, value))
    }

    private func observation(
        for binding: ProcessMetricBinding,
        user       : UInt64,
        system     : UInt64 = 0,
        start      : UInt64,
        end        : UInt64
    ) -> ProcessMetricObservation {
        ProcessMetricObservation(
            binding       : binding,
            userTicks     : user,
            systemTicks   : system,
            footprintBytes: 4_096,
            window        : ProcessMetricWindow(startTicks: start, endTicks: end),
            timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
        )
    }

    private func violation(
        in batch: ProcessMetricBatch,
        owner   : VerifiedAddonIdentity
    ) -> ProcessMetricCPUViolationResult? {
        batch.cpuAccounting.first(where: { $0.owner == owner })?.classification
    }

    private func completeSnapshot(
        in batch: ProcessMetricBatch,
        owner   : VerifiedAddonIdentity
    ) throws -> AddonCPUBudget.Snapshot {
        guard case .complete(let snapshot) = batch.cpuAccounting.first(where: { $0.owner == owner })?.result else {
            Issue.record("The test requires complete CPU accounting.")
            throw ProcessMetricsCPUViolationTestFailure.expectedCompleteAccounting
        }
        return snapshot
    }
}
