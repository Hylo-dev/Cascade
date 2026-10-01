//
//  AddonRuntimeAssetLifecycleTests.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

#if DEBUG
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AddonRuntimeAssetLifecycleTests {

    enum Event: String, CaseIterable, Sendable {

        case stop
        case exit
        case disable
        case end
        case expiry
        case close
        case closeStopping
        case closeQuiescing

        var isClose: Bool { self == .close || self == .closeStopping || self == .closeQuiescing }

        var isNonterminal: Bool { self == .end || self == .expiry }
    }

    struct Race: Sendable, CustomStringConvertible {

        let point: AssetLifecycleObserver.Point
        let event: Event
        let fault: Bool

        var description: String { "\(point.rawValue)/\(event.rawValue)/refundFault=\(fault)" }

        static var all: [Self] {
            [AssetLifecycleObserver.Point.admission, .native].flatMap { point in
                Event.allCases.flatMap { event in
                    [false, true].map { Self(point: point, event: event, fault: $0) }
                }
            }
        }
    }

    /// realWorkLifecycleMatrix covers charged admission and an actual ImageIO/CGContext frame,
    /// not metadata resizing. Fault cases retain the same token through explicit bounded drains.
    @Test(arguments: Race.all)
    func realWorkLifecycleMatrix(_ race: Race) async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            // The control pin and unrelated unpinned import expose logical close disposal
            // independently of protected in-flight native work and physical provider charges.
            let control = try await fixture.runtime.importAsset(
                encoded      : lifecyclePNG(width: 1, height: 1),
                publicationID: fixture.ids[1],
                connection   : fixture.connection
            )
            _ = try await fixture.runtime.importAsset(
                encoded      : lifecyclePNG(width: 1, height: 1),
                publicationID: fixture.ids[0],
                connection   : fixture.connection
            )
            _ = try await fixture.publish(
                [
                    Publication(
                        id         : fixture.ids[0],
                        revision   : 1,
                        kind       : .widget,
                        content    : fixture.content(nil),
                        timeline   : nil,
                        expiresAt  : fixture.wall.addingTimeInterval(5),
                        stalePolicy: .remove
                    ),
                    fixture.publication(id: fixture.ids[1], asset: control.assetID)
                ],
                sequence: 1
            )
            if race.event == .closeStopping {
                _ = try await fixture.prepareAcknowledgedAction(controlAsset: control.assetID)
            }

            let binding = try await fixture.binding()
            let png     = try lifecyclePNG(width: 8, height: 8)
            var transferID: UUID?
            var sequence: UInt64 = 1
            if race.point == .native {
                let begun = try await fixture.exchange(
                    AssetTransferRequest(
                        requestID    : UUID(),
                        operation    : .begin,
                        publicationID: fixture.ids[0],
                        totalBytes   : png.count
                    ),
                    sequence: 1
                )
                transferID = try #require(begun.transferID) as UUID
                sequence   = try await fixture.receiveAllChunks(
                    png,
                    transferID: #require(transferID),
                    startingAt: 2
                )
            }

            let request = try race.point == .admission
                ? AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: fixture.ids[0],
                    totalBytes   : png.count
                )
                : AssetTransferRequest(
                    requestID : UUID(),
                    operation : .finish,
                    transferID: transferID
                )
            let observer     = AssetLifecycleObserver(governor: fixture.governor, point: race.point)
            let beforeMemory = await fixture.governor.usage(.admittedMemoryBytes, owner: fixture.owner)
            let before       = await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner)
            var reservationID: UUID?
            var attemptsAtHold : UInt64 = 0
            var successesAtHold: UInt64 = 0
            let result = try await fixture.withHeldRequest(
                request,
                sequence: sequence,
                observer: observer
            ) {
                let held = await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner)
                reservationID = observer.snapshot().reservationID ?? held.assembler?.reservationID
                let id     = try #require(reservationID)
                let charge = await fixture.governor.assetTransferRefundSnapshotForTesting(id)
                attemptsAtHold  = charge.attempts
                successesAtHold = charge.successes
                #expect(charge.present)
                #expect(charge.memoryBytes == 2 * png.count + 4_096)
                #expect(held.activeAdmission)
                #expect(held.transferBinding == binding)
                #expect(held.assembler?.identity == before.assembler?.identity)
                let expectedAdditional = race.point == .admission
                    ? 8 * 1_024 * 1_024 + 2 * png.count + 4_096
                    : 8 * 1_024 * 1_024 + 2 * 1_024 * 1_024 + 8_000_000 + 65_536
                #expect(
                    await fixture.governor.usage(
                        .admittedMemoryBytes,
                        owner: fixture.owner
                    ) == beforeMemory + expectedAdditional
                )
                if race.point == .admission {
                    #expect(held.assembler?.phase == "admitting")
                    #expect(held.assembler?.bufferBytes == 0)
                    #expect(observer.snapshot().decodeEntries == 0)
                } else {
                    #expect(held.assembler?.phase == "decoding")
                    #expect(held.assembler?.bufferBytes == png.count)
                    #expect(observer.snapshot().decodeEntries == 1)
                    #expect(observer.snapshot().decodeReservations == 1)
                    #expect(observer.snapshot().nativeDraws == 1)
                    #expect(observer.snapshot().nativeReturns == 0)
                }

                if race.fault { await fixture.governor.armAssetTransferRefundFailureForTesting(count: 20) }
                switch race.event {
                    case .stop: _ = await fixture.runtime.requestStop()

                    case .exit: await fixture.runtime.observeExit(fixture.connection.incarnation)

                    case .disable: await fixture.runtime.disable(owner: fixture.owner)

                    case .end: #expect(try await fixture.runtime.endAssetPublicationForTesting(binding))

                    case .expiry:
                        fixture.clock.set(
                            RuntimeInstant(wall: fixture.wall.addingTimeInterval(5), monotonic: .seconds(5))
                        )
                        try await fixture.serviceBusyDeadline()

                    case .close, .closeStopping, .closeQuiescing:
                        if race.event == .closeStopping {
                            fixture.clock.set(
                                RuntimeInstant(
                                    wall     : fixture.wall.addingTimeInterval(3),
                                    monotonic: .seconds(3)
                                )
                            )
                            try await fixture.serviceBusyDeadline()
                            #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 1)
                        } else if race.event == .closeQuiescing {
                            _ = try await fixture.runtime.beginArchiveQuiescence(until: .seconds(30))
                        }

                        let current = fixture.connection
                        let forged  = RuntimeConnection(
                            token                : UUID(),
                            incarnation          : current.incarnation,
                            identity             : current.identity,
                            digest               : current.digest,
                            publicationConnection: current.publicationConnection,
                            serviceSession       : current.serviceSession,
                            authorityRevision    : current.authorityRevision
                        )
                        await fixture.runtime.closeConnection(forged)
                        #expect(
                            await fixture.runtime.assetLifecycleSnapshotForTesting(
                                owner: fixture.owner
                            ).connectionClosed == false
                        )
                        await fixture.runtime.closeConnection(current)
                        await fixture.runtime.closeConnection(current)
                        #expect(
                            await fixture.runtime.assetLifecycleSnapshotForTesting(
                                owner: fixture.owner
                            ).sessionBytes == 0
                        )
                        #expect(fixture.adapter.stopCount(incarnation: current.incarnation) == 1)
                }

                try await fixture.runtime.flushDisposedAssetsForTesting()
                let afterEvent = await fixture.governor.assetTransferRefundSnapshotForTesting(id)
                #expect(afterEvent.present)
                #expect(afterEvent.attempts == attemptsAtHold)
                #expect(afterEvent.memoryBytes == charge.memoryBytes)
                #expect(await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner).cleanupPending)
                #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == 1)
                let retainedPixels = race.event == .stop || race.event == .disable ? 0 : 4
                #expect(await fixture.governor.usage(.assetBytes, owner: fixture.owner) == retainedPixels)
                #expect(
                    await fixture.governor.usage(.admittedMemoryBytes, owner: fixture.owner)
                        == beforeMemory + expectedAdditional - (8 - retainedPixels) / 4 * (4 + 4_096)
                )
                if race.event.isNonterminal {
                    #expect(
                        await fixture.runtime.snapshot(at: fixture.clock.now().wall).publications.contains {
                            $0.id == fixture.ids[0]
                        } == false
                    )
                    // Real replacement admission cannot cross the active frame barrier.
                    await #expect(throws: AddonFailure.self) {
                        try await fixture.runtime.assignPublication(
                            owner     : fixture.owner,
                            featureID : "controls",
                            instanceID: fixture.ids[0].instanceID
                        )
                    }
                }
            }

            if case .completed(.accepted, _) = result { Issue.record("Revoked frame returned success") }
            let reply = try await fixture.consumeReply()
            #expect(reply == nil || reply?.result == .failure)
            let id    = try #require(reservationID)
            var final = await fixture.governor.assetTransferRefundSnapshotForTesting(id)
            if race.fault {
                #expect(final.present)
                #expect(final.lastReservationID == id)
                #expect(final.attempts > attemptsAtHold)
                #expect(final.attempts - attemptsAtHold <= 3)
                #expect(
                    await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner).deferredAssemblers == 1
                )
                for _ in 0..<3 {
                    let previousAttempts = final.attempts
                    let previousDrains   = await fixture.runtime.assetLifecycleSnapshotForTesting(
                        owner: fixture.owner
                    ).cleanupDrains
                    try await fixture.drainCleanup()
                    final = await fixture.governor.assetTransferRefundSnapshotForTesting(id)
                    let drainCount = await fixture.runtime.assetLifecycleSnapshotForTesting(
                        owner: fixture.owner
                    ).cleanupDrains - previousDrains
                    #expect(final.present)
                    // Deadline service drains once, and ordinary nextDelay admission drains
                    // before and after its operation. Closed admission omits those last two.
                    let expectedDrains: UInt64 =
                        race.event == .stop || race.event == .disable || race.event == .closeQuiescing ? 1 : 3
                    #expect(drainCount == expectedDrains)
                    #expect(final.attempts - previousAttempts == drainCount)
                    #expect(
                        await fixture.runtime.assetLifecycleSnapshotForTesting(
                            owner: fixture.owner
                        ).deferredAssemblers == 1
                    )
                }

                await fixture.governor.armAssetTransferRefundFailureForTesting(count: 0)
                try await fixture.drainCleanup()
            }

            try await fixture.runtime.flushDisposedAssetsForTesting()
            final = await fixture.governor.assetTransferRefundSnapshotForTesting(id)
            #expect(!final.present)
            #expect(final.successes == successesAtHold + 1)
            let cleaned = await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner)
            #expect(!cleaned.activeAdmission)
            #expect(cleaned.deferredAssemblers == 0)
            #expect(cleaned.pendingMetadataBytes == 0)
            #expect(cleaned.transferBinding == nil)
            #expect(cleaned.rasterFaults == 0)
            #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation) == false)
            #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
            #expect(observer.snapshot().nativeReturns == (race.point == .native ? 1 : 0))
            #expect(observer.snapshot().aliasCommits == 0)
            let preservesPin = race.event != .stop && race.event != .disable
            #expect(await fixture.governor.usage(.assetBytes, owner: fixture.owner) == (preservesPin ? 4 : 0))
            #expect(cleaned.rasterSlots == (preservesPin ? 1 : 0))
            let expectedMetadata = race.event.isNonterminal
                ? before.assetMetadataBytes - 4_096
                : preservesPin ? before.assetMetadataBytes - 8_192 : 0
            #expect(cleaned.assetMetadataBytes == expectedMetadata)
            #expect(await fixture.governor.usage(.providers, owner: fixture.owner) == (race.event == .exit ? 0 : 1))
            if race.event == .closeStopping {
                #expect(await fixture.governor.usage(.jobs, owner: fixture.owner) == 1)
                #expect(await fixture.governor.usage(.commands, owner: fixture.owner) == 1)
            }

            if race.event.isNonterminal {
                #expect(cleaned.assembler?.identity == before.assembler?.identity)
                #expect(cleaned.assembler?.closed == false)
                let imported = try await fixture.importAlias(
                    png,
                    publicationID: fixture.ids[1],
                    sequences    : (10, 11, 12)
                )
                #expect(imported.width == 8)
                #expect(
                    await fixture.runtime.snapshot(at: fixture.clock.now().wall).publications.contains {
                        $0.id == fixture.ids[0]
                    } == false
                )
            } else if race.event != .exit {
                #expect(cleaned.assembler?.closed == true)
            }
        } catch {
            await fixture.governor.armAssetTransferRefundFailureForTesting(count: 0)
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    /// exitDrainAttemptsEachRetainedAssemblerOnce detects retrying the same failed token in
    /// both the exit loop and the final retained-assembler loop of a single drain invocation.
    @Test
    func exitDrainAttemptsEachRetainedAssemblerOnce() async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            _ = try await fixture.exchange(
                AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: fixture.ids[0],
                    totalBytes   : 128
                ),
                sequence: 1
            )
            let before        = await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner)
            let reservationID = try #require(before.assembler?.reservationID)
            let attempts      = await fixture.governor.assetTransferRefundSnapshotForTesting(
                reservationID
            ).attempts
            await fixture.governor.armAssetTransferRefundFailureForTesting(count: 2)
            // This is explicitly the modeled trusted observation input, not native exit proof.
            await fixture.runtime.observeExit(fixture.connection.incarnation)
            let failed = await fixture.governor.assetTransferRefundSnapshotForTesting(reservationID)
            #expect(failed.attempts - attempts == 1)
            #expect(failed.present)
            #expect(
                await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner).deferredAssemblers == 1
            )
            await fixture.governor.armAssetTransferRefundFailureForTesting(count: 0)
            await fixture.runtime.stop()
            let final = await fixture.governor.assetTransferRefundSnapshotForTesting(reservationID)
            #expect(!final.present)
            #expect(final.successes == 1)
            #expect(await fixture.runtime.requestStop().cleanupPending == false)
        } catch {
            await fixture.governor.armAssetTransferRefundFailureForTesting(count: 0)
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    @Test(arguments: [AssetLifecycleObserver.Point.admission, .native])
    func unrelatedEndPreservesHeldRealWork(_ point: AssetLifecycleObserver.Point) async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            _ = try await fixture.publish(
                [
                    fixture.publication(id: fixture.ids[0], asset: nil),
                    fixture.publication(id: fixture.ids[1], asset: nil)
                ],
                sequence: 1
            )
            let unrelated = try await fixture.binding(1)
            let png       = try lifecyclePNG(width: 8, height: 8)
            let observer  = AssetLifecycleObserver(governor: fixture.governor, point: point)
            var transferID: UUID?
            if point == .native {
                transferID = try await fixture.exchange(
                    AssetTransferRequest(
                        requestID    : UUID(),
                        operation    : .begin,
                        publicationID: fixture.ids[0],
                        totalBytes   : png.count
                    ),
                    sequence: 1
                ).transferID
                _ = try await fixture.receiveAllChunks(
                    png,
                    transferID: #require(transferID),
                    startingAt: 2
                )
            }

            let request = try point == .admission
                ? AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: fixture.ids[0],
                    totalBytes   : png.count
                )
                : AssetTransferRequest(
                    requestID : UUID(),
                    operation : .finish,
                    transferID: transferID
                )
            let result = try await fixture.withHeldRequest(
                request,
                sequence: point == .admission ? 1 : 3,
                observer: observer
            ) {
                let applied = try await fixture.runtime.endAssetPublicationForTesting(unrelated)
                #expect(applied)
            }

            #expect(result == .completed(.accepted, .handedOff))
            var response = try #require(await fixture.consumeReply())
            if point == .admission {
                let id = try #require(response.transferID)
                _ = try await fixture.receiveAllChunks(
                    png,
                    transferID: id,
                    startingAt: 2
                )
                response = try await fixture.exchange(
                    AssetTransferRequest(
                        requestID : UUID(),
                        operation : .finish,
                        transferID: id
                    ),
                    sequence: 3
                )
            }

            #expect(response.result == .imported)
            #expect(response.assetHandle?.width == 8)
            #expect(await fixture.runtime.snapshot(at: fixture.wall).publications.count == 1)
        } catch {
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    @Test(arguments: [AssetLifecycleObserver.Point.admission, .native], [Event.end, .expiry])
    func immutableAssignmentAndLegitimateReplacementRejectOldAuthority(
        _ point: AssetLifecycleObserver.Point,
        _ event: Event
    ) async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            try await fixture.publishExpiring()
            let original = try await fixture.binding()
            let repeated = try await fixture.runtime.assignPublication(
                owner     : fixture.owner,
                featureID : "controls",
                instanceID: fixture.ids[0].instanceID
            )
            #expect(repeated == fixture.ids[0])
            #expect(try await fixture.binding() == original)
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.assignPublication(
                    owner     : fixture.owner,
                    featureID : "other",
                    instanceID: fixture.ids[0].instanceID
                )
            }

            let png      = try lifecyclePNG(width: 8, height: 8)
            let observer = AssetLifecycleObserver(governor: fixture.governor, point: point)
            var transferID: UUID?
            if point == .native {
                transferID = try await fixture.exchange(
                    AssetTransferRequest(
                        requestID    : UUID(),
                        operation    : .begin,
                        publicationID: fixture.ids[0],
                        totalBytes   : png.count
                    ),
                    sequence: 1
                ).transferID
                _ = try await fixture.receiveAllChunks(
                    png,
                    transferID: #require(transferID),
                    startingAt: 2
                )
            }

            let request = try point == .admission
                ? AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: fixture.ids[0],
                    totalBytes   : png.count
                )
                : AssetTransferRequest(
                    requestID : UUID(),
                    operation : .finish,
                    transferID: transferID
                )
            _ = try await fixture.withHeldRequest(
                request,
                sequence: point == .admission ? 1 : 3,
                observer: observer
            ) {
                if event == .end {
                    #expect(try await fixture.runtime.endAssetPublicationForTesting(original))
                } else {
                    fixture.clock.set(
                        RuntimeInstant(wall: fixture.wall.addingTimeInterval(5), monotonic: .seconds(5))
                    )
                    try await fixture.serviceBusyDeadline()
                }

                await #expect(throws: AddonFailure.self) {
                    try await fixture.runtime.assignPublication(
                        owner     : fixture.owner,
                        featureID : "controls",
                        instanceID: fixture.ids[0].instanceID
                    )
                }

                await #expect(throws: AddonFailure.self) {
                    try await fixture.runtime.requestLaunch(owner: fixture.owner)
                }
            }

            _ = try await fixture.consumeReply()
            // The modeled exact exit is an explicit part of this replacement scenario, after
            // the old request has drained. It is never used to make the held work refund.
            await fixture.runtime.observeExit(fixture.connection.incarnation)
            let newID = try await fixture.runtime.assignPublication(
                owner     : fixture.owner,
                featureID : "controls",
                instanceID: fixture.ids[0].instanceID
            )
            #expect(newID != original.publicationID)
            let reconnected = try await fixture.reconnect()
            let replacement = reconnected.using(reconnected.connection, ids: [newID, fixture.ids[1]])
            let fresh       = try await replacement.binding()
            #expect(fresh.assignmentToken != original.assignmentToken)
            let begun = try await replacement.exchange(
                AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: newID,
                    totalBytes   : png.count
                ),
                sequence: 1
            )
            let token  = try #require(begun.transferID)
            let before = await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner)
            #expect(try await fixture.runtime.endAssetPublicationForTesting(original) == false)
            await fixture.runtime.closeConnection(fixture.connection)
            #expect(
                await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner).transferBinding == fresh
            )
            #expect(
                await fixture.runtime.assetLifecycleSnapshotForTesting(
                    owner: fixture.owner
                ).assembler?.reservationID == before.assembler?.reservationID
            )
            _ = try await replacement.receiveAllChunks(
                png,
                transferID: token,
                startingAt: 2
            )
            let imported = try await replacement.exchange(
                AssetTransferRequest(
                    requestID : UUID(),
                    operation : .finish,
                    transferID: token
                ),
                sequence: 3
            )
            #expect(imported.assetHandle?.publicationID == newID)
        } catch {
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    @Test
    func realRuntimeDecodesOnceAndActualLastBorrowOwnsRaster() async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            let observer = AssetLifecycleObserver(governor: fixture.governor, point: .none)
            // Incompressible deterministic input exercises several real 64 KiB chunk frames.
            let png = try lifecyclePNG(width: 192, height: 192)
            try #require(png.count > 65_536)
            let finished = try await AssetLifecycleTesting.$observer.withValue(observer) {
                let begun = try await fixture.exchange(
                    AssetTransferRequest(
                        requestID    : UUID(),
                        operation    : .begin,
                        publicationID: fixture.ids[0],
                        totalBytes   : png.count
                    ),
                    sequence: 1
                )
                let transfer       = try #require(begun.transferID)
                let finishSequence = try await fixture.receiveAllChunks(
                    png,
                    transferID: transfer,
                    startingAt: 2
                )
                let response = try await fixture.exchange(
                    AssetTransferRequest(
                        requestID : UUID(),
                        operation : .finish,
                        transferID: transfer
                    ),
                    sequence: finishSequence
                )

                return (try #require(response.assetHandle), transfer)
            }

            let imported  = finished.0
            let duplicate = try await AssetLifecycleTesting.$observer.withValue(observer) {
                try await fixture.exchange(
                    AssetTransferRequest(
                        requestID : UUID(),
                        operation : .finish,
                        transferID: finished.1
                    ),
                    sequence: 10
                )
            }

            #expect(duplicate.result == .failure)
            #expect(observer.snapshot().admissions == 1)
            #expect(observer.snapshot().decodeEntries == 1)
            #expect(observer.snapshot().decodeReservations == 1)
            #expect(observer.snapshot().nativeDraws == 1)
            #expect(observer.snapshot().nativeReturns == 1)
            #expect(observer.snapshot().aliasCommits == 1)
            #expect(imported.width == 192 && imported.height == 192)
            let shared = try await AssetLifecycleTesting.$observer.withValue(observer) {
                try await fixture.exchange(
                    AssetTransferRequest(
                        requestID    : UUID(),
                        operation    : .share,
                        publicationID: fixture.ids[1],
                        sourceHandle : imported
                    ),
                    sequence: 20
                )
            }

            let alias = try #require(shared.assetHandle)
            _ = try await fixture.publish(
                [
                    fixture.publication(id: fixture.ids[0], asset: imported.assetID),
                    fixture.publication(id: fixture.ids[1], asset: alias.assetID)
                ],
                sequence: 1
            )
            for (offset, handle) in [imported, alias].enumerated() {
                _ = try await AssetLifecycleTesting.$observer.withValue(observer) {
                    try await fixture.exchange(
                        AssetTransferRequest(
                            requestID   : UUID(),
                            operation   : .release,
                            sourceHandle: handle
                        ),
                        sequence: UInt64(21 + offset)
                    )
                }
            }

            #expect(observer.snapshot().decodeEntries == 1)
            let charged = await fixture.governor.usage(.assetBytes)
            #expect(charged == 192 * 192 * 4)
            // The lexical helper owns the actual CGImage after both publications end.
            try await retainImageAcrossEnd(
                fixture,
                imported: imported,
                charged : charged
            )
            try await fixture.runtime.flushDisposedAssetsForTesting()
            #expect(await fixture.governor.usage(.assetBytes) == 0)
            #expect(await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner).rasterSlots == 0)
        } catch {
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    @Test
    func foreignAddonCannotTakeOrRevokeCanonicalTransfer() async throws {
        let fixture = try await AssetLifecycleFixture.make(foreign: true)
        do {
            let otherConnection = try #require(fixture.companion)
            let otherID         = try #require(fixture.companionID)
            let other           = fixture.using(otherConnection, ids: [otherID])
            let png             = try lifecyclePNG(width: 8, height: 8)
            let begun           = try await fixture.exchange(
                AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: fixture.ids[0],
                    totalBytes   : png.count
                ),
                sequence: 1
            )
            let transfer = try #require(begun.transferID)
            let before   = await fixture.runtime.assetLifecycleSnapshotForTesting(owner: fixture.owner)
            let request  = try AssetTransferRequest(
                requestID : UUID(),
                operation : .chunk,
                transferID: transfer,
                offset    : 0,
                bytes     : png
            )
            let ingress = try #require(
                fixture.adapter.stageAssetIngress(
                    AssetTransferFrameCodec.encode(request, profile: .v1),
                    incarnation: fixture.connection.incarnation,
                    sequence   : 2
                )
            )
            let takes = fixture.adapter.ingressTakeAttempts
            #expect(
                await fixture.runtime.receiveAssetRequest(ingress, connection: otherConnection)
                    == .refused(.invalidPayload)
            )
            #expect(fixture.adapter.ingressTakeAttempts == takes)
            let foreignBegin = try await other.exchange(
                AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: fixture.ids[0],
                    totalBytes   : png.count
                ),
                sequence: 1
            )
            #expect(foreignBegin.result == .failure)
            #expect(try await other.exchange(request, sequence: 2).result == .failure)
            #expect(
                await fixture.runtime.assetLifecycleSnapshotForTesting(
                    owner: fixture.owner
                ).assembler?.reservationID == before.assembler?.reservationID
            )
            _ = try await fixture.exchange(request, sequence: 2)
            #expect(
                try await fixture.exchange(
                    AssetTransferRequest(requestID: UUID(), operation: .finish, transferID: transfer),
                    sequence: 3
                ).result == .imported
            )
            #expect(try await other.importAlias(png, publicationID: other.ids[0], sequences: (3, 4, 5)).width == 8)
        } catch {
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    @Test
    func genuinelyPreviousConnectionCannotDisturbReplacementReplyAndTransfer() async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            let png   = try lifecyclePNG(width: 8, height: 8)
            let begin = try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : png.count
            )
            #expect(try await fixture.rawResult(begin, sequence: 1) == .completed(.accepted, .handedOff))
            guard case .assetResponse(let oldDelivery)? = fixture.adapter.currentDelivery(
                incarnation: fixture.connection.incarnation
            )
            else { throw AddonFailure(code: .invalidPayload, reason: "Missing actual old receipt") }

            _ = try await fixture.consumeReply()
            await fixture.runtime.closeConnection(fixture.connection)
            await fixture.runtime.observeExit(fixture.connection.incarnation)
            let fresh = try await fixture.reconnect()
            #expect(fresh.connection.token != fixture.connection.token)
            #expect(fresh.connection.incarnation != fixture.connection.incarnation)
            #expect(try await fresh.rawResult(begin, sequence: 1) == .completed(.accepted, .handedOff))
            guard case .assetResponse(let currentDelivery)? = fixture.adapter.currentDelivery(
                incarnation: fresh.connection.incarnation
            )
            else { throw AddonFailure(code: .invalidPayload, reason: "Missing actual new receipt") }

            let response = try AssetTransferFrameCodec.decodeResponse(currentDelivery.payload, profile: .v1)
            let transfer = try #require(response.transferID)
            let ingress  = try #require(
                fixture.adapter.stageAssetIngress(
                    AssetTransferFrameCodec.encode(
                        AssetTransferRequest(
                            requestID : UUID(),
                            operation : .chunk,
                            transferID: transfer,
                            offset    : 0,
                            bytes     : png
                        ),
                        profile: .v1
                    ),
                    incarnation: fresh.connection.incarnation,
                    sequence   : 2
                )
            )
            let takes = fixture.adapter.ingressTakeAttempts
            #expect(
                await fixture.runtime.receiveAssetRequest(ingress, connection: fixture.connection)
                    == .refused(.sessionRevoked)
            )
            #expect(fixture.adapter.ingressTakeAttempts == takes)
            #expect(
                await fixture.runtime.receiveAssetReceipt(oldDelivery.receipt, connection: fixture.connection) == false
            )
            await fixture.runtime.closeConnection(fixture.connection)
            #expect(
                fixture.adapter.currentDelivery(incarnation: fresh.connection.incarnation)
                    == .assetResponse(currentDelivery)
            )
            #expect(await fixture.runtime.receiveAssetReceipt(currentDelivery.receipt, connection: fresh.connection))
            _ = try await fresh.receiveAllChunks(
                png,
                transferID: transfer,
                startingAt: 2
            )
            #expect(
                try await fresh.exchange(
                    AssetTransferRequest(requestID: UUID(), operation: .finish, transferID: transfer),
                    sequence: 3
                ).result == .imported
            )
        } catch {
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    @Test(arguments: [false, true])
    func actionAndAssetDeliveryContendWithExactReceipts(actionFirst: Bool) async throws {
        let fixture = try await AssetLifecycleFixture.make()
        do {
            _ = try await fixture.publish(
                [
                    Publication(
                        id         : fixture.ids[1],
                        revision   : 1,
                        kind       : .widget,
                        content    : ActionFixture().presentation(),
                        timeline   : nil,
                        expiresAt  : fixture.wall.addingTimeInterval(60),
                        stalePolicy: .remove
                    )
                ],
                sequence: 1
            )
            let action = try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : fixture.ids[1],
                actionID        : "pause",
                input           : Data([7]),
                deadline        : fixture.wall.addingTimeInterval(20),
                observedRevision: 1
            )
            _ = try await fixture.runtime.submitAction(action)
            var delivery: ActionDispatcher.Delivery?
            let begin = try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .begin,
                publicationID: fixture.ids[0],
                totalBytes   : 4
            )
            if actionFirst {
                #expect(try await fixture.runtime.pumpReady())
                delivery = try #require(fixture.adapter.lastAction) as ActionDispatcher.Delivery
                let takes = fixture.adapter.ingressTakeAttempts
                #expect(try await fixture.rawResult(begin, sequence: 1) == .refused(.resourceDenied))
                #expect(fixture.adapter.ingressTakeAttempts == takes)
                #expect(
                    try await fixture.runtime.receiveAcknowledgment(#require(delivery), connection: fixture.connection)
                )
                #expect(await fixture.governor.usage(.jobs, owner: fixture.owner) == 1)
            }

            #expect(try await fixture.rawResult(begin, sequence: 1) == .completed(.accepted, .handedOff))
            guard case .assetResponse(let assetDelivery)? = fixture.adapter.currentDelivery(
                incarnation: fixture.connection.incarnation
            )
            else { throw AddonFailure(code: .invalidPayload, reason: "Missing actual asset reply") }

            if let delivery {
                #expect(
                    try await fixture.runtime.receiveAcknowledgment(delivery, connection: fixture.connection) == false
                )
                _ = try await fixture.runtime.receiveActionCompletion(
                    delivery,
                    connection: fixture.connection,
                    outcome   : .completed(payload: Data())
                )
                #expect(
                    fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation)
                        == .assetResponse(assetDelivery)
                )
            } else {
                #expect(try await fixture.runtime.pumpReady() == false)
            }

            let forged = RuntimeAssetReceipt(
                token          : UUID(),
                incarnation    : assetDelivery.receipt.incarnation,
                connectionToken: assetDelivery.receipt.connectionToken,
                sequence       : assetDelivery.receipt.sequence,
                requestID      : assetDelivery.receipt.requestID,
                operation      : assetDelivery.receipt.operation
            )
            #expect(await fixture.runtime.receiveAssetReceipt(forged, connection: fixture.connection) == false)
            #expect(
                fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation)
                    == .assetResponse(assetDelivery)
            )
            let response = try #require(await fixture.consumeReply())
            if !actionFirst {
                #expect(try await fixture.runtime.pumpReady())
                let actionDelivery = try #require(fixture.adapter.lastAction)
                #expect(
                    await fixture.runtime.receiveAssetReceipt(
                        assetDelivery.receipt,
                        connection: fixture.connection
                    ) == false
                )
                #expect(fixture.adapter.lastAction == actionDelivery)
                #expect(try await fixture.runtime.receiveAcknowledgment(actionDelivery, connection: fixture.connection))
                _ = try await fixture.runtime.receiveActionCompletion(
                    actionDelivery,
                    connection: fixture.connection,
                    outcome   : .completed(payload: Data())
                )
            }

            #expect(await fixture.governor.usage(.jobs, owner: fixture.owner) == 0)
            #expect(await fixture.governor.usage(.commands, owner: fixture.owner) == 0)
            _ = try await fixture.exchange(
                AssetTransferRequest(
                    requestID : UUID(),
                    operation : .abort,
                    transferID: #require(response.transferID) as UUID
                ),
                sequence: 2
            )
            #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        } catch {
            await fixture.tearDown()
            throw error
        }

        await fixture.tearDown()
    }

    private func retainImageAcrossEnd(
        _ fixture: AssetLifecycleFixture,
        imported : AssetHandle,
        charged  : Int
    ) async throws {
        let image = try #require(
            await fixture.runtime.assetImage(
                assetID            : imported.assetID,
                publicationID      : fixture.ids[0],
                publicationRevision: 1
            )
        )
        for index in [0, 1] {
            #expect(try await fixture.runtime.endAssetPublicationForTesting(fixture.binding(index)))
        }

        try await fixture.runtime.flushDisposedAssetsForTesting()
        #expect(await fixture.governor.usage(.assetBytes) == charged)
        #expect(image.width == 192 && image.height == 192)
        let data = try #require(image.dataProvider?.data)
        #expect(CFDataGetLength(data) == charged)
        #expect(Array((data as Data).prefix(4)) == [16, 166, 37, 255])
        withExtendedLifetime(image) {}
    }
}
#endif
