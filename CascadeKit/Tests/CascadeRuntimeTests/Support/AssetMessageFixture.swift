//
//  AssetMessageFixture.swift
//  CascadeKit
//

import CascadeAddonSDK
import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// AssetMessageFixture assembles the real host mechanisms behind the deterministic bridge.
struct AssetMessageFixture: Sendable {
    let root        : URL
    let runtime     : AddonRuntime
    let governor    : ResourceGovernor
    let access      : GatedRuntimeResourceAccess
    let adapter     : RecordingRuntimeAdapter
    let connection  : RuntimeConnection
    let channel     : RuntimeAssetChannelBridge
    let clock       : MutableRuntimeClock
    let ids         : [PublicationID]
    let owner       : AddonID
    let wall        : Date

    /// make builds the fixture; mixedPrivacy gives the second host assignment an isolated asset
    /// privacy partition so a cross-private sharing refusal can be exercised against the real
    /// canonical scope check.
    static func make(mixedPrivacy: Bool = false) async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp/cascade-message-asset-\(UUID())")
        let keyedRoot = root.appendingPathComponent("keyed")
        let checkpoint = root.appendingPathComponent("checkpoint")
        let archive = root.appendingPathComponent("archive")
        for directory in [root, keyedRoot, checkpoint, archive] {
            try FileManager.default.createDirectory(
                at                         : directory,
                withIntermediateDirectories: false,
                attributes                 : [.posixPermissions: 0o700]
            )
        }
        let action = try ActionFixture()
        let installed = try action.context().installed
        let governor = ResourceGovernor()
        let access = GatedRuntimeResourceAccess(target: governor)
        let adapter = RecordingRuntimeAdapter()
        let storage = try await AddonStorageCoordinator.make(
            checkpointRoot: checkpoint,
            keyedRoot     : keyedRoot,
            archiveRoot   : archive,
            registrations : [
                StateRegistration(
                    identity            : installed.verifiedIdentity,
                    maximumSchemaVersion: 1
                )
            ],
            governor      : governor,
            resourceAccess: governor
        )
        try await storage.start()
        let clock = MutableRuntimeClock(
            instant: RuntimeInstant(
                wall     : action.wall,
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
                grants          : [installed.manifest.id: []],
                explicitBindings: [],
                protocolVersion : (1, 2)
            ),
            governor              : governor,
            resourceAccess        : access,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock,
            storageCoordinator    : storage
        )
        var ids: [PublicationID] = []
        ids.append(
            try await runtime.assignPublication(
                owner     : installed.manifest.id,
                featureID : "controls",
                instanceID: UUID()
            )
        )
        ids.append(
            try await runtime.assignPublication(
                owner                : installed.manifest.id,
                featureID            : "controls",
                instanceID           : UUID(),
                assetPrivacyPartition: mixedPrivacy ? .isolated(UUID()) : .addonOwned
            )
        )
        let launch = try await runtime.requestLaunch(owner: installed.manifest.id)
        let connection = try await runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 2,
                contentSchemas: [1]
            )
        )
        let channel = RuntimeAssetChannelBridge(
            runtime   : runtime,
            adapter   : adapter,
            connection: connection
        )
        return Self(
            root      : root,
            runtime   : runtime,
            governor  : governor,
            access    : access,
            adapter   : adapter,
            connection: connection,
            channel   : channel,
            clock     : clock,
            ids       : ids,
            owner     : installed.manifest.id,
            wall      : action.wall
        )
    }

    func content(_ asset: String?) throws -> PresentationSet {
        try PresentationSet(
            widget: ContentDocument(
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
        id      : PublicationID,
        asset   : String?,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : id,
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

    /// exchange forwards one real codec frame through the bridge and decodes the host reply.
    func exchange(
        _ request : AssetTransferRequest,
        sequence  : UInt64
    ) async throws -> AssetTransferResponse {
        try AssetTransferFrameCodec.decodeResponse(
            try await channel.exchange(
                try AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                sequence: sequence
            ),
            profile: .v1
        )
    }

    /// importAlias runs the real begin/chunk/finish frames for one single-chunk alias.
    func importAlias(
        _ png: Data,
        publicationID: PublicationID,
        sequences: (UInt64, UInt64, UInt64)
    ) async throws -> AssetHandle {
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: publicationID,
            totalBytes   : png.count
        )
        let begun = try await exchange(
            begin,
            sequence: sequences.0
        )
        let transferID = try #require(begun.transferID)
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : png
        )
        _ = try await exchange(
            chunk,
            sequence: sequences.1
        )
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let imported = try await exchange(
            finish,
            sequence: sequences.2
        )
        return try #require(imported.assetHandle)
    }

    /// rawExchange drives one frame directly through the runtime (no bridge) and consumes the
    /// exact host receipt, returning the decoded reply. It is only used where a test deliberately
    /// rejects the handoff and the bridge would therefore refuse the frame.
    func rawExchange(
        _ request : AssetTransferRequest,
        sequence  : UInt64
    ) async throws -> AssetTransferResponse {
        let handle = try #require(
            adapter.stageAssetIngress(
                try AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                incarnation: connection.incarnation,
                sequence   : sequence
            )
        )
        let result = await runtime.receiveAssetRequest(
            handle,
            connection: connection
        )
        guard case .completed(_, .handedOff) = result,
            case .assetResponse(let delivery)? = adapter.currentDelivery(incarnation: connection.incarnation)
        else {
            throw AddonFailure(
                code  : .dependencyUnavailable,
                reason: "The host did not hand off an asset reply."
            )
        }
        guard await runtime.receiveAssetReceipt(
            delivery.receipt,
            connection: connection
        ) else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The exact asset receipt was refused."
            )
        }
        return try AssetTransferFrameCodec.decodeResponse(
            delivery.payload,
            profile: .v1
        )
    }

    /// rawResult stages and forwards one frame but returns the raw scalar host outcome, so a test
    /// can observe a rejected handoff without the bridge's own refusal.
    func rawResult(
        _ request : AssetTransferRequest,
        sequence  : UInt64
    ) async throws -> AddonRuntime.RuntimeAssetRequestResult {
        let handle = try #require(
            adapter.stageAssetIngress(
                try AssetTransferFrameCodec.encode(
                    request,
                    profile: .v1
                ),
                incarnation: connection.incarnation,
                sequence   : sequence
            )
        )
        return await runtime.receiveAssetRequest(
            handle,
            connection: connection
        )
    }

    func tearDown() async {
        await runtime.stop()
        await runtime.observeExit(connection.incarnation)
        try? FileManager.default.removeItem(at: root)
    }
}
