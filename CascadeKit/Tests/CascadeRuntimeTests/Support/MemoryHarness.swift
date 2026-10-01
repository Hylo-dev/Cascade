//
//  MemoryHarness.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct MemoryHarness {

    let runtime      : AddonRuntime
    let governor     : ResourceGovernor
    let adapter      : RecordingRuntimeAdapter
    let clock        : MutableRuntimeClock
    let owner        : AddonID
    let publicationID: PublicationID
    let connection   : RuntimeConnection
    let incarnation  : RuntimeIncarnation
    let binding      : ProcessMetricBinding
    let version      : AddonVersionIdentity

    private let wall        : Date
    private let presentation: PresentationSet

    init(
        userTicks  : [UInt64?]? = nil,
        systemTicks: [UInt64?]? = nil,
        footprints : [UInt64?]
    ) async throws {
        let fixture   = try ActionFixture()
        let installed = try fixture.context().installed
        owner        = fixture.owner
        wall         = fixture.wall
        presentation = try fixture.presentation()
        governor     = ResourceGovernor()
        adapter      = RecordingRuntimeAdapter()
        clock        = MutableRuntimeClock(instant: Self.instant(fixture.wall, 0))
        binding      = ProcessMetricBinding(
            pid               : 42,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
        let source = MemoryReadSource(
            binding    : binding,
            userTicks  : userTicks ?? Array(repeating: 0, count: footprints.count),
            systemTicks: systemTicks ?? Array(repeating: 0, count: footprints.count),
            footprints : footprints
        )
        runtime = try await AddonRuntime.make(
            catalog    : [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [owner: []],
                explicitBindings: []
            ),
            governor  : governor,
            adapter   : adapter,
            clock     : clock,
            metricRead: source.read
        )
        publicationID = try await runtime.assignPublication(
            owner     : owner,
            featureID : "controls",
            instanceID: UUID()
        )
        let launch = try await runtime.requestLaunch(owner: owner)
        connection = try await runtime.attach(
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
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : [try Publication(
                    id         : publicationID,
                    revision   : 1,
                    kind       : .widget,
                    content    : presentation,
                    timeline   : nil,
                    expiresAt  : fixture.wall.addingTimeInterval(100),
                    stalePolicy: .remove
                )],
                operations: [],
                completion: nil,
                checkpoint: nil
            ),
            connection: connection,
            sequence  : 1
        )
        _ = try await runtime.registerProcessMetrics(incarnation: incarnation, binding: binding)
        version = try AddonVersionIdentity(
            verifiedIdentity: installed.verifiedIdentity,
            version         : try #require(SemanticVersion(installed.manifest.version))
        )
    }

    var snapshot: AddonHealthSnapshot? {
        get async { await runtime.resourceHealthSnapshot(for: version) }
    }

    var incidentCount: Int {
        get async { await snapshot?.moderateIncidentCount ?? 0 }
    }

    func sample(at second: Int) async throws -> AddonRuntime.ResourceSampleResult {
        clock.set(Self.instant(wall, second))
        return try await runtime.sampleResources(reason: .jobBoundary)
    }

    func request(revision: UInt64 = 1) throws -> ActionRequest {
        try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : wall.addingTimeInterval(20),
            observedRevision: revision
        )
    }

    func completeLastAction() async throws {
        let delivery = try #require(adapter.lastAction)
        #expect(try await runtime.receiveActionCompletion(
            delivery,
            connection: connection,
            outcome   : .completed(payload: Data())
        ))
    }

    func restart() async throws -> RuntimeConnection {
        let launch = try await runtime.requestLaunch(owner: owner)
        return try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
    }

    func publish(
        on connection: RuntimeConnection,
        revision     : UInt64
    ) async throws {
        _ = try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : [try Publication(
                    id         : publicationID,
                    revision   : revision,
                    kind       : .widget,
                    content    : presentation,
                    timeline   : nil,
                    expiresAt  : wall.addingTimeInterval(100),
                    stalePolicy: .remove
                )],
                operations: [],
                completion: nil,
                checkpoint: nil
            ),
            connection: connection,
            sequence  : 1
        )
    }

    func firstObservation(_ result: AddonRuntime.ResourceSampleResult) -> AddonRuntime.ResourceOwnerObservation? {
        guard case .sampled(let observations) = result else { return nil }

        return observations.first
    }

    private static func instant(
        _ wall  : Date,
        _ second: Int
    ) -> RuntimeInstant {
        RuntimeInstant(wall: wall.addingTimeInterval(Double(second)), monotonic: .seconds(second))
    }
}
