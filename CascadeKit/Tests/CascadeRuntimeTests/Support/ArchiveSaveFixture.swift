//
//  ArchiveSaveFixture.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CascadeRuntime

/// ArchiveSaveFixture composes real runtime, native decoding, governor and SwiftData with fake transport only.
struct ArchiveSaveFixture: Sendable {

    let runtime   : AddonRuntime
    let governor  : ResourceGovernor
    let adapter   : RecordingRuntimeAdapter
    let clock     : MutableRuntimeClock
    let installed : InstalledAddon
    let ids       : [PublicationID]
    let connection: RuntimeConnection
    let archive   : SwiftDataArchive
    let root      : URL
    let wall      : Date

    var owner: AddonID { installed.manifest.id }

    static func make(
        partitions: [AssetPrivacyPartition] = [.addonOwned],
        observer  : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver()
    ) async throws -> Self {
        let base      = try ActionFixture()
        let installed = try base.context().installed
        let governor  = ResourceGovernor()
        let adapter   = RecordingRuntimeAdapter()
        let clock     = MutableRuntimeClock(
            instant: RuntimeInstant(wall: base.wall, monotonic: .zero)
        )

        let runtime = try await AddonRuntime.make(
            catalog    : [installed],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [base.owner: []],
                explicitBindings: []
            ),
            governor   : governor,
            adapter    : adapter,
            clock      : clock
        )

        var ids: [PublicationID] = []

        for (index, partition) in partitions.enumerated() {
            ids.append(
                try await runtime.assignPublication(
                    owner                : base.owner,
                    featureID            : index == 0 ? "controls" : "other",
                    instanceID           : UUID(),
                    assetPrivacyPartition: partition
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

        let root = URL(fileURLWithPath: "/private/tmp/cascade-runtime-save-\(UUID())")
        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )

        let archive = try await SwiftDataArchive.make(
            identity: installed.verifiedIdentity,
            root    : root,
            governor: governor,
            observer: observer
        )
        _ = try await archive.start()

        return Self(
            runtime   : runtime,
            governor  : governor,
            adapter   : adapter,
            clock     : clock,
            installed : installed,
            ids       : ids,
            connection: connection,
            archive   : archive,
            root      : root,
            wall      : base.wall
        )
    }

    func content(
        text : String = "Image",
        asset: String? = nil
    ) throws -> PresentationSet {
        try PresentationSet(
            widget         : ContentDocument(
                root              : .text(text),
                privacy           : .publicContent,
                accessibilityLabel: text,
                assetIDs          : asset.map { [$0] } ?? []
            ),
            compactLeading : nil,
            compactTrailing: nil,
            minimal        : nil,
            expanded       : nil
        )
    }

    func publication(
        index   : Int = 0,
        asset   : String? = nil,
        revision: UInt64 = 1
    ) throws -> Publication {
        try Publication(
            id         : ids[index],
            revision   : revision,
            kind       : .widget,
            content    : content(asset: asset),
            timeline   : nil,
            expiresAt  : wall.addingTimeInterval(100),
            stalePolicy: .remove
        )
    }

    func publish(
        _ publications: [Publication],
        sequence      : UInt64,
        ends          : [PublicationID] = []
    ) async throws {
        _ = try await receivePublicationOutput(
            runtime   : runtime,
            adapter   : adapter,
            output    : ProviderOutput(
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

    /// matches keeps decoded leaves and one graph inside admitted scopes and returns only a Boolean.
    func matches(_ check: @Sendable (RuntimeArchiveEnvelope) throws -> Bool) async throws -> Bool {
        try await archive.withGeneration { generation in
            guard let generation else { return false }

            return try await governor.withAssetDecodeReservation(
                bytes: RuntimeArchiveEnvelope.retentionReservationBytes() + generation.payload.count,
                owner: owner
            ) {
                let envelope = try RuntimeArchiveEnvelope.decode(generation.payload)
                return try await governor.withAssetDecodeReservation(
                    bytes: RuntimeArchivePublicationCodec.inspectionReservationBytes(),
                    owner: owner
                ) { try check(envelope) }
            }
        }
    }

    func stop() async {
        await runtime.stop()
        await runtime.observeExit(connection.incarnation)
    }

    func removeFiles() { try? FileManager.default.removeItem(at: root) }
}
