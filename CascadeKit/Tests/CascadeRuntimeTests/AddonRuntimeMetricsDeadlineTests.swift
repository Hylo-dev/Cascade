//
//  AddonRuntimeMetricsDeadlineTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonRuntimeMetricsDeadlineTests {
    @Test func periodicDeadlineSamplesOnceAndExplicitBoundaryKeepsCadence() async throws {
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

    @Test func wakeResetsBaselineWithoutReadingAndRearmsPeriodicDeadline() async throws {
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

    @Test func aggregateDeadlineKeysMigrateWhenTheirFirstOwnerIsDisabled() async throws {
        let first = try ActionFixture(ownerName: "com.example.aggregatefirst")
        let second = try ActionFixture(ownerName: "com.example.aggregatesecond")
        let firstInstalled = try first.context().installed
        let secondInstalled = try second.context().installed
        let clock = MutableRuntimeClock(instant: RuntimeInstant(
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
            governor  : ResourceGovernor(),
            adapter   : RecordingRuntimeAdapter(),
            clock     : clock,
            metricRead: { _ in .unavailable(.readFailed(5)) }
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

    @Test func lastMetricExitDisarmsTheCommonMetricsDeadline() async throws {
        let fixture = try await MetricsDeadlineFixture.make(reads: [0])

        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(1))
        await fixture.runtime.observeExit(fixture.incarnation)
        #expect(try await fixture.runtime.nextDelay(at: fixture.clock.now()) == .seconds(100))
    }

    @Test func coldStartExpiryDrainsMetricsBeforeThePeriodicPass() async throws {
        let fixture = try await MetricsDeadlineFixture.make(
            reads    : [0],
            connected: false
        )

        fixture.clock.advance(2)
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(fixture.source.readCount == 0)
        await fixture.runtime.observeExit(fixture.incarnation)
    }

    @Test func nearerActionDeadlineWinsOverTheMetricsDeadline() async throws {
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

private final class MetricsDeadlineReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [UInt64]
    private var count = 0
    private var windowIndex: UInt64 = 0

    var readCount: Int {
        lock.withLock { count }
    }

    init(ticks: [UInt64]) {
        self.ticks = ticks
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            count += 1
            windowIndex += 1
            let tick = ticks.isEmpty ? 0 : ticks.removeFirst()
            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : tick,
                systemTicks   : 0,
                footprintBytes: 4_096,
                window        : ProcessMetricWindow(
                    startTicks: 200 + windowIndex,
                    endTicks  : 201 + windowIndex
                ),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}

private struct MetricsDeadlineFixture {
    let runtime     : AddonRuntime
    let action      : ActionFixture
    let installed   : InstalledAddon
    let clock       : MutableRuntimeClock
    let source      : MetricsDeadlineReadSource
    let incarnation : RuntimeIncarnation
    let publicationID: PublicationID

    static func make(
        reads    : [UInt64],
        connected: Bool = true
    ) async throws -> MetricsDeadlineFixture {
        let action = try ActionFixture(ownerName: "com.example.metricsdeadline")
        let installed = try action.context().installed
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : action.wall,
            monotonic: .zero
        ))
        let source = MetricsDeadlineReadSource(ticks: reads)
        let runtime = try await AddonRuntime.make(
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
            metricRead: source.read
        )
        let publicationID = try await runtime.assignPublication(
            owner     : action.owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: action.owner)
        let incarnation: RuntimeIncarnation
        if connected {
            let connection = try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : 0,
                    contentSchemas: [1]
                )
            )
            incarnation = connection.incarnation
            _ = try await receivePublicationOutput(
                runtime   : runtime,
                adapter   : adapter,
                output    : ProviderOutput(
                    schemaVersion: 1,
                    publications: [try Publication(
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
        } else {
            incarnation = try #require(adapter.lastStart(owner: action.owner)?.incarnation)
        }
        let binding = ProcessMetricBinding(
            pid               : 54,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
        #expect(try await runtime.registerProcessMetrics(
            incarnation: incarnation,
            binding    : binding
        ) == .registered)
        return MetricsDeadlineFixture(
            runtime     : runtime,
            action      : action,
            installed   : installed,
            clock       : clock,
            source      : source,
            incarnation : incarnation,
            publicationID: publicationID
        )
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
