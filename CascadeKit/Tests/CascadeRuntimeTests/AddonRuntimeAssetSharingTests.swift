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
        let source  = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let before = try #require(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes)
        let shared = try await fixture.runtime.shareAsset(
            assetID   : source.assetID,
            from      : fixture.ids[0],
            to        : fixture.ids[1],
            connection: fixture.connection
        )
        #expect(source.assetID != shared.assetID)
        #expect(shared.publicationID == fixture.ids[1])
        #expect(await fixture.governor.usage(.assetBytes) == 4)
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before + 4096)

        _ = try await fixture.publish(
            [
                fixture.publication(
                    source.assetID,
                    index  : 0,
                    privacy: .sensitive
                ),
                fixture.publication(shared.assetID, index: 1)
            ],
            sequence: 1
        )
        var sourceImage = await fixture.image(source.assetID, index: 0)
        var sharedImage = await fixture.image(shared.assetID, index: 1)
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
        #expect(await fixture.image(source.assetID, index: 0) == nil)
        #expect(await fixture.image(shared.assetID, index: 1) === sharedImage)

        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(await fixture.image(shared.assetID, index: 1) === sharedImage)
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
        try await settle { await fixture.governor.usage(.assetBytes) == 0 }

        #expect(await fixture.governor.usage(.assetBytes) == 0)
    }

    @Test
    func hostPartitionIsImmutableAndCannotBeChosenByContentPrivacy() async throws {
        let partition = AssetPrivacyPartition.isolated(UUID())
        let fixture   = try await RuntimeSharingFixture.make(partitions: [.addonOwned, partition])
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.assignPublication(
                owner                : fixture.owner,
                featureID            : "controls",
                instanceID           : fixture.ids[0].instanceID,
                assetPrivacyPartition: partition
            )
        }
        #expect(try await fixture.runtime.assignPublication(
            owner     : fixture.owner,
            featureID : "controls",
            instanceID: fixture.ids[0].instanceID
        ) == fixture.ids[0])

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
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before)
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
        #expect(await fixture.image(source.assetID, index: 0)?.width == 1)

        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test(arguments: ["cancel", "disable", "exit"])
    func sharingRevalidatesAuthorityAfterMetadataAdmission(interruption: String) async throws {
        let fixture = try await RuntimeSharingFixture.make()
        let source  = try await fixture.runtime.importAsset(
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
            #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before)
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
        try await settle { await fixture.governor.usage(.assetBytes) == 0 }

        #expect(await fixture.governor.usage(.assetBytes) == 0)
    }

    @Test
    func sharedAliasMetadataDenialDoesNotDecodeOrInvalidateSource() async throws {
        let fixture = try await RuntimeSharingFixture.make()
        let source  = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let used        = await fixture.governor.usage(.retainedStateBytes)
        let fillerOwner = try #require(AddonID(rawValue: "com.example.sharing-filler"))
        let filler      = try await fixture.governor.admit(
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
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before)
        #expect(await fixture.governor.usage(.assetBytes) == 4)

        try await fixture.governor.release(filler.id, owner: fillerOwner)
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
        let source  = try await fixture.runtime.importAsset(
            encoded      : sharingPNG(),
            publicationID: fixture.ids[0],
            connection   : fixture.connection
        )
        let local = expiredIndex == 0
            ? source
            : try await fixture.runtime.importAsset(
                encoded      : sharingPNG(),
                publicationID: fixture.ids[1],
                connection   : fixture.connection
            )
        _ = try await fixture.publish(
            [
                fixture.publication(local.assetID, index: expiredIndex)
            ],
            sequence: 1
        )
        fixture.clock.set(RuntimeInstant(wall: fixture.wall.addingTimeInterval(61), monotonic: .seconds(61)))

        let before = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.shareAsset(
                assetID   : source.assetID,
                from      : fixture.ids[0],
                to        : fixture.ids[1],
                connection: fixture.connection
            )
        }
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == before)

        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }
}

/// sharingPNG supplies a real encoded image to the runtime-owned decoder.
private func sharingPNG() throws -> Data {
    let bytes      = Data([255, 0, 0, 255])
    let provider   = try #require(CGDataProvider(data: bytes as CFData))
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let image      = try #require(
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

    let data        = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))

    return data as Data
}
