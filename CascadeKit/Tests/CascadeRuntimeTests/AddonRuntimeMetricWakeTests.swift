//
//  AddonRuntimeMetricWakeTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonRuntimeMetricWakeTests {

    @Test
    func wakeDuringPositiveReadDefersResetAndKeepsCPUAdmissionPaused() async throws {
        let fixture = try await WakeFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        let overspend = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(overspend)?.classification == .moderate)
        try await expectNewActionDenied(fixture)

        fixture.clock.set(fixture.instant(12))
        fixture.reader.pauseThirdRead()
        let sampling = Task { try await fixture.runtime.sampleResources(reason: .jobBoundary) }
        defer {
            sampling.cancel()
            fixture.reader.release()
        }

        #expect(fixture.reader.waitForArrival(), "The native-read checkpoint must arrive within five seconds.")
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .deferred)
        #expect(try await fixture.runtime.sampleResources(reason: .jobBoundary) == .busy)
        fixture.reader.release()
        let stale = try await sampling.value
        #expect(firstObservation(stale)?.classification == .noNewViolation)
        #expect(firstObservation(stale)?.status == .stale)
        #expect(firstObservation(stale)?.decision == nil)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: fixture.version)?.moderateIncidentCount == 1)
        #expect(try await fixture.runtime.nextDelay(at: fixture.instant(12)) == .seconds(1))
        try await expectNewActionDenied(fixture)

        let readsBeforeReset = fixture.reader.readCount
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .completed)
        #expect(fixture.reader.readCount == readsBeforeReset)
        #expect(try await fixture.runtime.nextDelay(at: fixture.instant(12)) == .seconds(1))
        let baseline = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(baseline)?.classification == .unavailable)
        #expect(firstObservation(baseline)?.decision == nil)
        try await expectNewActionDenied(fixture)
    }

    @Test
    func wakeBaselinePreservesNegativeDebtUntilMeasuredRecovery() async throws {
        let fixture = try await WakeFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        #expect(
            firstObservation(
                try await fixture.runtime.sampleResources(reason: .jobBoundary)
            )?.classification == .moderate
        )
        try await expectNewActionDenied(fixture)
        fixture.clock.set(fixture.instant(2))
        let readsBeforeWake = fixture.reader.readCount
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .completed)
        #expect(fixture.reader.readCount == readsBeforeWake)
        let baseline = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(baseline)?.classification == .unavailable)
        try await expectNewActionDenied(fixture)
        fixture.clock.set(fixture.instant(3))
        let stillInDebt = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(stillInDebt)?.classification == .noNewViolation)
        try await expectNewActionDenied(fixture)
    }

    @Test
    func newerWakeDuringResetStaysPendingUntilNextDeadlinePass() async throws {
        let fixture = try await WakeFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        let checkpoint = WakeResetGate()
        let resetting  = Task {
            try await AddonRuntime.$cpuWakeResetCheckpoint.withValue({ checkpoint.pause() }) {
                try await fixture.runtime.resetProcessMetricsAfterWake()
            }
        }

        defer {
            resetting.cancel()
            checkpoint.release()
        }

        #expect(checkpoint.waitForArrival(), "The reset checkpoint must arrive within five seconds.")
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .deferred)
        #expect(try await fixture.runtime.sampleResources(reason: .jobBoundary) == .busy)
        checkpoint.release()
        #expect(try await resetting.value == .deferred)
        #expect(try await fixture.runtime.nextDelay(at: fixture.instant(1)) == .seconds(1))
        let readsBeforePass = fixture.reader.readCount
        fixture.clock.set(fixture.instant(2))
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.reader.readCount == readsBeforePass)
        #expect(try await fixture.runtime.nextDelay(at: fixture.instant(2)) == .seconds(1))
        let baseline = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(baseline)?.classification == .unavailable)
    }

    @Test
    func stoppedRuntimeIgnoresLateWakeWithoutReading() async throws {
        let fixture         = try await WakeFixture()
        let readsBeforeStop = fixture.reader.readCount
        await fixture.runtime.stop()
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .completed)
        #expect(fixture.reader.readCount == readsBeforeStop)
        #expect(try await fixture.runtime.nextDelay(at: fixture.instant(0)) == nil)
    }

    private func firstObservation(
        _ result: AddonRuntime.ResourceSampleResult
    ) -> AddonRuntime.ResourceOwnerObservation? {
        guard case .sampled(let observations) = result else { return nil }

        return observations.first
    }

    private func expectNewActionDenied(_ fixture: WakeFixture) async throws {
        let request = try fixture.request()
        do {
            _ = try await fixture.runtime.submitAction(request)
            Issue.record("A wake or an unmeasured baseline reopened CPU admission.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }

        #expect(await fixture.runtime.actionState(request.requestID, owner: fixture.action.owner) == nil)
    }

    private struct WakeFixture {

        let action       : ActionFixture
        let runtime      : AddonRuntime
        let clock        : MutableRuntimeClock
        let reader       : WakeReadSource
        let publicationID: PublicationID
        let version      : AddonVersionIdentity

        init() async throws {
            action = try ActionFixture()
            let installed = try action.context().installed
            let adapter   = RecordingRuntimeAdapter()
            clock = MutableRuntimeClock(instant: RuntimeInstant(wall: action.wall, monotonic: .zero))
            let binding = ProcessMetricBinding(
                pid               : 71,
                birthAbsoluteTicks: 100,
                executableUUID    : UUID(),
                token             : UUID(),
                clockDomain       : UUID()
            )
            reader  = WakeReadSource(binding: binding)
            runtime = try await AddonRuntime.make(
                catalog    : [installed],
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [action.owner: []],
                    explicitBindings: []
                ),
                governor  : ResourceGovernor(),
                adapter   : adapter,
                clock     : clock,
                metricRead: reader.read
            )
            publicationID = try await runtime.assignPublication(
                owner     : action.owner,
                featureID : "controls",
                instanceID: UUID()
            )
            let launch     = try await runtime.requestLaunch(owner: action.owner)
            let connection = try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : 0,
                    contentSchemas: [1]
                )
            )
            _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : ProviderOutput(
                    schemaVersion: 1,
                    publications : [try Publication(
                        id         : publicationID,
                        revision   : 1,
                        kind       : .widget,
                        content    : action.presentation(),
                        timeline   : nil,
                        expiresAt  : action.wall.addingTimeInterval(100),
                        stalePolicy: .remove
                    )],
                    operations: [],
                    completion: nil,
                    checkpoint: nil
                ),
                connection: connection,
                sequence  : 1
            )
            version = try AddonVersionIdentity(
                verifiedIdentity: installed.verifiedIdentity,
                version         : try #require(SemanticVersion(installed.manifest.version))
            )
            _ = try await runtime.registerProcessMetrics(
                incarnation: connection.incarnation,
                binding    : binding
            )
        }

        func instant(_ second: Int) -> RuntimeInstant {
            RuntimeInstant(wall: action.wall.addingTimeInterval(Double(second)), monotonic: .seconds(second))
        }

        func request() throws -> ActionRequest {
            try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : publicationID,
                actionID        : "pause",
                input           : Data([7]),
                deadline        : action.wall.addingTimeInterval(20),
                observedRevision: 1
            )
        }
    }
}
