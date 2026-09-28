//
//  AddonRuntimeAssetSharingTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

@Suite(.timeLimit(.minutes(1)))
struct AddonRuntimeAssetSharingTests {
    @Test
    func sharingAcrossFeaturesKeepsOneRasterAndIndependentPublicationLifetimes() async throws {
        let fixture = try await RuntimeSharingFixture.make()
        let source = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let before = try #require(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        )
        let shared = try await fixture.runtime.shareAsset(
            assetID   : source.assetID,
            from      : fixture.ids[0],
            to        : fixture.ids[1],
            connection: fixture.connection
        )
        #expect(source.assetID != shared.assetID)
        #expect(shared.publicationID == fixture.ids[1])
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
                + 4096
        )
        _ = try await fixture.publish(
            [
                fixture.publication(
                    source.assetID,
                    index  : 0,
                    privacy: .sensitive
                ),
                fixture.publication(
                    shared.assetID,
                    index: 1
                )
            ],
            sequence: 1
        )
        var sourceImage = await fixture.image(
            source.assetID,
            index: 0
        )
        var sharedImage = await fixture.image(
            shared.assetID,
            index: 1
        )
        #expect(sourceImage != nil)
        #expect(sourceImage === sharedImage)
        try await fixture.runtime.releaseAsset(
            assetID      : source.assetID,
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
        }
        _ = try await fixture.publish(
            [],
            sequence: 2,
            ends    : [fixture.ids[0]]
        )
        #expect(
            await fixture.image(
                source.assetID,
                index: 0
            ) == nil
        )
        #expect(
            await fixture.image(
                shared.assetID,
                index: 1
            ) === sharedImage
        )
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(
            await fixture.image(
                shared.assetID,
                index: 1
            ) === sharedImage
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.shareAsset(
                assetID   : shared.assetID,
                from      : fixture.ids[1],
                to        : fixture.ids[0],
                connection: fixture.connection
            )
        }
        await fixture.runtime.stop()
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(sourceImage?.width == 1)
        #expect(sharedImage?.height == 1)
        sourceImage = nil
        sharedImage = nil
        for _ in 0..<1000 {
            if await fixture.governor.usage(.assetBytes) == 0 { break }
            await Task.yield()
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
    }

    @Test
    func hostPartitionIsImmutableAndCannotBeChosenByContentPrivacy() async throws {
        let partition = AssetPrivacyPartition.isolated(UUID())
        let fixture = try await RuntimeSharingFixture.make(partitions: [.addonOwned, partition])
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.assignPublication(
                owner                : fixture.owner,
                featureID            : "controls",
                instanceID           : fixture.ids[0].instanceID,
                assetPrivacyPartition: partition
            )
        }
        #expect(
            try await fixture.runtime.assignPublication(
                owner     : fixture.owner,
                featureID : "controls",
                instanceID: fixture.ids[0].instanceID
            ) == fixture.ids[0]
        )
        let source = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        _ = try await fixture.publish(
            [
                fixture.publication(
                    source.assetID,
                    index  : 0,
                    privacy: .sensitive
                )
            ],
            sequence: 1
        )
        #expect(
            await fixture.image(
                source.assetID,
                index: 0
            )?.width == 1
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test(arguments: ["cancel", "disable", "exit"])
    func sharingRevalidatesAuthorityAfterMetadataAdmission(interruption: String) async throws {
        let fixture = try await RuntimeSharingFixture.make()
        let source = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await fixture.access.armResize()
        let task = Task {
            try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
        }
        await fixture.access.waitForArrival()
        switch interruption {
        case "cancel": task.cancel()
        case "disable": await fixture.runtime.disable(owner: fixture.owner)
        default: await fixture.runtime.observeExit(fixture.connection.incarnation)
        }
        await fixture.access.releaseGate()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.isEmpty)
        if interruption == "cancel" {
            #expect(
                await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
                    == before
            )
            #expect(await fixture.governor.usage(.assetBytes) == 4)
            let shared = try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
            #expect(shared.publicationID == fixture.ids[1])
            #expect(await fixture.governor.usage(.assetBytes) == 4)
        }
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        for _ in 0..<1000 {
            if await fixture.governor.usage(.assetBytes) == 0 { break }
            await Task.yield()
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
    }

    @Test
    func sharedAliasMetadataDenialDoesNotDecodeOrInvalidateSource() async throws {
        let fixture = try await RuntimeSharingFixture.make()
        let source = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let used = await fixture.governor.usage(.retainedStateBytes)
        let fillerOwner = try #require(AddonID(rawValue: "com.example.sharing-filler"))
        let filler = try await fixture.governor.admit(
            .state(bytes: 8 * 1024 * 1024 - used - 1024),
            owner: fillerOwner
        )
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        try await fixture.governor.release(
            filler.id,
            owner: fillerOwner
        )
        let shared = try await fixture.runtime.shareAsset(
            assetID   : source.assetID,
            from      : fixture.ids[0],
            to        : fixture.ids[1],
            connection: fixture.connection
        )
        #expect(shared.assetID != source.assetID)
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }
    @Test(arguments: [0, 1])
    func expiredAssignmentCannotShareBeforeDeadlineCleanup(expiredIndex: Int) async throws {
        let fixture = try await RuntimeSharingFixture.make()
        let source = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let local =
            expiredIndex == 0
            ? source
            : try await fixture.runtime.importAsset(
                encoded      : sharingPNG(),
                publicationID: fixture.ids[1],
                connection   : fixture.connection
            )
        _ = try await fixture.publish(
            [
                fixture.publication(
                    local.assetID,
                    index: expiredIndex
                )
            ],
            sequence: 1
        )
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(61),
                monotonic: .seconds(61)
            )
        )
        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
        }
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

}

/// RuntimeSharingFixture uses real contracts and two independently assigned addon features.
private struct RuntimeSharingFixture: Sendable {
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

/// sharingPNG supplies a real encoded image to the runtime-owned decoder.
private func sharingPNG() throws -> Data {
    let bytes = Data([255, 0, 0, 255])
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let image = try #require(
        CGImage(
            width            : 1,
            height           : 1,
            bitsPerComponent : 8,
            bitsPerPixel     : 32,
            bytesPerRow      : 4,
            space            : colorSpace,
            bitmapInfo       : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider         : provider,
            decode           : nil,
            shouldInterpolate: false,
            intent           : .defaultIntent
        )
    )
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        )
    )
    CGImageDestinationAddImage(
        destination,
        image,
        nil
    )
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}
