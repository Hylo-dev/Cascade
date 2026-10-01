//
//  AssetRuntimeFixture.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

struct AssetRuntimeFixture: Sendable {

    let runtime   : AddonRuntime
    let governor  : ResourceGovernor
    let access    : GatedRuntimeResourceAccess
    let adapter   : RecordingRuntimeAdapter
    let clock     : MutableRuntimeClock
    let owner     : AddonID
    let ids       : [PublicationID]
    let connection: RuntimeConnection
    let wall      : Date

    var offer: ProtocolOffer {
        get throws {
            try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        }
    }

    static func make(count: Int = 1) async throws -> Self {
        let base     = try ActionFixture()
        let governor = ResourceGovernor()
        let access   = GatedRuntimeResourceAccess(target: governor)
        let adapter  = RecordingRuntimeAdapter()
        let clock    = MutableRuntimeClock(
            instant: RuntimeInstant(wall: base.wall, monotonic: .zero)
        )

        let runtime = try await AddonRuntime.make(
            catalog               : [base.context().installed],
            environment           : HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [base.owner: []],
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : access,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock
        )

        var ids: [PublicationID] = []
        for _ in 0..<count {
            ids.append(
                try await runtime.assignPublication(
                    owner     : base.owner,
                    featureID : "controls",
                    instanceID: UUID()
                )
            )
        }

        let launch     = try await runtime.requestLaunch(owner: base.owner)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )

        return Self(
            runtime   : runtime,
            governor  : governor,
            access    : access,
            adapter   : adapter,
            clock     : clock,
            owner     : base.owner,
            ids       : ids,
            connection: connection,
            wall      : base.wall
        )
    }

    func content(_ asset: String?) throws -> PresentationSet {
        try PresentationSet(
            widget         : ContentDocument(
                root              : .text("Image"),
                privacy           : .publicContent,
                accessibilityLabel: "Image",
                assetIDs          : asset.map { [$0] } ?? []
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    func publication(
        asset   : String?,
        index   : Int = 0,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : ids[index],
            revision   : revision,
            kind       : .widget,
            content    : content(asset),
            timeline   : nil,
            expiresAt  : wall.addingTimeInterval(60),
            stalePolicy: .remove
        )
    }

    func publish(
        _ publications: [Publication],
        sequence      : UInt64,
        connection    : RuntimeConnection? = nil,
        ends          : [PublicationID] = []
    ) async throws -> PublicationAdmission {
        try await receivePublicationOutput(
            runtime   : runtime,
            adapter   : adapter,
            output    : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection ?? self.connection,
            sequence  : sequence
        )
    }

    func image(
        _ asset : String,
        revision: UInt64 = 1
    ) async -> CGImage? {
        await runtime.assetImage(
            assetID            : asset,
            publicationID      : ids[0],
            publicationRevision: revision
        )
    }
}
