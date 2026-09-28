//
//  MessageAddonAssetIntegrationTests.swift
//  CascadeKit
//

import CascadeAddonSDK
import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// MessageAddonAssetIntegrationTests exercises the real message path
/// `MessageAddonAssetClient -> AddonAssetMessageChannel bridge -> AddonRuntime -> AssetState`
/// with the real Foundation codec, assembler, ImageIO decoder and canonical alias state.
/// It does not qualify any native OS transport: the bridge is test-only.
@Suite(.timeLimit(.minutes(1)))
struct MessageAddonAssetIntegrationTests {
    @Test
    func messageImportPublishesSharesAndReleasesCanonicalAliases() async throws {
        let fixture = try await AssetMessageFixture.make()
        let client = MessageAddonAssetClient(channel: fixture.channel)
        let png = try randomPNG(
            width: 192,
            height: 192
        )
        #expect(png.count > AssetTransferFrameCodec.maximumChunkBytes)

        let imported = try await client.importAsset(
            png,
            publicationID: fixture.ids[0]
        )
        #expect(imported.width == 192)
        #expect(imported.publicationID == fixture.ids[0])
        // The alias is canonical but not yet reachable through a publication revision.
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            ) == nil
        )
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id: fixture.ids[0],
                    asset: imported.assetID
                )
            ],
            sequence: 1
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 192
        )

        let shared = try await client.shareAsset(
            imported,
            to: fixture.ids[1]
        )
        #expect(shared.assetID != imported.assetID)
        #expect(shared.owner == imported.owner)
        #expect(shared.publicationID == fixture.ids[1])
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id: fixture.ids[1],
                    asset: shared.assetID
                )
            ],
            sequence: 2
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : shared.assetID,
                publicationID      : fixture.ids[1],
                publicationRevision: 1
            )?.width == 192
        )

        try await client.releaseAsset(imported)
        // Releasing drops the import alias but not already published pins.
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 192
        )
        await #expect(throws: AddonFailure.self) {
            try await client.shareAsset(
                imported,
                to: fixture.ids[1]
            )
        }
        #expect(
            await fixture.runtime.assetImage(
                assetID            : shared.assetID,
                publicationID      : fixture.ids[1],
                publicationRevision: 1
            )?.width == 192
        )
        await client.close()
        await fixture.tearDown()
    }

    @Test
    func foreignSequenceAndOversizedIngressAreRefusedWithoutDisturbingTheTransfer() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width: 32,
            height: 32
        )
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : png.count
        )
        let beginFrame = try AssetTransferFrameCodec.encode(
            begin,
            profile: .v1
        )
        let begun = try AssetTransferFrameCodec.decodeResponse(
            try await fixture.channel.exchange(
                beginFrame,
                sequence: 1
            ),
            profile: .v1
        )
        let transferID = try #require(begun.transferID)
        // A duplicate/stale sequence is refused before the runtime takes the bytes.
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.channel.exchange(
                beginFrame,
                sequence: 1
            )
        }
        // A mismatched actual size is refused after taking and before mutation.
        let mismatchedHandle = try #require(
            fixture.adapter.stageAssetIngress(
                Data([0x01, 0x02]),
                incarnation: fixture.connection.incarnation,
                sequence: 3,
                advertisedBytes: 4
            )
        )
        let mismatched = await fixture.runtime.receiveAssetRequest(
            mismatchedHandle,
            connection: fixture.connection
        )
        #expect(mismatched == .refused(.invalidPayload))
        // The original transfer is still live and completes normally.
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : png
        )
        _ = try await fixture.channel.exchange(
            try AssetTransferFrameCodec.encode(
                chunk,
                profile: .v1
            ),
            sequence: 4
        )
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let imported = try AssetTransferFrameCodec.decodeResponse(
            try await fixture.channel.exchange(
                try AssetTransferFrameCodec.encode(
                    finish,
                    profile: .v1
                ),
                sequence: 5
            ),
            profile: .v1
        )
        #expect(imported.result == .imported)
        #expect(imported.assetHandle != nil)
        await fixture.tearDown()
    }

    @Test
    func foreignAssignmentAndExpiredTransferAreRefused() async throws {
        let fixture = try await AssetMessageFixture.make()
        // A begin for an unassigned publication is refused with bounded authority.
        let foreign = PublicationID(
            addonID   : fixture.owner,
            instanceID: UUID(),
            sessionID : UUID()
        )
        let foreignBegin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: foreign,
            totalBytes   : 16
        )
        let foreignResponse = try AssetTransferFrameCodec.decodeResponse(
            try await fixture.channel.exchange(
                try AssetTransferFrameCodec.encode(
                    foreignBegin,
                    profile: .v1
                ),
                sequence: 1
            ),
            profile: .v1
        )
        #expect(foreignResponse.result == .failure)
        #expect(foreignResponse.failureCode == .permissionDenied)

        // A live transfer expires after the nonrenewable 30-second deadline is serviced.
        let png = try randomPNG(
            width: 32,
            height: 32
        )
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : png.count
        )
        let begun = try AssetTransferFrameCodec.decodeResponse(
            try await fixture.channel.exchange(
                try AssetTransferFrameCodec.encode(
                    begin,
                    profile: .v1
                ),
                sequence: 2
            ),
            profile: .v1
        )
        let transferID = try #require(begun.transferID)
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : png
        )
        _ = try await fixture.channel.exchange(
            try AssetTransferFrameCodec.encode(
                chunk,
                profile: .v1
            ),
            sequence: 3
        )
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(31),
                monotonic: .seconds(31)
            )
        )
        let charged = await fixture.governor.usage(.admittedMemoryBytes)
        _ = try await fixture.runtime.serviceDeadlines()
        // Expiry is the existing deferred cleanup path: it refunds the idle assembly exactly.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) < charged)
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let expired = try AssetTransferFrameCodec.decodeResponse(
            try await fixture.channel.exchange(
                try AssetTransferFrameCodec.encode(
                    finish,
                    profile: .v1
                ),
                sequence: 4
            ),
            profile: .v1
        )
        #expect(expired.result == .failure)
        await fixture.tearDown()
    }

    @Test
    func stopWithoutObservedExitDrainsIdleAssembly() async throws {
        let fixture = try await AssetMessageFixture.make()
        let totalBytes = 1_048_576
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : totalBytes
        )
        let begun = try AssetTransferFrameCodec.decodeResponse(
            try await fixture.channel.exchange(
                try AssetTransferFrameCodec.encode(
                    begin,
                    profile: .v1
                ),
                sequence: 1
            ),
            profile: .v1
        )
        #expect(begun.result == .begun)
        // One protected transfer holds two encoded-sized buffers plus control bytes.
        let charged = beforeMemory + 2 * totalBytes + 4_096
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        // Synchronous stop revokes authority immediately and keeps the process record.
        let stopped = await fixture.runtime.requestStop()
        #expect(stopped.cleanupPending && stopped.retainedProcessCount == 1)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        // Bounded deferred cleanup releases the idle assembly with no observed exit.
        await fixture.runtime.stop()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        #expect(await fixture.runtime.requestStop().cleanupPending == false)
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        try? FileManager.default.removeItem(at: fixture.root)
    }

    @Test
    func publicationEndRevokesIdleReceivingTransferWithoutWaitingForDeadline() async throws {
        let fixture = try await AssetMessageFixture.make()
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: nil
                )
            ],
            sequence: 1
        )
        let totalBytes = 1_048_576
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : totalBytes
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 2
        )
        let transferID = try #require(begun.transferID)
        #expect(begun.result == .begun)
        #expect(
            await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory + 2 * totalBytes + 4_096
        )
        // Ending the exact bound publication revokes the idle receiving transfer at once,
        // without process exit and without waiting out the 30-second transfer deadline.
        _ = try await fixture.publish(
            [],
            sequence: 3,
            ends    : [fixture.ids[0]]
        )
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        // The revoked transfer no longer owns a runtime identity and is refused.
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let refused = try await fixture.exchange(
            finish,
            sequence: 4
        )
        #expect(refused.result == .failure)
        await fixture.tearDown()
    }

    @Test
    func publicationExpiryRevokesIdleReceivingTransferBeforeTransferDeadline() async throws {
        let fixture = try await AssetMessageFixture.make()
        let expiry = try Publication(
            id         : fixture.ids[0],
            revision   : 1,
            kind       : .widget,
            content    : fixture.content(nil),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(5),
            stalePolicy: .remove
        )
        _ = try await fixture.publish(
            [expiry],
            sequence: 1
        )
        let totalBytes = 1_048_576
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : totalBytes
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 2
        )
        #expect(begun.result == .begun)
        // The publication expires well before the nonrenewable 30-second transfer deadline.
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(10),
                monotonic: .seconds(10)
            )
        )
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        await fixture.tearDown()
    }

    @Test
    func finishMetadataDenialDisposesExactTransferAndReconcilesPool() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 64,
            height: 64
        )
        #expect(png.count <= AssetTransferFrameCodec.maximumChunkBytes)
        let beforePool = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : png.count
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : png
        )
        let chunked = try await fixture.exchange(
            chunk,
            sequence: 2
        )
        #expect(chunked.result == .acknowledged)
        // Fill the retained-state ceiling so the finish metadata admission is refused before any
        // decode borrows the protected assembly.
        let fillerOwner = try #require(AddonID(rawValue: "com.example.asset-message-quota"))
        let retained = await fixture.governor.usage(.retainedStateBytes)
        // Leave 2 KiB of retained-state headroom: enough for the request's 1 KiB scratch entry,
        // but far less than the 4 KiB import metadata admission the finish must request.
        let filler = try await fixture.governor.admit(
            .state(bytes: 8 * 1_024 * 1_024 - retained - 2_048),
            owner: fillerOwner
        )
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let refused = try await fixture.exchange(
            finish,
            sequence: 3
        )
        #expect(refused.result == .failure)
        // The exact receiving transfer and its protected reservation are both disposed.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == beforePool
        )
        try await fixture.governor.release(
            filler.id,
            owner: fillerOwner
        )
        // The same process assembler remains usable for a later protected transfer.
        let retried = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : png.count
        )
        let retriedBegin = try await fixture.exchange(
            retried,
            sequence: 4
        )
        let retriedID = try #require(retriedBegin.transferID)
        #expect(retriedBegin.result == .begun)
        let retriedChunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: retriedID,
            offset    : 0,
            bytes     : png
        )
        let retriedChunked = try await fixture.exchange(
            retriedChunk,
            sequence: 5
        )
        #expect(retriedChunked.result == .acknowledged)
        let retriedFinish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: retriedID
        )
        let imported = try await fixture.exchange(
            retriedFinish,
            sequence: 6
        )
        #expect(imported.result == .imported)
        await fixture.tearDown()
    }

    @Test
    func messageImportAndReleaseReconcilePoolCharges() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 48,
            height: 48
        )
        let beforePool = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let beforeRetained = await fixture.governor.usage(.retainedStateBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : png.count
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : png
        )
        _ = try await fixture.exchange(
            chunk,
            sequence: 2
        )
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let imported = try await fixture.exchange(
            finish,
            sequence: 3
        )
        let handle = try #require(imported.assetHandle)
        #expect(imported.result == .imported)
        let afterImport = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        #expect((afterImport ?? 0) > (beforePool ?? 0))
        // Releasing the message-minted alias must reconcile the pooled metadata quote exactly;
        // this fails if pendingAssetMetadataBytes outlives the protected import.
        let release = try AssetTransferRequest(
            requestID   : UUID(),
            operation   : .release,
            sourceHandle: handle
        )
        let released = try await fixture.exchange(
            release,
            sequence: 4
        )
        #expect(released.result == .acknowledged)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == beforePool
        )
        #expect(await fixture.governor.usage(.retainedStateBytes) == beforeRetained)
        await fixture.tearDown()
    }

    @Test
    func failedMessageDecodeReconcilesImportMetadataAndAssembler() async throws {
        let fixture = try await AssetMessageFixture.make()
        let beforePool = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let beforeRetained = await fixture.governor.usage(.retainedStateBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 3
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : Data([1, 2, 3])
        )
        let chunked = try await fixture.exchange(
            chunk,
            sequence: 2
        )
        #expect(chunked.result == .acknowledged)
        let finish = try AssetTransferRequest(
            requestID : UUID(),
            operation : .finish,
            transferID: transferID
        )
        let failed = try await fixture.exchange(
            finish,
            sequence: 3
        )
        #expect(failed.result == .failure)
        // The prepaid import quote was set before the protected decode; it must not survive it.
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == beforePool
        )
        #expect(await fixture.governor.usage(.retainedStateBytes) == beforeRetained)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        await fixture.tearDown()
    }

    @Test
    func messageShareAndReleaseReconcileSharedPoolCharges() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 48,
            height: 48
        )
        let beforePool = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let imported = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        let afterImport = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let afterImportRetained = await fixture.governor.usage(.retainedStateBytes)
        let share = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .share,
            publicationID: fixture.ids[1],
            sourceHandle : imported
        )
        let shared = try await fixture.exchange(
            share,
            sequence: 4
        )
        let sharedHandle = try #require(shared.assetHandle)
        #expect(shared.result == .shared)
        #expect(
            (await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes ?? 0)
                > (afterImport ?? 0)
        )
        // Releasing only the shared alias must reconcile the sharing quote exactly; this fails
        // if pendingAssetMetadataBytes outlives the protected share.
        let releaseShared = try AssetTransferRequest(
            requestID   : UUID(),
            operation   : .release,
            sourceHandle: sharedHandle
        )
        let releasedShared = try await fixture.exchange(
            releaseShared,
            sequence: 5
        )
        #expect(releasedShared.result == .acknowledged)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == afterImport
        )
        #expect(await fixture.governor.usage(.retainedStateBytes) == afterImportRetained)
        let releaseImported = try AssetTransferRequest(
            requestID   : UUID(),
            operation   : .release,
            sourceHandle: imported
        )
        let releasedImported = try await fixture.exchange(
            releaseImported,
            sequence: 6
        )
        #expect(releasedImported.result == .acknowledged)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == beforePool
        )
        await fixture.tearDown()
    }

    @Test(arguments: [false, true])
    func closeDuringHeldHandoffDrainsExchangeAndRevokesConnection(quiescing: Bool) async throws {
        let fixture = try await AssetMessageFixture.make()
        if quiescing {
            let pinned = try await fixture.runtime.importAsset(
                encoded      : randomPNG(width: 32, height: 32),
                publicationID: fixture.ids[1],
                connection   : fixture.connection
            )
            _ = try await fixture.publish(
                [fixture.publication(id: fixture.ids[1], asset: pinned.assetID)],
                sequence: 1
            )
        }
        let pinnedBytes = await fixture.governor.usage(.assetBytes)
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 1_048_576
        )
        let frame = try AssetTransferFrameCodec.encode(
            begin,
            profile: .v1
        )
        await fixture.channel.armHold(at: .afterHandoff)
        let exchange = Task { try await fixture.channel.exchange(frame, sequence: 1) }
        await fixture.channel.waitForHoldArrival()
        // The host has physically staged a real reply in the bounded adapter slot, while the idle
        // assembler still holds its protected reservation.
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) != nil)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) > beforeMemory)
        if quiescing {
            _ = try await fixture.runtime.beginArchiveQuiescence(until: .seconds(10))
            // Shared publication staging must also be disposed, independently of the held
            // asset exchange. Quiescence itself neither stops the process nor drains it.
            _ = try #require(fixture.adapter.stageIngress(
                ProviderOutput(
                    schemaVersion: 1,
                    publications : [],
                    operations   : [],
                    completion   : nil,
                    checkpoint   : nil
                ),
                incarnation: fixture.connection.incarnation
            ))
            let current = fixture.connection
            let stale = RuntimeConnection(
                token                : current.token,
                incarnation          : RuntimeIncarnation(),
                identity             : current.identity,
                digest               : current.digest,
                publicationConnection: current.publicationConnection,
                serviceSession       : current.serviceSession,
                authorityRevision    : current.authorityRevision
            )
            await fixture.runtime.closeConnection(stale)
            #expect(fixture.adapter.stopCount(incarnation: current.incarnation) == 0)
            #expect(fixture.adapter.hasIngress(incarnation: current.incarnation))
            #expect(fixture.adapter.currentDelivery(incarnation: current.incarnation) != nil)
        }
        // Repeated and concurrent close callers all await the one real drain, not a closed flag.
        async let firstClose: Void = fixture.channel.close()
        async let secondClose: Void = fixture.channel.close()
        _ = await firstClose
        _ = await secondClose
        await fixture.channel.close()
        #expect(fixture.channel.didDrainInFlightExchange)
        #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 1)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        // The exact idle assembler is refunded once the real drain completes.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == 1)
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.hasProcess == true)
        if quiescing {
            #expect(pinnedBytes > 0)
            #expect(await fixture.governor.usage(.assetBytes) == pinnedBytes)
            #expect(await fixture.governor.usage(.publications) == 1)
        }
        // The in-flight caller is drained to a real bounded refusal, not merely cancelled.
        await #expect(throws: AddonFailure.self) {
            _ = try await exchange.value
        }
        // The same connection cannot carry another frame after close.
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.channel.exchange(frame, sequence: 2)
        }
        #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 1)
        // Even a fresh bridge over the exact same RuntimeConnection cannot revive the physical
        // slot: close revoked the real connection, not just the bridge's local flag.
        let revived = RuntimeAssetChannelBridge(
            runtime   : fixture.runtime,
            adapter   : fixture.adapter,
            connection: fixture.connection
        )
        await #expect(throws: AddonFailure.self) {
            _ = try await revived.exchange(frame, sequence: 1)
        }
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await fixture.tearDown()
    }

    @Test
    func cancellingTheCallerDoesNotAbandonTheHeldPhysicalExchange() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 1_048_576
        )
        let frame = try AssetTransferFrameCodec.encode(
            begin,
            profile: .v1
        )
        await fixture.channel.armHold(at: .beforeReceive)
        let exchange = Task { try await fixture.channel.exchange(frame, sequence: 1) }
        await fixture.channel.waitForHoldArrival()
        exchange.cancel()
        await Task.yield()
        // Cancellation alone is not proof of rejection or disposal: the real staged frame is still
        // held and the runtime has not stopped anything.
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 0)
        // Only the explicit drain releases it, and it ends in a real refusal.
        await fixture.channel.close()
        #expect(fixture.channel.didDrainInFlightExchange)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await #expect(throws: AddonFailure.self) {
            _ = try await exchange.value
        }
        await fixture.tearDown()
    }

    @Test
    func secondExchangeWhileOneIsHeldIsRefusedWithoutNewStaging() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 1_048_576
        )
        let frame = try AssetTransferFrameCodec.encode(
            begin,
            profile: .v1
        )
        await fixture.channel.armHold(at: .beforeReceive)
        let held = Task { try await fixture.channel.exchange(frame, sequence: 1) }
        await fixture.channel.waitForHoldArrival()
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        // The bounded slot refuses a second concurrent exchange before any new staging.
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.channel.exchange(frame, sequence: 2)
        }
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        // Close drains exactly the held frame.
        await fixture.channel.close()
        #expect(fixture.channel.didDrainInFlightExchange)
        await #expect(throws: AddonFailure.self) {
            _ = try await held.value
        }
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await fixture.tearDown()
    }

    @Test
    func duplicateSequenceIsRefusedBeforePhysicalStaging() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 1_048_576
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 1
        )
        #expect(begun.result == .begun)
        let takeAttempts = fixture.adapter.ingressTakeAttempts
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.exchange(
                begin,
                sequence: 1
            )
        }
        // The bridge refused the duplicate before staging, so the host never saw a second take.
        #expect(fixture.adapter.ingressTakeAttempts == takeAttempts)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await fixture.channel.close()
        await fixture.tearDown()
    }

    @Test
    func receiptMismatchDisposesRawReplyAndRefusesReuse() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 1_048_576
        )
        fixture.channel.armFault(.mismatchedReceipt)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.exchange(
                begin,
                sequence: 1
            )
        }
        // The mismatched physical receipt invalidates the bounded reply: its raw staging is
        // disposed and the channel refuses further frames until close revokes the connection.
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.exchange(
                begin,
                sequence: 2
            )
        }
        await fixture.channel.close()
        #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 1)
        await fixture.tearDown()
    }

    @Test
    func postHandoffTransportErrorDisposesRawReplyAndRefusesReuse() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 1_048_576
        )
        fixture.channel.armFault(.transportError)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.exchange(
                begin,
                sequence: 1
            )
        }
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.exchange(
                begin,
                sequence: 2
            )
        }
        await fixture.channel.close()
        #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 1)
        await fixture.tearDown()
    }

    // MARK: Shared ingress and delivery boundaries

    @Test
    func assetFramesShareOneTypedIngressWithPublicationAndStorage() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 8
        )
        let handle = try #require(
            fixture.adapter.stageAssetIngress(
                try AssetTransferFrameCodec.encode(
                    begin,
                    profile: .v1
                ),
                incarnation: fixture.connection.incarnation,
                sequence   : 1
            )
        )
        // The one shared typed slot refuses a publication or storage frame while the asset
        // frame is staged. This is the physical counterpart of the runtime's single ingress credit.
        #expect(
            fixture.adapter.stageIngress(
                try ProviderOutput(
                    schemaVersion: 1,
                    publications : [],
                    operations   : [],
                    completion   : nil,
                    checkpoint   : nil
                ),
                incarnation: fixture.connection.incarnation
            ) == nil
        )
        #expect(
            fixture.adapter.stageStorageIngress(
                Data([1]),
                incarnation: fixture.connection.incarnation,
                sequence   : 1
            ) == nil
        )
        #expect(
            await fixture.runtime.receiveAssetRequest(
                handle,
                connection: fixture.connection
            ) == .completed(
                .accepted,
                .handedOff
            )
        )
        // Only the exact accepted receipt frees the shared delivery credit.
        let delivery = try #require(
            fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation)
        )
        guard case .assetResponse(let assetDelivery) = delivery else {
            Issue.record("Expected an asset response delivery")
            await fixture.tearDown()
            return
        }
        #expect(
            await fixture.runtime.receiveAssetReceipt(
                assetDelivery.receipt,
                connection: fixture.connection
            )
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        await fixture.tearDown()
    }

    @Test
    func acceptedAssetReplyBlocksASecondFrameAndCrossChannelReceiptsCannotFreeIt() async throws {
        let fixture = try await AssetMessageFixture.make()
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 8
        )
        let frame = try AssetTransferFrameCodec.encode(
            begin,
            profile: .v1
        )
        let first = try #require(
            fixture.adapter.stageAssetIngress(
                frame,
                incarnation: fixture.connection.incarnation,
                sequence   : 1
            )
        )
        #expect(
            await fixture.runtime.receiveAssetRequest(
                first,
                connection: fixture.connection
            ) == .completed(
                .accepted,
                .handedOff
            )
        )
        let delivery = try #require(
            fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation)
        )
        guard case .assetResponse(let assetDelivery) = delivery else {
            Issue.record("Expected an asset response delivery")
            await fixture.tearDown()
            return
        }
        // A second frame is refused by the shared delivery credit before any backend take, so
        // the outstanding accepted reply is not disturbed.
        let second = try #require(
            fixture.adapter.stageAssetIngress(
                frame,
                incarnation: fixture.connection.incarnation,
                sequence   : 2
            )
        )
        let attempts = fixture.adapter.ingressTakeAttempts
        #expect(
            await fixture.runtime.receiveAssetRequest(
                second,
                connection: fixture.connection
            ) == .refused(.resourceDenied)
        )
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) != nil)
        // A cross-channel receipt (foreign incarnation and connection token) and a stale receipt
        // (wrong sequence) cannot free unrelated accepted work.
        let crossChannel = RuntimeAssetReceipt(
            token          : assetDelivery.receipt.token,
            incarnation    : RuntimeIncarnation(),
            connectionToken: UUID(),
            sequence       : assetDelivery.receipt.sequence,
            requestID      : assetDelivery.receipt.requestID,
            operation      : assetDelivery.receipt.operation
        )
        #expect(
            await fixture.runtime.receiveAssetReceipt(
                crossChannel,
                connection: fixture.connection
            ) == false
        )
        let stale = RuntimeAssetReceipt(
            token          : assetDelivery.receipt.token,
            incarnation    : fixture.connection.incarnation,
            connectionToken: fixture.connection.token,
            sequence       : assetDelivery.receipt.sequence &+ 1,
            requestID      : assetDelivery.receipt.requestID,
            operation      : assetDelivery.receipt.operation
        )
        #expect(
            await fixture.runtime.receiveAssetReceipt(
                stale,
                connection: fixture.connection
            ) == false
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) != nil)
        // Only the exact receipt frees the payload.
        #expect(
            await fixture.runtime.receiveAssetReceipt(
                assetDelivery.receipt,
                connection: fixture.connection
            )
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        await fixture.tearDown()
    }

    // MARK: Ingress refusal before backend work

    @Test
    func wrongIncarnationZeroSequenceAndOversizedAssetIngressAreRefusedWithoutTake() async throws {
        let fixture = try await AssetMessageFixture.make()
        let attempts = fixture.adapter.ingressTakeAttempts
        for handle in [
            RuntimeAssetIngressHandle(
                token       : UUID(),
                incarnation : RuntimeIncarnation(),
                encodedBytes: 1,
                sequence    : 1
            ),
            RuntimeAssetIngressHandle(
                token       : UUID(),
                incarnation : fixture.connection.incarnation,
                encodedBytes: 1,
                sequence    : 0
            ),
            RuntimeAssetIngressHandle(
                token       : UUID(),
                incarnation : fixture.connection.incarnation,
                encodedBytes: AssetTransferFrameCodec.maximumEncodedBytes + 1,
                sequence    : 1
            ),
        ] {
            #expect(
                await fixture.runtime.receiveAssetRequest(
                    handle,
                    connection: fixture.connection
                ) == .refused(.invalidPayload)
            )
        }
        // None of the illegal handles reached the backend or advanced the shared sequence.
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : 8
            ),
            sequence: 1
        )
        #expect(begun.result == .begun)
        await fixture.tearDown()
    }

    @Test(arguments: ["{}", "[]", "not-json"])
    func malformedRawAssetFramesAreRefusedWithoutReceipt(_ text: String) async throws {
        let fixture = try await AssetMessageFixture.make()
        let handle = try #require(
            fixture.adapter.stageAssetIngress(
                Data(text.utf8),
                incarnation: fixture.connection.incarnation,
                sequence   : 1
            )
        )
        let receipts = fixture.adapter.deliveryReceiptCount
        #expect(
            await fixture.runtime.receiveAssetRequest(
                handle,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        #expect(fixture.adapter.deliveryReceiptCount == receipts)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        // The same process still admits a legitimate frame afterwards.
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : 8
            ),
            sequence: 1
        )
        #expect(begun.result == .begun)
        await fixture.tearDown()
    }

    @Test
    func actuallyOversizedChunkFrameIsRefusedWhileTheLiveTransferSurvives() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : png.count
            ),
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        // A real frame whose encoded size is within the 192 KiB frame cap but whose decoded
        // chunk payload is 65,537 bytes: one byte past the 64 KiB chunk bound. Encoding it
        // through the public initializer is (correctly) impossible, so the JSON is hand-crafted.
        let oversizedBytes = Data(repeating: 0x41, count: AssetTransferFrameCodec.maximumChunkBytes + 1)
        let raw = try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "requestID": UUID().uuidString,
                "operation": "chunk",
                "transferID": transferID.uuidString,
                "offset": 0,
                "bytes": oversizedBytes.base64EncodedString(),
            ],
            options: [.sortedKeys]
        )
        #expect(raw.count <= AssetTransferFrameCodec.maximumEncodedBytes)
        let handle = try #require(
            fixture.adapter.stageAssetIngress(
                raw,
                incarnation: fixture.connection.incarnation,
                sequence   : 2
            )
        )
        #expect(
            await fixture.runtime.receiveAssetRequest(
                handle,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        // The legitimate transfer was never revoked and finishes with the real chunk.
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: transferID,
            offset    : 0,
            bytes     : png
        )
        let ack = try await fixture.exchange(
            chunk,
            sequence: 2
        )
        #expect(ack.result == .acknowledged)
        let imported = try await fixture.exchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .finish,
                transferID: transferID
            ),
            sequence: 3
        )
        #expect(imported.result == .imported)
        await fixture.tearDown()
    }

    @Test
    func admissionIsReleasedBetweenChunksSoUnrelatedWorkCompletes() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : png.count
            ),
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        let ack = try await fixture.exchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: transferID,
                offset    : 0,
                bytes     : png
            ),
            sequence: 2
        )
        #expect(ack.result == .acknowledged)
        // The chunk frame's global admission ended with its reply: an unrelated, authorized
        // publication output completes on the same connection while the transfer is still live.
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: nil
                )
            ],
            sequence: 1
        )
        let imported = try await fixture.exchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .finish,
                transferID: transferID
            ),
            sequence: 3
        )
        #expect(imported.result == .imported)
        await fixture.tearDown()
    }

    @Test
    func suppressedBeginHandoffRollsBackTheNewTransferAndKeepsTheAssemblerUsable() async throws {
        let fixture = try await AssetMessageFixture.make()
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        fixture.adapter.rejectedAssetOperations = [.begin]
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 8
        )
        #expect(
            try await fixture.rawResult(
                begin,
                sequence: 1
            ) == .completed(
                .accepted,
                .rejectedBeforeHandoff
            )
        )
        // Only the newly created transfer was rolled back: its reservation is refunded and the
        // adapter staging is drained.
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == beforeMemory)
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        fixture.adapter.rejectedAssetOperations = []
        let begun = try await fixture.exchange(
            begin,
            sequence: 2
        )
        #expect(begun.result == .begun)
        await fixture.tearDown()
    }

    @Test
    func suppressedImportHandoffReleasesOnlyTheNewAliasAndKeepsIndependentPins() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        // An independent, already published pin that the rollback must not touch.
        let pinned = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: pinned.assetID
                )
            ],
            sequence: 1
        )
        let beforePool = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let beforeBytes = await fixture.governor.usage(.assetBytes)
        let beforeRetained = await fixture.governor.usage(.retainedStateBytes)
        // A second import whose finish reply cannot be handed off.
        fixture.adapter.rejectedAssetOperations = [.finish]
        let begun = try await fixture.rawExchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[1],
                totalBytes   : png.count
            ),
            sequence: 4
        )
        let transferID = try #require(begun.transferID)
        _ = try await fixture.rawExchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: transferID,
                offset    : 0,
                bytes     : png
            ),
            sequence: 5
        )
        #expect(
            try await fixture.rawResult(
                try AssetTransferRequest(
                    requestID : UUID(),
                    operation : .finish,
                    transferID: transferID
                ),
                sequence: 6
            ) == .completed(
                .accepted,
                .rejectedBeforeHandoff
            )
        )
        for _ in 0..<1_000 {
            if await fixture.governor.usage(.assetBytes) == beforeBytes { break }
            await Task.yield()
        }
        // The newly minted alias and its metadata quote are released; the independent pin stays.
        #expect(await fixture.governor.usage(.assetBytes) == beforeBytes)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == beforePool
        )
        #expect(await fixture.governor.usage(.retainedStateBytes) == beforeRetained)
        #expect(
            await fixture.runtime.assetImage(
                assetID            : pinned.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await fixture.tearDown()
    }

    @Test
    func suppressedShareHandoffReleasesOnlyTheNewAliasAndKeepsTheSource() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let source = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        let beforePool = await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes
        let beforeBytes = await fixture.governor.usage(.assetBytes)
        fixture.adapter.rejectedAssetOperations = [.share]
        #expect(
            try await fixture.rawResult(
                try AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .share,
                    publicationID: fixture.ids[1],
                    sourceHandle : source
                ),
                sequence: 4
            ) == .completed(
                .accepted,
                .rejectedBeforeHandoff
            )
        )
        #expect(await fixture.governor.usage(.assetBytes) == beforeBytes)
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes == beforePool
        )
        // The source alias is untouched and still authorizes a real publication pin.
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: source.assetID
                )
            ],
            sequence: 1
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : source.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        await fixture.tearDown()
    }

    // MARK: Foreign identity, connection and transfer tokens

    @Test
    func foreignTransferIDAndForgedConnectionsCannotRevokeTheLiveTransfer() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : png.count
            ),
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        // A foreign transfer ID is refused and must not clear or revoke the live transfer.
        let foreignChunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: UUID(),
            offset    : 0,
            bytes     : Data([1])
        )
        let refusedChunk = try await fixture.exchange(
            foreignChunk,
            sequence: 2
        )
        #expect(refusedChunk.result == .failure)
        // Forged connection copies (foreign token, digest, previous authority revision) are all
        // refused before the shared ingress is taken and never touch the live transfer.
        let forgedConnections = [
            RuntimeConnection(
                token                : UUID(),
                incarnation          : fixture.connection.incarnation,
                identity             : fixture.connection.identity,
                digest               : fixture.connection.digest,
                publicationConnection: fixture.connection.publicationConnection,
                serviceSession       : fixture.connection.serviceSession,
                authorityRevision    : fixture.connection.authorityRevision
            ),
            RuntimeConnection(
                token                : fixture.connection.token,
                incarnation          : fixture.connection.incarnation,
                identity             : fixture.connection.identity,
                digest               : fixture.connection.digest + "-foreign",
                publicationConnection: fixture.connection.publicationConnection,
                serviceSession       : fixture.connection.serviceSession,
                authorityRevision    : fixture.connection.authorityRevision
            ),
            RuntimeConnection(
                token                : fixture.connection.token,
                incarnation          : fixture.connection.incarnation,
                identity             : fixture.connection.identity,
                digest               : fixture.connection.digest,
                publicationConnection: fixture.connection.publicationConnection,
                serviceSession       : fixture.connection.serviceSession,
                authorityRevision    : fixture.connection.authorityRevision &+ 1
            ),
        ]
        for forged in forgedConnections {
            let raw = try AssetTransferFrameCodec.encode(
                try AssetTransferRequest(
                    requestID : UUID(),
                    operation : .chunk,
                    transferID: transferID,
                    offset    : 0,
                    bytes     : Data([1])
                ),
                profile: .v1
            )
            let handle = try #require(
                fixture.adapter.stageAssetIngress(
                    raw,
                    incarnation: fixture.connection.incarnation,
                    sequence   : 3
                )
            )
            let attempts = fixture.adapter.ingressTakeAttempts
            #expect(
                await fixture.runtime.receiveAssetRequest(
                    handle,
                    connection: forged
                ) == .refused(.sessionRevoked)
            )
            #expect(fixture.adapter.ingressTakeAttempts == attempts)
        }
        // The legitimate transfer still completes with the real chunk and finish.
        let ack = try await fixture.exchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: transferID,
                offset    : 0,
                bytes     : png
            ),
            sequence: 3
        )
        #expect(ack.result == .acknowledged)
        let imported = try await fixture.exchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .finish,
                transferID: transferID
            ),
            sequence: 4
        )
        #expect(imported.result == .imported)
        await fixture.tearDown()
    }

    @Test
    func crossPrivateSharingIsRefusedAndPreservesTheSourceAlias() async throws {
        let fixture = try await AssetMessageFixture.make(mixedPrivacy: true)
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let imported = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        // The target assignment has a different host privacy partition, so the canonical
        // sharing check refuses the alias while leaving the source alias intact.
        let share = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .share,
            publicationID: fixture.ids[1],
            sourceHandle : imported
        )
        let refused = try await fixture.exchange(
            share,
            sequence: 4
        )
        #expect(refused.result == .failure)
        #expect(refused.failureCode == .permissionDenied)
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: imported.assetID
                )
            ],
            sequence: 1
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        let released = try await fixture.exchange(
            try AssetTransferRequest(
                requestID   : UUID(),
                operation   : .release,
                sourceHandle: imported
            ),
            sequence: 5
        )
        #expect(released.result == .acknowledged)
        await fixture.tearDown()
    }

    // MARK: Publication lifetime versus the process assembler

    @Test
    func endingOnePublicationMustNotDisableTheLiveProcessAssetCapability() async throws {
        let fixture = try await AssetMessageFixture.make()
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: nil
                )
            ],
            sequence: 1
        )
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : 8
            ),
            sequence: 1
        )
        #expect(begun.result == .begun)
        // Ending the exact bound publication revokes only that transfer.
        _ = try await fixture.publish(
            [],
            sequence: 2,
            ends    : [fixture.ids[0]]
        )
        // Ending a publication revokes only the exact bound transfer. The process stays
        // connected and the other assignment is still authorized, so a later legitimate import
        // MUST still be admitted on the same per-process assembler instead of being permanently
        // disabled by a terminal close.
        let later = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[1],
                totalBytes   : 8
            ),
            sequence: 2
        )
        #expect(later.result == .begun)
        await fixture.tearDown()
    }

    @Test
    func expiringOnePublicationMustNotDisableTheLiveProcessAssetCapability() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        // The first assignment expires well before the nonrenewable 30-second transfer deadline.
        let expiry = try Publication(
            id         : fixture.ids[0],
            revision   : 1,
            kind       : .widget,
            content    : fixture.content(nil),
            timeline   : nil,
            expiresAt  : fixture.wall.addingTimeInterval(5),
            stalePolicy: .remove
        )
        _ = try await fixture.publish(
            [expiry],
            sequence: 1
        )
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : png.count
            ),
            sequence: 1
        )
        #expect(begun.result == .begun)
        // Expiry is serviced through the shared deadline event and must revoke only the exact
        // transfer, not close the assembler of the still-connected live process.
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(10),
                monotonic: .seconds(10)
            )
        )
        _ = try await fixture.runtime.serviceDeadlines()
        // The second authorized assignment completes a full import on the SAME process
        // assembler, proving the sole reservation token was refunded and the assembler reused.
        let imported = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[1],
            sequences    : (2, 3, 4)
        )
        #expect(imported.publicationID == fixture.ids[1])
        #expect(imported.width == 32)
        await fixture.tearDown()
    }

    @Test
    func deferredRefundFailureKeepsTheSoleTokenAndReconcilesBeforeReuse() async throws {
        let fixture = try await AssetMessageFixture.make()
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: nil
                )
            ],
            sequence: 1
        )
        let totalBytes = 1_048_576
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        let begin = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : totalBytes
        )
        let begun = try await fixture.exchange(
            begin,
            sequence: 1
        )
        #expect(begun.result == .begun)
        let charged = beforeMemory + 2 * totalBytes + 4_096
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        // One real protected-refund failure is injected before the bound publication ends, so the
        // exact nonterminal revocation leaves the sole reservation token retained and observable.
        await fixture.governor.armAssetTransferRefundFailureForTesting()
        _ = try await fixture.publish(
            [],
            sequence: 2,
            ends    : [fixture.ids[0]]
        )
        #expect(await fixture.governor.usage(.admittedMemoryBytes) == charged)
        // The next admission drains the retained exact token before admitting new work; the refund
        // then releases it once and the same live assembler commits a later authorized import.
        let png = try randomPNG(
            width : 8,
            height: 8
        )
        let imported = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[1],
            sequences    : (2, 3, 4)
        )
        #expect(imported.publicationID == fixture.ids[1])
        await fixture.tearDown()
    }

    @Test(arguments: [false, true])
    func suspendedFinishNeverCommitsAnAliasWhenProviderIsDisabledOrStopped(_ disable: Bool) async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 64,
            height: 64
        )
        // The publication expires five seconds after the begin, well before the 30-second
        // transfer deadline, so the race is specifically a publication-lifetime revocation.
        _ = try await fixture.publish(
            [
                try Publication(
                    id         : fixture.ids[0],
                    revision   : 1,
                    kind       : .widget,
                    content    : fixture.content(nil),
                    timeline   : nil,
                    expiresAt  : fixture.wall.addingTimeInterval(5),
                    stalePolicy: .remove
                )
            ],
            sequence: 1
        )
        let begun = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : png.count
            ),
            sequence: 1
        )
        let transferID = try #require(begun.transferID)
        let chunked = try await fixture.exchange(
            try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: transferID,
                offset    : 0,
                bytes     : png
            ),
            sequence: 2
        )
        #expect(chunked.result == .acknowledged)
        let beforeBytes = await fixture.governor.usage(.assetBytes)
        let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes)
        // Park the real finish inside growPool, which forwards the actual governor resize once.
        await fixture.access.armResize()
        let handle = try #require(
            fixture.adapter.stageAssetIngress(
                try AssetTransferFrameCodec.encode(
                    try AssetTransferRequest(
                        requestID : UUID(),
                        operation : .finish,
                        transferID: transferID
                    ),
                    profile: .v1
                ),
                incarnation: fixture.connection.incarnation,
                sequence   : 3
            )
        )
        let finish = Task {
            await fixture.runtime.receiveAssetRequest(
                handle,
                connection: fixture.connection
            )
        }
        await fixture.access.waitForArrival()
        // The provider is disabled (or the whole runtime is stopped) while the exact finish is
        // suspended after its metadata quote and before any decode or synchronous alias insert.
        // This is metadata-admission evidence only. The separate lifecycle suite holds real
        // transfer admission/native execution; serviceDeadlines expires canonical publications
        // before its later scheduling admission can report busy.
        if disable {
            await fixture.runtime.disable(owner: fixture.owner)
        } else {
            _ = await fixture.runtime.requestStop()
        }
        await fixture.access.releaseGate()
        let result = await finish.value
        if case .completed(.failure, _) = result {
            // Expected: the protected finish observes revoked authority and suppresses the alias.
        } else if case .refused = result {
            // Also acceptable: authority was revoked before the ingress could be accepted.
        } else {
            Issue.record("Expected a bounded finish failure, got \(result)")
        }
        // No alias was committed, the exact assembler charge is refunded and the adapter staging
        // is drained on every outcome.
        #expect(await fixture.governor.usage(.assetBytes) == beforeBytes)
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) < beforeMemory)
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
        await fixture.tearDown()
    }

    // MARK: Real publication pins, borrowed image and final disposal

    @Test
    func messageImportKeepsPinsAndABorrowedImageUntilRealDisposal() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let imported = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: imported.assetID
                )
            ],
            sequence: 1
        )
        let shared = try await fixture.exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .share,
                publicationID: fixture.ids[1],
                sourceHandle : imported
            ),
            sequence: 4
        )
        let sharedHandle = try #require(shared.assetHandle)
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[1],
                    asset: sharedHandle.assetID
                )
            ],
            sequence: 2
        )
        var borrowed: CGImage? = await fixture.runtime.assetImage(
            assetID            : imported.assetID,
            publicationID      : fixture.ids[0],
            publicationRevision: 1
        )
        #expect(borrowed?.width == 32)
        let chargedBytes = await fixture.governor.usage(.assetBytes)
        #expect(chargedBytes > 0)
        // Releasing both import aliases leaves the independent publication pins and the
        // borrowed actual CGImage owning the raster bytes.
        _ = try await fixture.exchange(
            try AssetTransferRequest(
                requestID   : UUID(),
                operation   : .release,
                sourceHandle: sharedHandle
            ),
            sequence: 5
        )
        _ = try await fixture.exchange(
            try AssetTransferRequest(
                requestID   : UUID(),
                operation   : .release,
                sourceHandle: imported
            ),
            sequence: 6
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : sharedHandle.assetID,
                publicationID      : fixture.ids[1],
                publicationRevision: 1
            )?.width == 32
        )
        #expect(await fixture.governor.usage(.assetBytes) == chargedBytes)
        // Provider revocation removes connection aliases but keeps published content alive.
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        #expect(borrowed?.height == 32)
        // Final real disposal: the expired publication pins release the lookup, but the raster
        // bytes stay charged until the borrowed CGImage is dropped.
        fixture.clock.set(
            RuntimeInstant(
                wall     : fixture.wall.addingTimeInterval(61),
                monotonic: .seconds(61)
            )
        )
        _ = try await fixture.runtime.serviceDeadlines()
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            ) == nil
        )
        #expect(borrowed?.width == 32)
        #expect(await fixture.governor.usage(.assetBytes) == chargedBytes)
        borrowed = nil
        // A time deadline, not a yield count: under the full parallel run a
        // thousand yields can elapse before the release reaches the governor.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await fixture.governor.usage(.assetBytes) != 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        await fixture.tearDown()
    }

    @Test
    func bridgeClosePreservesDurablePublicationsAndActualAssetPins() async throws {
        let fixture = try await AssetMessageFixture.make()
        let png = try randomPNG(
            width : 32,
            height: 32
        )
        let imported = try await fixture.importAlias(
            png,
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        _ = try await fixture.publish(
            [
                fixture.publication(
                    id   : fixture.ids[0],
                    asset: imported.assetID
                )
            ],
            sequence: 1
        )
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        let assetBytes = await fixture.governor.usage(.assetBytes)
        #expect(assetBytes > 0)
        // Closing import authority must retain the durable publication and its physical raster.
        await fixture.channel.close()
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.count == 1)
        #expect(await fixture.governor.usage(.publications) == 1)
        #expect(await fixture.governor.usage(.assetBytes) == assetBytes)
        #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == 1)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.runtime.releaseAsset(
                assetID      : imported.assetID,
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
        }
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == 0)
        #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.count == 1)
        #expect(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )?.width == 32
        )
        #expect(await fixture.governor.usage(.assetBytes) == assetBytes)
        await fixture.tearDown()
    }

    @Test(arguments: ["token", "incarnation", "identity", "digest", "revision"])
    func forgedCloseCannotRevokeTheCanonicalConnection(field: String) async throws {
        let fixture = try await AssetMessageFixture.make()
        let current = fixture.connection
        let foreignIdentity = try installedFixture("consumer").verifiedIdentity
        let forged = RuntimeConnection(
            token                : field == "token" ? UUID() : current.token,
            incarnation          : field == "incarnation" ? RuntimeIncarnation() : current.incarnation,
            identity             : field == "identity" ? foreignIdentity : current.identity,
            digest               : field == "digest" ? "foreign-digest" : current.digest,
            publicationConnection: current.publicationConnection,
            serviceSession       : current.serviceSession,
            authorityRevision    : field == "revision" ? current.authorityRevision + 1 : current.authorityRevision
        )
        await fixture.runtime.closeConnection(forged)
        #expect(fixture.adapter.stopCount(incarnation: current.incarnation) == 0)
        let reply = try await fixture.exchange(
            AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : 4
            ),
            sequence: 1
        )
        #expect(reply.result == .begun)
        await fixture.tearDown()
    }

    @Test
    func staleBridgeCloseCannotStopOrRevokeReplacementTraffic() async throws {
        let fixture = try await AssetMessageFixture.make()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        let launch = try await fixture.runtime.requestLaunch(owner: fixture.owner)
        let replacement = try await fixture.runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 2,
                contentSchemas: [1]
            )
        )
        let channel = RuntimeAssetChannelBridge(
            runtime   : fixture.runtime,
            adapter   : fixture.adapter,
            connection: replacement
        )
        let request = try AssetTransferRequest(
            requestID    : UUID(),
            operation    : .begin,
            publicationID: fixture.ids[0],
            totalBytes   : 4
        )
        let ingress = try #require(fixture.adapter.stageAssetIngress(
            AssetTransferFrameCodec.encode(
                request,
                profile: .v1
            ),
            incarnation: replacement.incarnation,
            sequence   : 1
        ))
        #expect(await fixture.runtime.receiveAssetRequest(
            ingress,
            connection: replacement
        ) == .completed(.accepted, .handedOff))
        guard case .assetResponse(let delivery)? = fixture.adapter.currentDelivery(
            incarnation: replacement.incarnation
        ) else {
            await fixture.runtime.observeExit(replacement.incarnation)
            await fixture.tearDown()
            Issue.record("Expected the replacement's real asset reply.")
            return
        }
        // Close the old bridge while the replacement physically owns a reply and assembly.
        await fixture.channel.close()
        await fixture.runtime.closeConnection(fixture.connection)
        #expect(fixture.adapter.stopCount(incarnation: replacement.incarnation) == 0)
        #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == 1)
        #expect(fixture.adapter.currentDelivery(incarnation: replacement.incarnation) == .assetResponse(delivery))
        #expect(await fixture.runtime.receiveAssetReceipt(
            delivery.receipt,
            connection: replacement
        ))
        let response = try AssetTransferFrameCodec.decodeResponse(
            delivery.payload,
            profile: .v1
        )
        #expect(response.result == .begun)
        let chunk = try AssetTransferRequest(
            requestID : UUID(),
            operation : .chunk,
            transferID: #require(response.transferID),
            offset    : 0,
            bytes     : Data([1, 2, 3, 4])
        )
        let continued = try AssetTransferFrameCodec.decodeResponse(
            await channel.exchange(
                AssetTransferFrameCodec.encode(
                    chunk,
                    profile: .v1
                ),
                sequence: 2
            ),
            profile: .v1
        )
        #expect(continued.result == .acknowledged)
        await channel.close()
        await fixture.runtime.observeExit(replacement.incarnation)
        await fixture.tearDown()
    }

    @Test
    func connectionCloseDisposesUnpinnedImportsWithoutWaitingForProcessExit() async throws {
        let fixture = try await AssetMessageFixture.make()
        _ = try await fixture.importAlias(
            randomPNG(
                width : 32,
                height: 32
            ),
            publicationID: fixture.ids[0],
            sequences    : (1, 2, 3)
        )
        #expect(await fixture.governor.usage(.assetBytes) > 0)
        let beforePool = try #require(await fixture.runtime.diagnostics(owner: fixture.owner)).reservedStateBytes
        await fixture.channel.close()
        // Raster disposal refunds asynchronously after the last actual reference is dropped.
        for _ in 0..<1_000 {
            if await fixture.governor.usage(.assetBytes) == 0 { break }
            await Task.yield()
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.reservedStateBytes ?? Int.max < beforePool)
        #expect(await fixture.runtime.diagnostics(owner: fixture.owner)?.hasProcess == true)
        #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == 1)
        await fixture.tearDown()
    }

    @Test
    func closeAfterServiceInducedStopDisposesImportsAndSessionsWithoutExit() async throws {
        let fixture = try await AddonRuntimeSlotOwnershipTests.ServiceFixture()
        let owner = fixture.provider.manifest.id
        let current = fixture.providerConnection
        _ = try await fixture.runtime.importAsset(
            encoded      : randomPNG(width: 32, height: 32),
            publicationID: fixture.publicationID,
            connection   : current
        )
        let acquisition = try await fixture.acquire()
        #expect(try await fixture.runtime.receiveSourceStartupCompletion(
            acquisition.sourceID,
            connection: current
        ))
        let work = try await fixture.runtime.beginServiceInvocation(
            connection: fixture.consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: fixture.invocation()
        )
        #expect(try await fixture.runtime.pumpServiceInvocation(work.id))
        // Revoking the consumer's grant invokes real broker reconciliation, which requests
        // provider stop while retaining its canonical connection and uncertain physical job.
        await fixture.runtime.closeConnection(fixture.consumerConnection)
        #expect(fixture.adapter.stopCount(incarnation: current.incarnation) == 1)
        #expect(await fixture.governor.usage(.assetBytes) > 0)
        let beforePool = try #require(await fixture.runtime.diagnostics(owner: owner)).reservedStateBytes
        let beforeState = await fixture.governor.usage(.retainedStateBytes, owner: owner)
        let stale = RuntimeConnection(
            token                : UUID(),
            incarnation          : current.incarnation,
            identity             : current.identity,
            digest               : current.digest,
            publicationConnection: current.publicationConnection,
            serviceSession       : current.serviceSession,
            authorityRevision    : current.authorityRevision
        )
        await fixture.runtime.closeConnection(stale)
        #expect(await fixture.governor.usage(.retainedStateBytes, owner: owner) == beforeState)
        // Foreign component handles must be ignored even for an already-stopping process.
        let supplied = RuntimeConnection(
            token                : current.token,
            incarnation          : current.incarnation,
            identity             : current.identity,
            digest               : current.digest,
            publicationConnection: fixture.consumerConnection.publicationConnection,
            serviceSession       : fixture.consumerConnection.serviceSession,
            authorityRevision    : current.authorityRevision
        )
        let channel = RuntimeAssetChannelBridge(
            runtime   : fixture.runtime,
            adapter   : fixture.adapter,
            connection: supplied
        )
        await channel.close()
        for _ in 0..<1_000 {
            if await fixture.governor.usage(.assetBytes) == 0 { break }
            await Task.yield()
        }
        #expect(await fixture.governor.usage(.assetBytes) == 0)
        let afterPool = try #require(await fixture.runtime.diagnostics(owner: owner)).reservedStateBytes
        let afterState = await fixture.governor.usage(.retainedStateBytes, owner: owner)
        #expect(afterPool < beforePool)
        // The broker session has a separate governor reservation outside the owner's runtime
        // pool. Both that session and the pool's publication session/import metadata must go.
        #expect(beforeState - afterState > beforePool - afterPool)
        await fixture.runtime.closeConnection(current)
        #expect(await fixture.governor.usage(.retainedStateBytes, owner: owner) == afterState)
        #expect(fixture.adapter.stopCount(incarnation: current.incarnation) == 1)
        #expect(await fixture.governor.usage(.providers) == 2)
        #expect(await fixture.governor.usage(.jobs, owner: owner) == 1)
        #expect(await fixture.governor.usage(.commands, owner: fixture.consumer.manifest.id) == 1)
        #expect(await fixture.runtime.diagnostics(owner: owner)?.hasProcess == true)
        #expect(await fixture.runtime.snapshot(at: fixture.action.wall).publications.count == 1)
        await fixture.runtime.observeExit(current.incarnation)
        #expect(await fixture.governor.usage(.jobs, owner: owner) == 0)
        #expect(await fixture.governor.usage(.commands, owner: fixture.consumer.manifest.id) == 0)
        #expect(await fixture.governor.usage(.providers) == 1)
        await fixture.stop()
    }
}

/// RuntimeAssetChannelBridge is a test-only `AddonAssetMessageChannel` over the real runtime.
///
/// It owns exactly one bounded physical exchange slot. Each exchange stages one raw frame in the
/// adapter's typed ingress slot, invokes the real host receive path, correlates the exact host
/// reply receipt against its own connection and sequence, consumes that receipt, and only then
/// hands the bounded reply `Data` to the caller. A duplicate or regressing sequence, an
/// out-of-bound frame and a second concurrent exchange are refused before any new staging, so the
/// bridge never retains an open-ended queue or per-frame history.
///
/// `close` revokes the exact authenticated connection through the runtime's existing lifecycle
/// path and then awaits the in-flight exchange; it never fabricates an observed native process
/// exit. Repeated and concurrent close callers all await that one drain rather than a closed flag.
///
/// The bridge is deliberately test-only: it authenticates nothing and implements no OS transport.
/// Its hold and fault points exist only so the tests can drive a physically in-flight exchange
/// deterministically, without sleeps or polling.
private final class RuntimeAssetChannelBridge: AddonAssetMessageChannel, @unchecked Sendable {
    /// ExchangeHoldPoint names the one deterministic suspension a test can arm.
    enum ExchangeHoldPoint: Sendable {
        case beforeReceive
        case afterHandoff
    }

    /// Fault injects one bounded physical reply fault after the host has handed off its reply.
    enum Fault: Sendable {
        case mismatchedReceipt
        case transportError
    }

    let generation: ConnectionGeneration
    let profile   : AssetTransferFrameProfile?

    private let runtime      : AddonRuntime
    private let adapter      : RecordingRuntimeAdapter
    private let connection   : RuntimeConnection
    private let stateLock    = NSLock()
    private let exchangeGate = BridgeExchangeGate()
    private var lastSequence : UInt64 = 0
    private var inFlight     : Task<Data, any Error>?
    private var closeTask    : Task<Void, Never>?
    private var isRevoked    = false
    private var holdPoint    : ExchangeHoldPoint?
    private var armedFault   : Fault?

    private var drainedInFlightExchange = false

    init(
        runtime   : AddonRuntime,
        adapter   : RecordingRuntimeAdapter,
        connection: RuntimeConnection
    ) {
        self.runtime = runtime
        self.adapter = adapter
        self.connection = connection
        self.generation = connection.publicationConnection.generation
        self.profile = connection.publicationConnection.negotiatedProtocol.assetFrameProfile
    }

    // MARK: Test-only deterministic points

    /// didDrainInFlightExchange is true once close has awaited a real in-flight exchange.
    var didDrainInFlightExchange: Bool { stateLock.withLock { drainedInFlightExchange } }

    /// armHold suspends exactly the next exchange at one deterministic physical point.
    func armHold(at point: ExchangeHoldPoint) async {
        stateLock.withLock { holdPoint = point }
        await exchangeGate.arm()
    }

    /// waitForHoldArrival blocks until the armed exchange has reached its held point.
    func waitForHoldArrival() async {
        await exchangeGate.waitForArrival()
    }

    /// armFault injects exactly one bounded physical fault on the next handed-off reply.
    func armFault(_ fault: Fault) {
        stateLock.withLock { armedFault = fault }
    }

    // MARK: AddonAssetMessageChannel

    func exchange(_ frame: Data, sequence: UInt64) async throws -> Data {
        let work = try claimExchangeSlot(frame, sequence: sequence)
        let reply: Data
        do {
            reply = try await work.value
        } catch {
            releaseExchangeSlot()
            throw error
        }
        releaseExchangeSlot()
        return reply
    }

    func close() async {
        let work: Task<Void, Never> = stateLock.withLock {
            if let existing = closeTask { return existing }
            isRevoked = true
            let created = Task { await self.performClose() }
            closeTask = created
            return created
        }
        await work.value
    }

    // MARK: Bounded physical exchange slot

    /// claimExchangeSlot takes the single bounded slot synchronously before any await.
    private func claimExchangeSlot(
        _ frame   : Data,
        sequence  : UInt64
    ) throws -> Task<Data, any Error> {
        try stateLock.withLock {
            guard !isRevoked else {
                throw AddonFailure(
                    code  : .sessionRevoked,
                    reason: "The bridge connection is revoked."
                )
            }
            guard inFlight == nil else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The bridge carries one physical exchange at a time."
                )
            }
            guard sequence > lastSequence else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "The bridge requires a strictly increasing physical sequence."
                )
            }
            guard frame.count > 0, frame.count <= AssetTransferFrameCodec.maximumEncodedBytes else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "The bridge refuses an out-of-bound encoded frame."
                )
            }
            lastSequence = sequence
            let created = Task { try await self.performExchange(frame, sequence: sequence) }
            inFlight = created
            return created
        }
    }

    private func releaseExchangeSlot() {
        stateLock.withLock { inFlight = nil }
    }

    /// performExchange stages, sends, correlates and consumes exactly one real host reply.
    private func performExchange(
        _ frame   : Data,
        sequence  : UInt64
    ) async throws -> Data {
        let holdPoint = stateLock.withLock { self.holdPoint }
        guard
            let handle = adapter.stageAssetIngress(
                frame,
                incarnation: connection.incarnation,
                sequence   : sequence
            )
        else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The bridge could not stage the bounded asset frame."
            )
        }
        var ingressTaken = false
        defer {
            if !ingressTaken {
                adapter.rejectAssetIngress(
                    handle,
                    incarnation: connection.incarnation
                )
            }
        }
        if holdPoint == .beforeReceive {
            await exchangeGate.arrivalPoint()
            try checkRevoked()
        }
        let result = await runtime.receiveAssetRequest(
            handle,
            connection: connection
        )
        // The runtime always disposes its ingress claim before this call returns.
        ingressTaken = true
        switch result {
        case .refused(let code):
            throw AddonFailure(
                code  : code,
                reason: "The host refused the asset frame."
            )
        case .completed(_, let disposition):
            guard disposition == .handedOff else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The host did not hand off an asset reply."
                )
            }
        }
        guard
            case .assetResponse(let delivery)? = adapter.currentDelivery(
                incarnation: connection.incarnation
            )
        else {
            throw AddonFailure(
                code  : .dependencyUnavailable,
                reason: "The bridge did not observe an asset reply."
            )
        }
        var receiptConsumed = false
        defer {
            if !receiptConsumed {
                // Drop only this incarnation's raw reply staging; the exact connection is
                // revoked before it can carry another frame, so the stale work credit is inert.
                adapter.deliveryWasReceived(incarnation: connection.incarnation)
            }
        }
        if holdPoint == .afterHandoff {
            await exchangeGate.arrivalPoint()
            try checkRevoked()
        }
        let receipt = try correlatedReceipt(delivery: delivery, sequence: sequence)
        guard await runtime.receiveAssetReceipt(
            receipt,
            connection: connection
        ) else {
            refuseReuseAfterFault()
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The bridge could not consume the exact asset receipt."
            )
        }
        receiptConsumed = true
        return delivery.payload
    }

    /// correlatedReceipt applies the one armed test-only fault and then verifies the physical
    /// correlation the bridge itself staged. The receipt never leaves the bridge.
    private func correlatedReceipt(
        delivery: RuntimeAssetResponseDelivery,
        sequence: UInt64
    ) throws -> RuntimeAssetReceipt {
        let fault = stateLock.withLock { () -> Fault? in
            let armed = armedFault
            armedFault = nil
            return armed
        }
        let receipt: RuntimeAssetReceipt
        switch fault {
        case .mismatchedReceipt:
            receipt = RuntimeAssetReceipt(
                token          : delivery.receipt.token,
                incarnation    : delivery.receipt.incarnation,
                connectionToken: delivery.receipt.connectionToken,
                sequence       : delivery.receipt.sequence &+ 1,
                requestID      : delivery.receipt.requestID,
                operation      : delivery.receipt.operation
            )
        case .transportError:
            refuseReuseAfterFault()
            throw AddonFailure(
                code  : .dependencyUnavailable,
                reason: "The bridge observed a physical transport error after handoff."
            )
        case .none:
            receipt = delivery.receipt
        }
        guard
            receipt.incarnation == connection.incarnation,
            receipt.connectionToken == connection.token,
            receipt.sequence == sequence
        else {
            refuseReuseAfterFault()
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The bridge observed a mismatched physical reply receipt."
            )
        }
        return receipt
    }

    /// checkRevoked revalidates the scalar closure after any suspension before send or consume.
    private func checkRevoked() throws {
        guard !stateLock.withLock({ isRevoked }) else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The bridge connection is revoked."
            )
        }
    }

    /// refuseReuseAfterFault stops new frames after an uncertain physical reply without waiting.
    private func refuseReuseAfterFault() {
        stateLock.withLock { isRevoked = true }
    }

    // MARK: Close and drain

    /// performClose revokes the exact authenticated connection and drains the in-flight exchange.
    ///
    /// The runtime validates and revokes the exact connection before disposing staging. The
    /// held exchange is then released explicitly and awaited to completion before close returns.
    private func performClose() async {
        await runtime.closeConnection(connection)
        await exchangeGate.release()
        guard let inFlightWork = stateLock.withLock({ inFlight }) else { return }
        _ = try? await inFlightWork.value
        stateLock.withLock { drainedInFlightExchange = true }
    }
}

/// BridgeExchangeGate suspends exactly one staged bridge exchange at a deterministic point.
///
/// It holds one optional continuation pair, no queue and no history. `close` releases the held
/// exchange before awaiting it, so a genuine close never depends on a sleep, a poll or an
/// external timer. The flags make arming and release order-independent.
private actor BridgeExchangeGate {
    private var isArmed    = false
    private var hasArrived = false
    private var isReleased = false
    private var arrival    : CheckedContinuation<Void, Never>?
    private var completion : CheckedContinuation<Void, Never>?

    func arm() {
        isArmed = true
        hasArrived = false
        isReleased = false
    }

    func arrivalPoint() async {
        guard isArmed else { return }
        isArmed = false
        hasArrived = true
        arrival?.resume()
        arrival = nil
        if isReleased { return }
        await withCheckedContinuation { completion = $0 }
    }

    func waitForArrival() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        isReleased = true
        completion?.resume()
        completion = nil
    }
}

/// AssetMessageFixture assembles the real host mechanisms behind the deterministic bridge.
private struct AssetMessageFixture: Sendable {
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

    /// mixedPrivacy gives the second host assignment an isolated asset privacy partition so a
    /// cross-private sharing refusal can be exercised against the real canonical scope check.
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

/// randomPNG encodes an incompressible image so the compressed payload spans several 64 KiB chunks.
private func randomPNG(width: Int, height: Int) throws -> Data {
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var bytes = [UInt8](
        repeating: 0,
        count: width * height * 4
    )
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    for index in bytes.indices {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        bytes[index] = UInt8(truncatingIfNeeded: state >> 33)
    }
    let provider = try #require(
        CGDataProvider(data: Data(bytes) as CFData)
    )
    let image = try #require(
        CGImage(
            width             : width,
            height            : height,
            bitsPerComponent  : 8,
            bitsPerPixel      : 32,
            bytesPerRow       : width * 4,
            space             : colorSpace,
            bitmapInfo        : CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider          : provider,
            decode            : nil,
            shouldInterpolate : false,
            intent            : .defaultIntent
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
