//
//  ProcessMetricsCoordinatorTests.swift
//  CascadeKit
//

import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ProcessMetricsCoordinatorTests {
    private let executableUUID = UUID(uuid: (
        0x11, 0x11, 0x11, 0x11, 0x22, 0x22, 0x33, 0x33,
        0x44, 0x44, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55
    ))
    private let clockDomain = UUID(uuid: (
        0x12, 0x34, 0x56, 0x78, 0x12, 0x34, 0x12, 0x34,
        0x12, 0x34, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC
    ))

    private func binding(
        pid   : Int32 = 42,
        birth : UInt64 = 100,
        token : UUID = UUID(uuid: (
            0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xBB, 0xCC, 0xCC,
            0xDD, 0xDD, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE
        ))
    ) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid                : pid,
            birthAbsoluteTicks : birth,
            executableUUID     : executableUUID,
            token              : token,
            clockDomain        : clockDomain
        )
    }

    private func observation(
        for binding : ProcessMetricBinding,
        user        : UInt64,
        system      : UInt64 = 0,
        footprint   : UInt64 = 4_096,
        start       : UInt64,
        end         : UInt64
    ) -> ProcessMetricObservation {
        ProcessMetricObservation(
            binding       : binding,
            userTicks     : user,
            systemTicks   : system,
            footprintBytes: footprint,
            window        : ProcessMetricWindow(startTicks: start, endTicks: end),
            timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
        )
    }

    @Test func periodicSamplingGatesReadsAndAdvancesFromNowWithoutCatchUp() async throws {
        let first  = binding()
        let second = binding(
            pid   : 43,
            token : alternateToken
        )
        let source = MetricReadSource([
            first.token : [.sample(observation(for: first, user: 10, start: 200, end: 201))],
            second.token: [.sample(observation(for: second, user: 20, start: 200, end: 201))]
        ])
        let coordinator = ProcessMetricsCoordinator(cadence: .milliseconds(100), read: source.read)

        try await coordinator.register(first, at: .zero)
        try await coordinator.register(second, at: .milliseconds(100))
        #expect(await coordinator.nextDeadline == .seconds(1))
        #expect(try await coordinator.sampleIfDue(at: .milliseconds(999)) == nil)
        #expect(source.bindings.isEmpty)

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(3)))
        #expect(batch.samples.count == 2)
        #expect(batch.samples.contains { $0.binding == first })
        #expect(batch.samples.contains { $0.binding == second })
        #expect(batch.samples.allSatisfy { $0.reduction.status == .baseline })
        #expect(source.bindings == [first, second])
        #expect(await coordinator.nextDeadline == .seconds(4))
    }

    @Test func reducersProduceBaselineThenInterval() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 10, start: 200, end: 201)),
                .sample(observation(for: expected, user: 16, system: 4, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(expected, at: .zero)

        let baseline = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(baseline.samples.first?.reduction.status == .baseline)
        let interval = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        #expect(interval.samples.first?.reduction.status == .interval)
        #expect(interval.samples.first?.reduction.interval?.cpuNanoseconds == 10)
        #expect(interval.samples.first?.reduction.interval?.elapsedNanoseconds == 100)
    }

    @Test func unavailableBindingDoesNotBlockAnotherReduction() async throws {
        let failed = binding()
        let valid  = binding(
            pid   : 43,
            token : alternateToken
        )
        let source = MetricReadSource([
            failed.token: [.unavailable(.readFailed(5))],
            valid.token : [.sample(observation(for: valid, user: 10, start: 200, end: 201))]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(failed, at: .zero)
        try await coordinator.register(valid, at: .zero)

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(batch.samples.first(where: { $0.binding == failed })?.reduction.status == .unavailable(.readFailed(5)))
        #expect(batch.samples.first(where: { $0.binding == valid })?.reduction.status == .baseline)
    }

    @Test(arguments: [ProcessMetricFailure.identityMismatch, .exited])
    func identityTerminalReadReportsUnavailableThenRetiresOnlyThatBinding(
        failure: ProcessMetricFailure
    ) async throws {
        let retired = binding()
        let active  = binding(
            pid   : 43,
            token : alternateToken
        )
        let source = MetricReadSource([
            retired.token: [.unavailable(failure)],
            active.token : [
                .sample(observation(for: active, user: 10, start: 200, end: 201)),
                .sample(observation(for: active, user: 20, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(retired, at: .zero)
        try await coordinator.register(active, at: .zero)

        let first = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(first.samples.first(where: { $0.binding == retired })?.reduction.status == .unavailable(failure))
        _ = try await coordinator.sampleIfDue(at: .seconds(2))
        #expect(source.bindings.filter { $0 == retired }.count == 1)
        #expect(source.bindings.filter { $0 == active }.count == 2)
        #expect(await coordinator.registeredCount == 1)

        let replacement = binding(pid: retired.pid, birth: 101, token: retired.token)
        try await coordinator.register(replacement, at: .milliseconds(2_500))
        #expect(await coordinator.unregister(retired) == false)
        #expect(await coordinator.registeredCount == 2)
    }

    @Test func exactOwnershipRejectsConflictsAndStaleUnregister() async throws {
        let original = binding()
        let tokenConflict = binding(pid: 43, birth: 101, token: original.token)
        let pidConflict = binding(
            pid   : original.pid,
            birth : 101,
            token : alternateToken
        )
        let coordinator = ProcessMetricsCoordinator(read: { _ in .unavailable(.readFailed(5)) })
        try await coordinator.register(original, at: .zero)

        await #expect(throws: ProcessMetricsCoordinator.Failure.tokenConflict) {
            try await coordinator.register(tokenConflict, at: .zero)
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.pidConflict) {
            try await coordinator.register(pidConflict, at: .zero)
        }
        #expect(await coordinator.unregister(tokenConflict) == false)
        #expect(await coordinator.unregister(original))
        #expect(await coordinator.registeredCount == 0)
    }

    @Test func duplicateRegistrationPreservesReducerBaseline() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 10, start: 200, end: 201)),
                .sample(observation(for: expected, user: 20, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(expected, at: .zero)
        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        #expect(try await coordinator.register(expected, at: .milliseconds(1_500)) == .duplicate)

        let batch = try #require(try await coordinator.sampleIfDue(at: .seconds(2)))
        #expect(batch.samples.first?.reduction.status == .interval)
        #expect(source.bindings.count == 2)
    }

    @Test func duplicateRegistrationAdvancesAcceptedClockWithoutMovingDeadline() async throws {
        let expected = binding()
        let coordinator = ProcessMetricsCoordinator(read: { _ in .unavailable(.readFailed(5)) })
        try await coordinator.register(expected, at: .zero)
        #expect(try await coordinator.register(expected, at: .milliseconds(500)) == .duplicate)
        #expect(await coordinator.nextDeadline == .seconds(1))
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidMonotonicTime) {
            try await coordinator.sampleIfDue(at: .milliseconds(499))
        }
        #expect(await coordinator.nextDeadline == .seconds(1))
    }

    @Test func zeroAndFullCapacityRejectWithoutEviction() async throws {
        let expected = binding()
        let zero = ProcessMetricsCoordinator(capacity: 0, read: { _ in .unavailable(.readFailed(5)) })
        await #expect(throws: ProcessMetricsCoordinator.Failure.capacityReached) {
            try await zero.register(expected, at: .zero)
        }
        #expect(await zero.registeredCount == 0)

        let one = ProcessMetricsCoordinator(capacity: 1, read: { _ in .unavailable(.readFailed(5)) })
        try await one.register(expected, at: .zero)
        let excess = binding(
            pid   : 43,
            token : alternateToken
        )
        await #expect(throws: ProcessMetricsCoordinator.Failure.capacityReached) {
            try await one.register(excess, at: .zero)
        }
        #expect(await one.registeredCount == 1)
        #expect(await one.unregister(expected))
    }

    @Test func capacityIsClampedAndMalformedBindingsAreNeverRetained() async throws {
        let coordinator = ProcessMetricsCoordinator(capacity: Int.max, read: { _ in
            .unavailable(.readFailed(5))
        })
        for index in 0..<1_024 {
            let current = binding(pid: Int32(index + 1), token: uniqueToken(index))
            try await coordinator.register(current, at: .zero)
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.capacityReached) {
            try await coordinator.register(
                binding(pid: 1_025, token: uniqueToken(1_024)),
                at: .zero
            )
        }
        #expect(await coordinator.registeredCount == 1_024)

        let malformed = ProcessMetricsCoordinator(read: { _ in .unavailable(.readFailed(5)) })
        let zero = ProcessMetricBinding.zeroUUID
        let invalid = [
            binding(pid: 0),
            binding(token: zero),
            ProcessMetricBinding(
                pid                : 42,
                birthAbsoluteTicks : 100,
                executableUUID     : executableUUID,
                token              : uniqueToken(2_000),
                clockDomain        : zero
            )
        ]
        for candidate in invalid {
            await #expect(throws: ProcessMetricsCoordinator.Failure.invalidBinding) {
                try await malformed.register(candidate, at: .zero)
            }
        }
        #expect(await malformed.registeredCount == 0)
        #expect(await malformed.nextDeadline == nil)
    }

    @Test func explicitReregistrationStartsANewBaseline() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 10, start: 200, end: 201)),
                .sample(observation(for: expected, user: 20, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(expected, at: .zero)
        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        #expect(await coordinator.unregister(expected))
        try await coordinator.register(expected, at: .milliseconds(1_500))

        let batch = try #require(try await coordinator.sampleIfDue(at: .milliseconds(2_500)))
        #expect(batch.samples.first?.reduction.status == .baseline)
    }

    @Test func boundarySamplesDoNotPostponePeriodicDeadline() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 10, start: 200, end: 201)),
                .sample(observation(for: expected, user: 20, start: 300, end: 301)),
                .sample(observation(for: expected, user: 30, start: 400, end: 401))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(expected, at: .zero)

        let job = try await coordinator.sampleAll(reason: .jobBoundary, at: .milliseconds(500))
        #expect(job.samples.first?.reduction.status == .baseline)
        let pressure = try await coordinator.sampleAll(reason: .memoryPressure, at: .milliseconds(750))
        #expect(pressure.samples.first?.reduction.status == .interval)
        #expect(await coordinator.nextDeadline == .seconds(1))
        let periodic = try #require(try await coordinator.sampleIfDue(at: .seconds(1)))
        #expect(periodic.samples.first?.reduction.status == .interval)
        #expect(await coordinator.nextDeadline == .seconds(2))
    }

    @Test func wakeResetClearsContinuityWithoutReadingAndIdleDisarms() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [
                .sample(observation(for: expected, user: 10, start: 200, end: 201)),
                .sample(observation(for: expected, user: 20, start: 300, end: 301))
            ]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(expected, at: .zero)
        _ = try await coordinator.sampleIfDue(at: .seconds(1))
        try await coordinator.resetAfterWake(at: .milliseconds(1_500))
        #expect(source.bindings.count == 1)
        #expect(await coordinator.nextDeadline == .milliseconds(2_500))

        let restarted = try #require(try await coordinator.sampleIfDue(at: .milliseconds(2_500)))
        #expect(restarted.samples.first?.reduction.status == .baseline)
        #expect(await coordinator.unregister(expected))
        #expect(await coordinator.nextDeadline == nil)
        #expect(try await coordinator.sampleIfDue(at: .seconds(3)) == nil)
    }

    @Test func invalidOrBackwardTimeDoesNotReadOrAdvanceDeadline() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [.sample(observation(for: expected, user: 10, start: 200, end: 201))]
        ])
        let coordinator = ProcessMetricsCoordinator(read: source.read)
        try await coordinator.register(expected, at: .seconds(10))
        #expect(try await coordinator.sampleIfDue(at: .milliseconds(10_500)) == nil)

        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidMonotonicTime) {
            try await coordinator.sampleIfDue(at: .seconds(9))
        }
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidMonotonicTime) {
            try await coordinator.sampleIfDue(at: .seconds(Int64.max))
        }
        let huge = Duration.seconds(Int64.max) + .seconds(1)
        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidMonotonicTime) {
            try await coordinator.sampleIfDue(at: huge)
        }
        #expect(source.bindings.isEmpty)
        #expect(await coordinator.nextDeadline == .seconds(11))
    }

    @Test func fractionalDurationRejectsBackwardTimeAndNeverFiresEarly() async throws {
        let expected = binding()
        let source = MetricReadSource([
            expected.token: [.sample(observation(for: expected, user: 10, start: 200, end: 201))]
        ])
        let cadence = Duration(secondsComponent: 1, attosecondsComponent: 800_000_000)
        let start   = Duration(secondsComponent: 0, attosecondsComponent: 1_900_000_000)
        let deadline = start + cadence
        let coordinator = ProcessMetricsCoordinator(cadence: cadence, read: source.read)
        try await coordinator.register(expected, at: start)

        await #expect(throws: ProcessMetricsCoordinator.Failure.invalidMonotonicTime) {
            try await coordinator.sampleIfDue(
                at: Duration(secondsComponent: 0, attosecondsComponent: 1_100_000_000)
            )
        }
        let early = deadline - Duration(secondsComponent: 0, attosecondsComponent: 100_000_000)
        #expect(try await coordinator.sampleIfDue(at: early) == nil)
        #expect(source.bindings.isEmpty)
        #expect(await coordinator.nextDeadline == deadline)
        #expect(try await coordinator.sampleIfDue(at: deadline) != nil)
        #expect(source.bindings == [expected])
    }

    private var alternateToken: UUID {
        UUID(uuid: (
            0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xBB, 0xCC, 0xCC,
            0xDD, 0xDD, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE, 0xEE
        ))
    }

    private func uniqueToken(_ value: Int) -> UUID {
        UUID(uuid: (
            0xCC, 0xCC, 0xCC, 0xCC, 0xDD, 0xDD, 0xEE, 0xEE,
            0xFF, 0xFF, 0xAA, 0xAA, 0xAA, 0xAA,
            UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)
        ))
    }
}
