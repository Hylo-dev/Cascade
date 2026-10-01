//
//  AddonRuntimeMetricsDeadlineTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonRuntimeMetricsDeadlineTests {

    @Test
    func periodicDeadlineSamplesOnceAndExplicitBoundaryKeepsCadence() async throws {
        let fixture = try await MetricsDeadlineFixture.make(reads: [0, 10_000_000, 20_000_000])

        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(1))

        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(1))

        fixture.clock.advance(1)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.source.readCount == 2)

        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.source.readCount == 2)

        await fixture.runtime.observeExit(fixture.incarnation)
    }

    @Test
    func wakeResetsBaselineWithoutReadingAndRearmsPeriodicDeadline() async throws {
        let fixture = try await MetricsDeadlineFixture.make(reads: [0, 150_000_000, 160_000_000])

        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.advance(1)
        #expect(try await fixture.runtime.resetProcessMetricsAfterWake() == .completed)
        #expect(fixture.source.readCount == 1)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(1))

        fixture.clock.advance(1)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.source.readCount == 2)
        #expect(try await fixture.runtime.sampleResources(reason: .jobBoundary) == .sampled([
            AddonRuntime.ResourceOwnerObservation(
                owner         : fixture.installed.verifiedIdentity,
                classification: .noNewViolation,
                decision      : nil,
                status        : .current
            )
        ]))

        await fixture.runtime.observeExit(fixture.incarnation)
    }

    @Test
    func aggregateDeadlineKeysMigrateWhenTheirFirstOwnerIsDisabled() async throws {
        let first           = try ActionFixture(ownerName: "com.example.aggregatefirst")
        let second          = try ActionFixture(ownerName: "com.example.aggregatesecond")
        let firstInstalled  = try first.context().installed
        let secondInstalled = try second.context().installed
        let clock           = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : first.wall,
            monotonic: .zero
        ))

        let runtime = try await AddonRuntime.make(
            catalog    : [firstInstalled, secondInstalled],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [first.owner: [], second.owner: []],
                explicitBindings: []
            ),
            governor   : ResourceGovernor(),
            adapter    : RecordingRuntimeAdapter(),
            clock      : clock,
            metricRead : { _ in .unavailable(.readFailed(5)) }
        )

        _ = try await runtime.assignPublication(
            owner     : first.owner,
            featureID : "controls",
            instanceID: UUID()
        )

        _ = try await runtime.requestLaunch(owner: first.owner)
        _ = try await runtime.nextDelay(at: clock.now())
        await runtime.disable(owner: first.owner)
        _ = try await runtime.nextDelay(at: clock.now())
    }

    @Test
    func lastMetricExitDisarmsTheCommonMetricsDeadline() async throws {
        let fixture = try await MetricsDeadlineFixture.make(reads: [0])

        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(1))

        await fixture.runtime.observeExit(fixture.incarnation)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(100))
    }

    @Test
    func coldStartExpiryDrainsMetricsBeforeThePeriodicPass() async throws {
        let fixture = try await MetricsDeadlineFixture.make(reads: [0], connected: false)

        fixture.clock.advance(2)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.source.readCount == 0)

        await fixture.runtime.observeExit(fixture.incarnation)
    }

    @Test
    func nearerActionDeadlineWinsOverTheMetricsDeadline() async throws {
        let fixture = try await MetricsDeadlineFixture.make(reads: [0])
        let request = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : fixture.publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.action.wall.addingTimeInterval(0.5),
            observedRevision: 1
        )

        #expect(try await fixture.runtime.submitAction(request) == .admitted)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .milliseconds(500))

        await fixture.runtime.observeExit(fixture.incarnation)
    }
}

private extension MutableRuntimeClock {

    func advance(_ seconds: Int) {
        let now = now()

        set(RuntimeInstant(
            wall     : now.wall.addingTimeInterval(Double(seconds)),
            monotonic: now.monotonic + .seconds(seconds)
        ))
    }
}
