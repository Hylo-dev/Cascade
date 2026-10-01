//
//  ProcessMetricsCPUAccountingTests.swift
//  CascadeKit
//

import Foundation
import Testing
import CascadeContracts
@testable import CascadeRuntime

@Suite
struct ProcessMetricsCPUAccountingTests {

    @Test
    func baselineIsIncompleteAndNextIntervalDebitsTheOwner() async throws {
        let expected = binding()
        let source   = CPUAccountingReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 0, start: 200, end: 201)),
                .sample(observation(for: expected, user: 10_000_000, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        let owner       = try owner()
        try await coordinator.register(
            expected,
            at              : .zero,
            eventDrivenOwner: owner
        )

        let baseline = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(baseline.cpuAccounting == [
            ProcessMetricCPUAccounting(owner: owner, result: .incomplete)
        ])

        let interval = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        let result   = try #require(interval.cpuAccounting.first?.result)
        guard case .complete(let snapshot) = result else {
            Issue.record("A committed interval must expose the owner's final snapshot.")
            return
        }

        #expect(snapshot.balance == .milliseconds(90))
        #expect(snapshot.debt == .zero)
    }

    @Test
    func multipleBindingsShareOneOwnerBudgetAndOneRefill() async throws {
        let first  = binding(token: token(1))
        let second = binding(pid: 43, token: token(2))
        let source = CPUAccountingReadSource([
            first.token: [
                .sample(observation(for: first, user: 0, start: 200, end: 201)),
                .sample(observation(for: first, user: 60_000_000, start: 300, end: 301))
            ],
            second.token: [
                .sample(observation(for: second, user: 0, start: 200, end: 201)),
                .sample(observation(for: second, user: 50_000_000, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        let owner       = try owner()
        try await coordinator.register(
            first,
            at              : .zero,
            eventDrivenOwner: owner
        )
        try await coordinator.register(
            second,
            at              : .zero,
            eventDrivenOwner: owner
        )
        _ = try await coordinator.sampleIfDue(at: .seconds(1))

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        #expect(batch.cpuAccounting.count == 1)

        let snapshot = try completeSnapshot(in: batch, owner: owner)
        #expect(snapshot.balance == .milliseconds(-10))
        #expect(snapshot.debt == .milliseconds(10))
    }

    @Test
    func distinctOwnersHaveIsolatedAccounts() async throws {
        let first       = binding(token: token(1))
        let second      = binding(pid: 43, token: token(2))
        let firstOwner  = try owner(addonID: "com.example.first")
        let secondOwner = try owner(addonID: "com.example.second")
        let source      = CPUAccountingReadSource([
            first.token: [
                .sample(observation(for: first, user: 0, start: 200, end: 201)),
                .sample(observation(for: first, user: 60_000_000, start: 300, end: 301))
            ],
            second.token: [
                .sample(observation(for: second, user: 0, start: 200, end: 201)),
                .sample(observation(for: second, user: 20_000_000, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(
            first,
            at              : .zero,
            eventDrivenOwner: firstOwner
        )
        try await coordinator.register(
            second,
            at              : .zero,
            eventDrivenOwner: secondOwner
        )
        _ = try await coordinator.sampleIfDue(at: .seconds(1))

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        #expect(try completeSnapshot(in: batch, owner: firstOwner).balance == .milliseconds(40))
        #expect(try completeSnapshot(in: batch, owner: secondOwner).balance == .milliseconds(80))
    }

    @Test
    func repeatedBoundaryAndPeriodicSamplesChargeOnlyTheirFreshIntervals() async throws {
        let expected = binding()
        let source   = CPUAccountingReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 0, start: 200, end: 201)),
                .sample(observation(for: expected, user: 60_000_000, start: 300, end: 301)),
                .sample(observation(for: expected, user: 70_000_000, start: 400, end: 401))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        let owner       = try owner()
        try await coordinator.register(
            expected,
            at              : .zero,
            eventDrivenOwner: owner
        )

        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(500))
        let boundary = try await coordinator.sampleAll(reason: .memoryPressure, at: .seconds(1))
        #expect(try completeSnapshot(in: boundary, owner: owner).balance == .milliseconds(40))

        let periodic = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(try completeSnapshot(in: periodic, owner: owner).balance == .milliseconds(30))
    }

    @Test
    func exactDuplicatePreservesAccountAndOwnerReassignmentIsAtomic() async throws {
        let expected = binding()
        let original = try owner()
        let foreign  = try owner(addonID: "com.example.foreign")
        let source   = CPUAccountingReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 0, start: 200, end: 201)),
                .sample(observation(for: expected, user: 60_000_000, start: 300, end: 301)),
                .sample(observation(for: expected, user: 70_000_000, start: 400, end: 401))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(
            expected,
            at              : .zero,
            eventDrivenOwner: original
        )
        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        _ = try await coordinator.sampleIfDue(at: .seconds(2))

        #expect(try await coordinator.register(
            expected,
            at              : .milliseconds(2_500),
            eventDrivenOwner: original
        ) == .duplicate)

        await #expect(throws: ProcessMetricsCoordinator.Failure.ownershipConflict) {
            try await coordinator.register(
                expected,
                at              : .milliseconds(2_500),
                eventDrivenOwner: foreign
            )
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.ownershipConflict) {
            try await coordinator.register(expected, at: .milliseconds(2_500))
        }

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(3)))
        #expect(try completeSnapshot(in: batch, owner: original).balance == .milliseconds(35))
    }

    @Test
    func unownedBindingCannotBeUpgradedAndProducesNoAccountResult() async throws {
        let expected    = binding()
        let coordinator = ProcessMetricsCoordinator(read: { binding in
            .sample(self.observation(for: binding, user: 0, start: 200, end: 201))
        })
        try await coordinator.register(expected, at: .zero)
        await #expect(throws: ProcessMetricsCoordinator.Failure.ownershipConflict) {
            try await coordinator.register(
                expected,
                at              : .milliseconds(500),
                eventDrivenOwner: try self.owner()
            )
        }

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(batch.cpuAccounting.isEmpty)
        #expect(batch.samples.first?.reduction.status == .baseline)
    }

    @Test
    func unregisterAndTerminalRetirementPreserveDebtForReplacementBindings() async throws {
        let first       = binding(token: token(1))
        let replacement = binding(pid: 43, token: token(2))
        let terminal    = binding(pid: 44, token: token(3))
        let final       = binding(pid: 45, token: token(4))
        let source      = CPUAccountingReadSource([
            first.token: [
                .sample(observation(for: first, user: 0, start: 200, end: 201)),
                .sample(observation(for: first, user: 150_000_000, start: 300, end: 301))
            ],
            replacement.token: [
                .sample(observation(for: replacement, user: 0, start: 200, end: 201)),
                .sample(observation(for: replacement, user: 10_000_000, start: 300, end: 301)),
                .unavailable(.exited)
            ],
            terminal.token: [.unavailable(.identityMismatch)],
            final.token: [
                .sample(observation(for: final, user: 0, start: 200, end: 201)),
                .sample(observation(for: final, user: 10_000_000, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        let owner       = try owner()
        try await coordinator.register(
            first,
            at              : .zero,
            eventDrivenOwner: owner
        )
        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        _ = try await coordinator.sampleIfDue(at: .seconds(2))

        #expect(await coordinator.unregister(first))

        try await coordinator.register(
            replacement,
            at              : .milliseconds(2_500),
            eventDrivenOwner: owner
        )
        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(3))
        let resumed = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(4))
        #expect(try completeSnapshot(in: resumed, owner: owner).balance == .milliseconds(-50))

        let retired = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(5))
        #expect(accountingResult(in: retired, owner: owner) == .incomplete)

        try await coordinator.register(
            terminal,
            at              : .milliseconds(5_100),
            eventDrivenOwner: owner
        )
        let mismatch = try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(5_200))
        #expect(accountingResult(in: mismatch, owner: owner) == .incomplete)

        try await coordinator.register(
            final,
            at              : .milliseconds(5_300),
            eventDrivenOwner: owner
        )

        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(6))
        let finalBatch = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(7))
        #expect(try completeSnapshot(in: finalBatch, owner: owner).balance == .milliseconds(-45))
    }

    @Test
    func wakeResetBreaksBaselineWithoutResettingDebt() async throws {
        let expected = binding()
        let source   = CPUAccountingReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 0, start: 200, end: 201)),
                .sample(observation(for: expected, user: 150_000_000, start: 300, end: 301)),
                .sample(observation(for: expected, user: 160_000_000, start: 400, end: 401)),
                .sample(observation(for: expected, user: 170_000_000, start: 500, end: 501))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        let owner       = try owner()
        try await coordinator.register(
            expected,
            at              : .zero,
            eventDrivenOwner: owner
        )
        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        _ = try await coordinator.sampleIfDue(at: .seconds(2))
        try await coordinator.resetAfterWake(at: .milliseconds(2_500))

        let baseline = try #require(try await coordinator.sampleIfDue(at: .milliseconds(3_500)))
        #expect(accountingResult(in: baseline, owner: owner) == .incomplete)

        let interval = try #require(try await coordinator.sampleIfDue(at: .milliseconds(4_500)))
        #expect(try completeSnapshot(in: interval, owner: owner).balance == .nanoseconds(-47_500_000))
    }

    @Test
    func incompleteOwnerKeepsSiblingDebitAndDoesNotBlockAnotherOwner() async throws {
        let measured    = binding(token: token(1))
        let missing     = binding(pid: 43, token: token(2))
        let other       = binding(pid: 44, token: token(3))
        let firstOwner  = try owner(addonID: "com.example.first")
        let secondOwner = try owner(addonID: "com.example.second")
        let source      = CPUAccountingReadSource([
            measured.token: [
                .sample(observation(for: measured, user: 0, start: 200, end: 201)),
                .sample(observation(for: measured, user: 60_000_000, start: 300, end: 301))
            ],
            missing.token: [
                .sample(observation(for: missing, user: 0, start: 200, end: 201)),
                .unavailable(.readFailed(5))
            ],
            other.token: [
                .sample(observation(for: other, user: 0, start: 200, end: 201)),
                .sample(observation(for: other, user: 20_000_000, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(
            measured,
            at              : .zero,
            eventDrivenOwner: firstOwner
        )
        try await coordinator.register(
            missing,
            at              : .zero,
            eventDrivenOwner: firstOwner
        )
        try await coordinator.register(
            other,
            at              : .zero,
            eventDrivenOwner: secondOwner
        )
        _ = try await coordinator.sampleIfDue(at: .seconds(1))

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        #expect(accountingResult(in: batch, owner: firstOwner) == .incomplete)
        #expect(try completeSnapshot(in: batch, owner: secondOwner).balance == .milliseconds(80))

        #expect(await coordinator.unregister(measured))
        #expect(await coordinator.unregister(missing))

        let replacement = binding(pid: 45, token: token(4))
        source.enqueue([
            .sample(observation(for: replacement, user: 0, start: 200, end: 201)),
            .sample(observation(for: replacement, user: 10_000_000, start: 300, end: 301))
        ], for: replacement)
        try await coordinator.register(
            replacement,
            at              : .milliseconds(2_500),
            eventDrivenOwner: firstOwner
        )

        _ = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(3))
        let resumed = try await coordinator.sampleAll(reason: .jobBoundary, at: .seconds(4))
        #expect(try completeSnapshot(in: resumed, owner: firstOwner).balance == .milliseconds(40))
    }

    @Test
    func defaultRetainedAccountCapacityRejectsAfterDetachedOwnersWithoutMutation() async throws {
        let coordinator = ProcessMetricsCoordinator(
            capacity: 2,
            read    : { _ in .unavailable(.readFailed(5)) }
        )
        for index in 0..<32 {
            let current = binding(pid: Int32(index + 1), token: token(UInt8(index + 1)))
            try await coordinator.register(
                current,
                at              : .zero,
                eventDrivenOwner: try owner(addonID: "com.example.owner\(index)")
            )
            #expect(await coordinator.unregister(current))
        }

        let rejected = binding(pid: 40, token: token(40))

        await #expect(throws: ProcessMetricsCoordinator.Failure.accountCapacityReached) {
            try await coordinator.register(
                rejected,
                at              : .seconds(1),
                eventDrivenOwner: try self.owner(addonID: "com.example.excess")
            )
        }
        #expect(await coordinator.registeredCount == 0)
        #expect(await coordinator.nextDeadline == nil)

        let replacement = binding(pid: 41, token: token(41))
        try await coordinator.register(
            replacement,
            at              : .seconds(1),
            eventDrivenOwner: try owner(addonID: "com.example.owner0")
        )
        #expect(await coordinator.registeredCount == 1)
        #expect(await coordinator.nextDeadline == .seconds(2))
    }

    @Test
    func invalidOwnerAndClockDoNotAllocateAccounts() async throws {
        let expected    = binding(token: token(1))
        let valid       = binding(pid: 43, token: token(2))
        let coordinator = ProcessMetricsCoordinator(
            accountCapacity: 1,
            read           : { _ in .unavailable(.readFailed(5)) }
        )
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidEventDrivenOwner) {
            try await coordinator.register(
                expected,
                at              : .zero,
                eventDrivenOwner: try self.owner(publisher: " \n\t ")
            )
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidEventDrivenOwner) {
            try await coordinator.register(
                expected,
                at              : .zero,
                eventDrivenOwner: try self.owner(publisher: String(repeating: "é", count: 257))
            )
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidMonotonicTime) {
            try await coordinator.register(
                expected,
                at              : .seconds(-1),
                eventDrivenOwner: try self.owner(addonID: "com.example.rejected")
            )
        }

        try await coordinator.register(
            valid,
            at              : .zero,
            eventDrivenOwner: try owner(addonID: "com.example.valid")
        )
        #expect(await coordinator.registeredCount == 1)
    }

    @Test
    func accountingOverflowStaysFailedWithoutBlockingOtherOwner() async throws {
        let failed       = binding(token: token(1))
        let healthy      = binding(pid: 43, token: token(2))
        let failedOwner  = try owner(addonID: "com.example.failed")
        let healthyOwner = try owner(addonID: "com.example.healthy")
        let source       = CPUAccountingReadSource([
            failed.token: [
                .sample(observation(for: failed, user: 0, start: 200, end: 201)),
                .sample(observation(for: failed, user: .max, start: 300, end: 301)),
                .sample(observation(for: failed, user: .max, system: 100_000_000, start: 400, end: 401)),
                .sample(observation(for: failed, user: .max, system: 110_000_001, start: 500, end: 501)),
                .sample(observation(for: failed, user: .max, system: 110_000_001, start: 600, end: 601))
            ],
            healthy.token: [
                .sample(observation(for: healthy, user: 0, start: 200, end: 201)),
                .sample(observation(for: healthy, user: 10_000_000, start: 300, end: 301)),
                .sample(observation(for: healthy, user: 20_000_000, start: 400, end: 401)),
                .sample(observation(for: healthy, user: 30_000_000, start: 500, end: 501)),
                .sample(observation(for: healthy, user: 40_000_000, start: 600, end: 601))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(
            failed,
            at              : .zero,
            eventDrivenOwner: failedOwner
        )
        try await coordinator.register(
            healthy,
            at              : .zero,
            eventDrivenOwner: healthyOwner
        )
        for second in 1...3 {
            _ = try await coordinator.sampleIfDue(at: .seconds(second))
        }

        let overflow = try #require(try await coordinator.sampleIfDue(at: .seconds(4)))
        #expect(accountingResult(in: overflow, owner: failedOwner) == .accountingFailed)
        #expect(try completeSnapshot(in: overflow, owner: healthyOwner).balance == .milliseconds(80))

        let sticky = try #require(try await coordinator.sampleIfDue(at: .seconds(5)))
        #expect(accountingResult(in: sticky, owner: failedOwner) == .accountingFailed)
        #expect(try completeSnapshot(in: sticky, owner: healthyOwner).balance == .milliseconds(75))
    }

    private func owner(
        publisher: String = "TEST-ONLY.publisher",
        addonID  : String = "com.example.cpu"
    ) throws -> VerifiedAddonIdentity {
        VerifiedAddonIdentity(publisher: publisher, addonID: try #require(AddonID(rawValue: addonID)))
    }

    private func binding(
        pid  : Int32 = 42,
        token: UUID = UUID(uuid: (
            0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xCC, 0xCC,
            0xDD, 0xDD, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE
        ))
    ) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid               : pid,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(uuid: (
                0x11, 0x11, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33,
                0x44, 0x44, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55
            )),
            token             : token,
            clockDomain       : UUID(uuid: (
                0x12, 0x34, 0x56, 0x78, 0x12, 0x34, 0x12, 0x34,
                0x12, 0x34, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC
            ))
        )
    }

    private func token(_ value: UInt8) -> UUID {
        UUID(uuid: (
            0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xCC, 0xCC,
            0xDD, 0xDD, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, value
        ))
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

    private func accountingResult(
        in batch: ProcessMetricBatch,
        owner   : VerifiedAddonIdentity
    ) -> ProcessMetricCPUAccountingResult? {
        batch.cpuAccounting.first(where: { $0.owner == owner })?.result
    }

    private func completeSnapshot(
        in batch: ProcessMetricBatch,
        owner   : VerifiedAddonIdentity
    ) throws -> AddonCPUBudget.Snapshot {
        let result = try #require(accountingResult(in: batch, owner: owner))

        guard case .complete(let snapshot) = result else {
            Issue.record("Expected complete CPU accounting for \(owner.addonID.rawValue).")
            throw CPUAccountingTestFailure.expectedComplete
        }

        return snapshot
    }
}
