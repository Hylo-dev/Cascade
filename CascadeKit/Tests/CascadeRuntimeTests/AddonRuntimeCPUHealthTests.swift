//
//  AddonRuntimeCPUHealthTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonRuntimeCPUHealthTests {
    @Test func threeFreshOverCreditBatchesQuarantineTheCanonicalVersion() async throws {
        let fixture = try ActionFixture()
        let installed = try fixture.context().installed
        let binding = metricBinding()
        let source = CPUHealthReadSource([binding.token: [
            .sample(observation(binding, user: 0, start: 200, end: 201)),
            .sample(observation(binding, user: 150_000_000, start: 300, end: 301)),
            .sample(observation(binding, user: 160_000_000, start: 400, end: 401)),
            .sample(observation(binding, user: 170_000_000, start: 500, end: 501))
        ]])
        let clock = MutableRuntimeClock(instant: instant(0))
        let adapter = RecordingRuntimeAdapter()
        let runtime = try await AddonRuntime.make(
            catalog    : [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor   : ResourceGovernor(),
            adapter    : adapter,
            clock      : clock,
            metricRead : source.read
        )
        _ = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        _ = try await runtime.requestLaunch(owner: installed.manifest.id)
        let incarnation = try #require(adapter.lastStart(owner: installed.manifest.id)?.incarnation)
        #expect(try await runtime.registerProcessMetrics(
            incarnation: incarnation,
            binding    : binding
        ) == .registered)

        #expect(try await runtime.sampleResources(reason: .periodic) == .notDue)

        _ = try await runtime.sampleResources(reason: .jobBoundary)
        let version = try AddonVersionIdentity(
            verifiedIdentity: installed.verifiedIdentity,
            version         : try #require(SemanticVersion(installed.manifest.version))
        )
        for second in 1...3 {
            clock.set(instant(second))
            let result = try await runtime.sampleResources(reason: .jobBoundary)
            guard case .sampled(let observations) = result else {
                Issue.record("Expected a sampled CPU batch.")
                return
            }
            #expect(observations.count == 1)
            #expect(observations.first?.classification == .moderate)
            #expect(observations.first?.decision == (second == 3 ? .quarantine : .keep))
            #expect(observations.first?.status == .current)
            #expect(await runtime.resourceHealthSnapshot(for: version)?.moderateIncidentCount == (second == 3 ? 0 : second))
        }
        #expect(await runtime.resourceHealthSnapshot(for: version)?.isQuarantined == true)
        await runtime.observeExit(incarnation)
        let startsBefore = adapter.startCount(owner: installed.manifest.id)
        await #expect(throws: AddonFailure.self) {
            try await runtime.requestLaunch(owner: installed.manifest.id)
        }
        #expect(adapter.startCount(owner: installed.manifest.id) == startsBefore)
        #expect(try await runtime.sampleResources(reason: .jobBoundary) == .sampled([]))
    }

    @Test func residualDebtAndMissingMeasurementsDoNotCreateNewIncidents() async throws {
        let binding = metricBinding()
        let source = CPUHealthReadSource([binding.token: [
            .sample(observation(binding, user: 0, start: 200, end: 201)),
            .sample(observation(binding, user: 150_000_000, start: 300, end: 301)),
            .sample(observation(binding, user: 150_000_000, start: 400, end: 401)),
            .unavailable(.readFailed(5))
        ]])
        let harness = try await makeHarness(source: source)
        _ = try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : binding
        )
        _ = try await harness.runtime.sampleResources(reason: .jobBoundary)

        harness.clock.set(instant(1))
        let overCredit = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(overCredit)?.classification == .moderate)
        #expect(firstObservation(overCredit)?.decision == .keep)
        harness.clock.set(instant(2))
        let zero = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(zero)?.classification == .noNewViolation)
        #expect(firstObservation(zero)?.decision == nil)
        harness.clock.set(instant(3))
        let unavailable = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(unavailable)?.classification == .unavailable)
        #expect(firstObservation(unavailable)?.decision == nil)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 1)
        #expect(await harness.governor.usage(.providers, owner: harness.installed.manifest.id) == 1)
        #expect(harness.adapter.stopCount(incarnation: harness.incarnation) == 0)
    }

    @Test func foreignAndConflictingBindingsAreRejectedWhileDuplicateKeepsReducerProgress() async throws {
        let binding = metricBinding()
        let conflict = metricBinding(pid: 43, token: 4)
        let source = CPUHealthReadSource([binding.token: [
            .sample(observation(binding, user: 0, start: 200, end: 201)),
            .sample(observation(binding, user: 150_000_000, start: 300, end: 301))
        ]])
        let harness = try await makeHarness(source: source)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.registerProcessMetrics(
                incarnation: RuntimeIncarnation(),
                binding    : binding
            )
        }
        #expect(try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : binding
        ) == .registered)
        _ = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : binding
        ) == .duplicate)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.registerProcessMetrics(
                incarnation: harness.incarnation,
                binding    : conflict
            )
        }
        harness.clock.set(instant(1))
        let batch = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(batch)?.decision == .keep)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 1)
    }

    @Test func providerExitAndRestartKeepBothHealthHistoryAndSharedCPUDebt() async throws {
        let first = metricBinding()
        let next = metricBinding(pid: 43, token: 4)
        let source = CPUHealthReadSource([
            first.token: [
                .sample(observation(first, user: 0, start: 200, end: 201)),
                .sample(observation(first, user: 150_000_000, start: 300, end: 301))
            ],
            next.token: [
                .sample(observation(next, user: 0, start: 200, end: 201)),
                .sample(observation(next, user: 10_000_000, start: 300, end: 301))
            ]
        ])
        let harness = try await makeHarness(source: source)
        _ = try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : first
        )
        _ = try await harness.runtime.sampleResources(reason: .jobBoundary)
        harness.clock.set(instant(1))
        _ = try await harness.runtime.sampleResources(reason: .jobBoundary)
        await harness.runtime.observeExit(harness.incarnation)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 1)

        harness.clock.set(instant(2))
        _ = try await harness.runtime.requestLaunch(owner: harness.installed.manifest.id)
        let replacement = try #require(harness.adapter.lastStart(owner: harness.installed.manifest.id)?.incarnation)
        #expect(replacement != harness.incarnation)
        _ = try await harness.runtime.registerProcessMetrics(
            incarnation: replacement,
            binding    : next
        )
        harness.clock.set(instant(3))
        let baseline = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(baseline)?.classification == .unavailable)
        harness.clock.set(instant(4))
        let overspend = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(overspend)?.classification == .moderate)
        #expect(firstObservation(overspend)?.decision == .keep)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 2)
        #expect(await harness.governor.usage(.providers, owner: harness.installed.manifest.id) == 1)
        #expect(harness.adapter.stopCount(incarnation: replacement) == 0)
        await harness.runtime.observeExit(harness.incarnation)
        #expect(await harness.runtime.diagnostics(owner: harness.installed.manifest.id)?.hasProcess == true)
    }

    @Test func stopDuringNativeReadInvalidatesHealthAndRejectsOverlappingSamples() async throws {
        let binding = metricBinding()
        let gate = CPUHealthReadGate()
        let source = CPUHealthReadSource(
            [binding.token: [
                .sample(observation(binding, user: 0, start: 200, end: 201)),
                .sample(observation(binding, user: 150_000_000, start: 300, end: 301))
            ]],
            gate: gate
        )
        let harness = try await makeHarness(source: source)
        _ = try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : binding
        )
        _ = try await harness.runtime.sampleResources(reason: .jobBoundary)
        harness.clock.set(instant(1))

        let sampling = Task {
            try await harness.runtime.sampleResources(reason: .jobBoundary)
        }
        defer { gate.release() }
        #expect(gate.waitForArrival())
        #expect(try await harness.runtime.sampleResources(reason: .jobBoundary) == .busy)
        _ = await harness.runtime.requestStop()
        gate.release()
        let result = try await sampling.value
        #expect(firstObservation(result)?.classification == .moderate)
        #expect(firstObservation(result)?.status == .stale)
        #expect(firstObservation(result)?.decision == nil)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 0)
        #expect(await harness.governor.usage(.providers, owner: harness.installed.manifest.id) == 1)
        #expect(harness.adapter.stopCount(incarnation: harness.incarnation) == 1)
        await harness.runtime.stop()
    }

    @Test func exitDuringRegistrationRollsBackRowBeforeSameBindingReplacement() async throws {
        let binding = metricBinding()
        let source = CPUHealthReadSource([binding.token: [
            .sample(observation(binding, user: 0, start: 200, end: 201)),
            .sample(observation(binding, user: 150_000_000, start: 300, end: 301))
        ]])
        let harness = try await makeHarness(source: source)
        let checkpoint = CPURegistrationCheckpoint()
        let registration = Task {
            try await AddonRuntime.$cpuRegistrationCheckpoint.withValue({
                checkpoint.pause()
            }) {
                try await harness.runtime.registerProcessMetrics(
                    incarnation: harness.incarnation,
                    binding    : binding
                )
            }
        }
        defer { checkpoint.release() }
        #expect(checkpoint.waitForArrival())
        await harness.runtime.observeExit(harness.incarnation)
        harness.clock.set(instant(1))
        _ = try await harness.runtime.requestLaunch(owner: harness.installed.manifest.id)
        let replacement = try #require(harness.adapter.lastStart(owner: harness.installed.manifest.id)?.incarnation)
        #expect(replacement != harness.incarnation)
        checkpoint.release()
        await #expect(throws: AddonFailure.self) {
            try await registration.value
        }
        #expect(try await harness.runtime.registerProcessMetrics(
            incarnation: replacement,
            binding    : binding
        ) == .registered)
        let baseline = try await harness.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(baseline)?.classification == .unavailable)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 0)
    }

    @Test func ownerQuarantineDoesNotChangeAnotherOwnersHealthOrPhysicalReservation() async throws {
        let fixture = try ActionFixture()
        let first = try fixture.context().installed
        let second = try replacing(first, id: "com.example.second-cpu-owner")
        let firstBinding = metricBinding()
        let secondBinding = metricBinding(pid: 43, token: 4)
        let source = CPUHealthReadSource([
            firstBinding.token: [
                .sample(observation(firstBinding, user: 0, start: 200, end: 201)),
                .sample(observation(firstBinding, user: 150_000_000, start: 300, end: 301)),
                .sample(observation(firstBinding, user: 160_000_000, start: 400, end: 401)),
                .sample(observation(firstBinding, user: 170_000_000, start: 500, end: 501))
            ],
            secondBinding.token: [
                .sample(observation(secondBinding, user: 0, start: 200, end: 201)),
                .sample(observation(secondBinding, user: 150_000_000, start: 300, end: 301)),
                .sample(observation(secondBinding, user: 150_000_000, start: 400, end: 401)),
                .sample(observation(secondBinding, user: 150_000_000, start: 500, end: 501))
            ]
        ])
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(instant: instant(0))
        let governor = ResourceGovernor()
        let runtime = try await AddonRuntime.make(
            catalog    : [first, second],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [first.manifest.id: [], second.manifest.id: []],
                explicitBindings: []
            ),
            governor  : governor,
            adapter   : adapter,
            clock     : clock,
            metricRead: source.read
        )
        for installed in [first, second] {
            _ = try await runtime.assignPublication(
                owner     : installed.manifest.id,
                featureID : "controls",
                instanceID: UUID()
            )
            _ = try await runtime.requestLaunch(owner: installed.manifest.id)
        }
        let firstIncarnation = try #require(adapter.lastStart(owner: first.manifest.id)?.incarnation)
        let secondIncarnation = try #require(adapter.lastStart(owner: second.manifest.id)?.incarnation)
        _ = try await runtime.registerProcessMetrics(
            incarnation: firstIncarnation,
            binding: firstBinding
        )
        _ = try await runtime.registerProcessMetrics(
            incarnation: secondIncarnation,
            binding: secondBinding
        )
        _ = try await runtime.sampleResources(reason: .jobBoundary)
        for secondMark in 1...3 {
            clock.set(instant(secondMark))
            _ = try await runtime.sampleResources(reason: .jobBoundary)
        }
        let firstVersion = try AddonVersionIdentity(
            verifiedIdentity: first.verifiedIdentity,
            version         : try #require(SemanticVersion(first.manifest.version))
        )
        let secondVersion = try AddonVersionIdentity(
            verifiedIdentity: second.verifiedIdentity,
            version         : try #require(SemanticVersion(second.manifest.version))
        )
        #expect(await runtime.resourceHealthSnapshot(for: firstVersion)?.isQuarantined == true)
        #expect(await runtime.resourceHealthSnapshot(for: secondVersion)?.moderateIncidentCount == 1)
        #expect(await runtime.resourceHealthSnapshot(for: secondVersion)?.isQuarantined == false)
        #expect(await governor.usage(.providers, owner: first.manifest.id) == 1)
        #expect(await governor.usage(.providers, owner: second.manifest.id) == 1)
        #expect(adapter.stopCount(incarnation: firstIncarnation) == 0)
        #expect(adapter.stopCount(incarnation: secondIncarnation) == 0)
    }

    @Test func coldStartDeadlineDetachesMetricsWithoutReleasingPhysicalProvider() async throws {
        let binding = metricBinding()
        let source = CPUHealthReadSource([binding.token: [
            .sample(observation(binding, user: 0, start: 200, end: 201))
        ]])
        let harness = try await makeHarness(source: source)
        _ = try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : binding
        )
        _ = try await harness.runtime.sampleResources(reason: .jobBoundary)
        harness.clock.set(instant(2))
        _ = try await harness.runtime.serviceDeadlines()
        #expect(harness.adapter.stopCount(incarnation: harness.incarnation) == 1)
        #expect(try await harness.runtime.sampleResources(reason: .jobBoundary) == .sampled([]))
        #expect(await harness.governor.usage(.providers, owner: harness.installed.manifest.id) == 1)
        #expect(await harness.runtime.resourceHealthSnapshot(for: harness.version)?.moderateIncidentCount == 0)
    }

    private func makeHarness(source: CPUHealthReadSource) async throws -> (
        runtime: AddonRuntime,
        installed: InstalledAddon,
        adapter: RecordingRuntimeAdapter,
        clock: MutableRuntimeClock,
        governor: ResourceGovernor,
        incarnation: RuntimeIncarnation,
        version: AddonVersionIdentity
    ) {
        let fixture = try ActionFixture()
        let installed = try fixture.context().installed
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(instant: instant(0))
        let governor = ResourceGovernor()
        let runtime = try await AddonRuntime.make(
            catalog    : [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [fixture.owner: []],
                explicitBindings: []
            ),
            governor  : governor,
            adapter   : adapter,
            clock     : clock,
            metricRead: source.read
        )
        _ = try await runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        _ = try await runtime.requestLaunch(owner: fixture.owner)
        let incarnation = try #require(adapter.lastStart(owner: fixture.owner)?.incarnation)
        let version = try AddonVersionIdentity(
            verifiedIdentity: installed.verifiedIdentity,
            version         : try #require(SemanticVersion(installed.manifest.version))
        )
        return (runtime, installed, adapter, clock, governor, incarnation, version)
    }

    private func firstObservation(
        _ result: AddonRuntime.ResourceSampleResult
    ) -> AddonRuntime.ResourceOwnerObservation? {
        guard case .sampled(let observations) = result else { return nil }
        return observations.first
    }

    private func instant(_ second: Int) -> RuntimeInstant {
        RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000 + Double(second)),
            monotonic: .seconds(second)
        )
    }

    private func metricBinding(
        pid  : Int32 = 42,
        token: UInt8 = 2
    ) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid                : pid,
            birthAbsoluteTicks : 100,
            executableUUID     : UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)),
            token              : UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, token)),
            clockDomain        : UUID(uuid: (3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3))
        )
    }

    private func observation(
        _ binding: ProcessMetricBinding,
        user     : UInt64,
        start    : UInt64,
        end      : UInt64
    ) -> ProcessMetricObservation {
        ProcessMetricObservation(
            binding       : binding,
            userTicks     : user,
            systemTicks   : 0,
            footprintBytes: 4_096,
            window        : ProcessMetricWindow(startTicks: start, endTicks: end),
            timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
        )
    }
}
