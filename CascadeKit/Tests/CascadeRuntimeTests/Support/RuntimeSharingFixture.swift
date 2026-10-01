//
//  RuntimeSharingFixture.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// RuntimeSharingFixture uses real contracts and two independently assigned addon features.
struct RuntimeSharingFixture: Sendable {
    let runtime   : AddonRuntime
    let governor  : ResourceGovernor
    let access    : GatedRuntimeResourceAccess
    let adapter   : RecordingRuntimeAdapter
    let clock     : MutableRuntimeClock
    let owner     : AddonID
    let ids       : [PublicationID]
    let connection: RuntimeConnection
    let wall      : Date

    static func make(partitions: [AssetPrivacyPartition] = [.addonOwned, .addonOwned]) async throws
        -> Self
    {
        let base = try ActionFixture()
        let installed = try replacing(
            base.context().installed,
            features: [
                AddonFeature(
                    id      : "controls",
                    requires: [],
                    actions : nil
                ),
                AddonFeature(
                    id      : "activity",
                    requires: [],
                    actions : nil
                )
            ]
        )
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(
            instant: RuntimeInstant(
                wall     : base.wall,
                monotonic: .zero
            )
        )
        let runtime = try await AddonRuntime.make(
            catalog    : [installed],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
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
        for (
            index,
            feature
        ) in ["controls", "activity"].enumerated() {
            ids.append(
                try await runtime.assignPublication(
                    owner                : base.owner,
                    featureID            : feature,
                    instanceID           : UUID(),
                    assetPrivacyPartition: partitions[index]
                )
            )
        }
        let launch = try await runtime.requestLaunch(owner: base.owner)
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

    func publication(
        _ asset: String,
        index  : Int,
        privacy: ContentDocument.Privacy = .publicContent
    ) throws -> Publication {
        let document = try ContentDocument(
            root              : .text("Image"),
            privacy           : privacy,
            accessibilityLabel: "Image",
            assetIDs          : [asset]
        )
        let content = try PresentationSet(
            widget         : index == 0 ? document : nil,
            compactLeading : index == 1 ? document : nil,
            compactTrailing: index == 1 ? document : nil,
            minimal        : index == 1 ? document : nil,
            expanded       : index == 1 ? document : nil
        )
        return try Publication(
            id         : ids[index],
            revision   : 1,
            kind       : index == 0 ? .widget : .activity,
            content    : content,
            timeline   : nil,
            expiresAt  : wall.addingTimeInterval(60),
            stalePolicy: .remove
        )
    }

    func publish(
        _ publications: [Publication],
        sequence      : UInt64,
        ends          : [PublicationID] = []
    ) async throws -> PublicationAdmission {
        try await receivePublicationOutput(
            runtime: runtime,
            adapter: adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : publications,
                operations   : ends.map { .endPublication($0) },
                completion   : nil,
                checkpoint   : nil
            ),
            connection: connection,
            sequence  : sequence
        )
    }

    func image(
        _ asset: String,
        index  : Int
    ) async -> CGImage? {
        await runtime.assetImage(
            assetID            : asset,
            publicationID      : ids[index],
            publicationRevision: 1
        )
    }
}
