//
//  MetricsDeadlineFixture.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct MetricsDeadlineFixture {
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
