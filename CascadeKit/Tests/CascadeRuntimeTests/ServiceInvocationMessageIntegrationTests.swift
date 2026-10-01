//
//  ServiceInvocationMessageIntegrationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ServiceInvocationMessageIntegrationTests {

    @Test(arguments: [false, true], [false, true])
    func completionAtCleanupTailDrainsWithoutAnotherEventAndRefundRetries(
        failRefund          : Bool,
        enqueueAnotherRefund: Bool
    ) async throws {
        try await withInvocationHost(secondConsumer: true) { host in
            let anotherPublicationID: PublicationID?
            if enqueueAnotherRefund {
                anotherPublicationID = try await host.runtime.assignPublication(
                    owner     : host.leaf,
                    featureID : "summary",
                    instanceID: UUID()
                )
            } else { anotherPublicationID = nil }
            let launchA   = try await host.runtime.requestLaunch(owner: host.leaf)
            let consumerA = try await host.runtime.attach(
                launchID: launchA,
                offer   : InvocationMessageHost.offer(3)
            )
            let permissionA = try await host.runtime.authorizeService(
                connection           : consumerA,
                requirementID        : host.contractID,
                scope                : ServiceScope(featureID: "summary", operation: host.operation),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )
            let acquisitionA = try await host.runtime.acquireService(
                connection  : consumerA,
                permissionID: permissionA,
                lifetime    : .seconds(30)
            )
            #expect(await host.governor.usage(.providers) == 3)
            let publication = try Publication(
                id      : host.publicationID,
                revision: 1,
                kind    : .widget,
                content : PresentationSet(
                    widget: ContentDocument(
                        root              : .text("Refund owner"),
                        privacy           : .publicContent,
                        accessibilityLabel: "Refund owner"
                    ),
                    compactLeading : nil,
                    compactTrailing: nil,
                    minimal        : nil,
                    expanded       : nil
                ),
                timeline   : nil,
                expiresAt  : host.clock.now().wall.addingTimeInterval(60),
                stalePolicy: .remove
            )
            let output = try ProviderOutput(
                schemaVersion: 1,
                publications : [publication],
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            )
            let stagedPublication = try host.adapter.stagePublication(output, connection: host.consumer)
            let published         = try #require(stagedPublication)
            _ = try await host.runtime.receivePublicationOutput(
                published,
                connection: host.consumer,
                sequence  : 1
            )
            let begun = try await host.asset(
                AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: host.publicationID,
                    totalBytes   : 128
                ),
                sequence: 1
            )
            _ = try #require(begun.transferID)
            let binding = try await host.runtime.assetBindingForTesting(
                publicationID: host.publicationID,
                connection   : host.consumer
            )
            let reservationID = try #require(
                await host.runtime.assetLifecycleSnapshotForTesting(owner: host.owner).assembler?.reservationID
            )
            let before = await host.governor.assetTransferRefundSnapshotForTesting(reservationID)
            #expect(before.present && before.memoryBytes == 4_352)
            var anotherRefund: (binding: AssetTransferBinding, reservationID: UUID)?
            if let id = anotherPublicationID {
                let publicationA = try Publication(
                    id         : id,
                    revision   : 1,
                    kind       : .widget,
                    content    : publication.content,
                    timeline   : nil,
                    expiresAt  : host.clock.now().wall.addingTimeInterval(60),
                    stalePolicy: .remove
                )
                let outputA = try ProviderOutput(
                    schemaVersion: 1,
                    publications : [publicationA],
                    operations   : [],
                    completion   : nil,
                    checkpoint   : nil
                )
                let stagedA = try host.adapter.stagePublication(outputA, connection: consumerA)
                _ = try await host.runtime.receivePublicationOutput(
                    #require(stagedA),
                    connection: consumerA,
                    sequence  : 1
                )
                let beginA = try AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: id,
                    totalBytes   : 128
                )
                let assetIngressA = try #require(
                    host.adapter.stageAsset(
                        AssetTransferFrameCodec.encode(beginA, profile: .v1),
                        connection: consumerA,
                        sequence  : 1
                    )
                )
                _ = await host.runtime.receiveAssetRequest(assetIngressA, connection: consumerA)
                guard case .assetResponse(let assetReplyA) = host.adapter.payload(consumerA.incarnation) else {
                    Issue.record("Missing actual asset begin reply")
                    return
                }

                #expect(await host.runtime.receiveAssetReceipt(assetReplyA.receipt, connection: consumerA))
                anotherRefund = (
                    try await host.runtime.assetBindingForTesting(publicationID: id, connection: consumerA),
                    try #require(
                        await host.runtime.assetLifecycleSnapshotForTesting(owner: host.leaf).assembler?.reservationID
                    )
                )
            }

            let idB      = try await host.begin()
            let provider = try #require(host.providerDelivery)
            guard case .invocation(let invocationB) = try ServiceFrameCodec.decodeProviderFrame(
                provider.payload,
                profile: .v1_3
            ) else {
                Issue.record("B did not dispatch")
                return
            }

            let requestB = try ServiceInvocationRequest(
                grantID   : host.acquisition.grant.id,
                invocation: invocationB
            )
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            let requestA = try ServiceInvocationRequest(
                grantID   : acquisitionA.grant.id,
                invocation: host.invocation()
            )
            let ingressA = try #require(
                host.adapter.stage(
                    ServiceFrameCodec.encode(requestA, profile: .v1_3),
                    connection: consumerA,
                    sequence  : 1,
                    kind      : .invocation
                )
            )
            let tail = InvocationRouteGate()
            await host.resources.armResize()
            let admissionA = Task {
                await AddonRuntime.$serviceInvocationObserver.withValue({ point in
                    if point == .cleanupTailBeforeAssembler { await tail.pause() }
                }) {
                    let result = await host.runtime.receiveServiceRequest(ingressA, connection: consumerA)
                    await host.resources.releaseGate()
                    await tail.release()

                    return result
                }
            }

            do {
                await host.resources.waitForArrival()
                try #require(await host.runtime.assetLifecycleSnapshotForTesting(owner: host.owner).activeAdmission)
                #expect(try await host.runtime.endAssetPublicationForTesting(binding))
                let revoked = await host.runtime.assetLifecycleSnapshotForTesting(owner: host.owner)
                #expect(revoked.deferredAssemblers == 1 && revoked.assembler?.phase == "disposing")
                #expect(revoked.assembler?.bufferBytes == 0 && revoked.assembler?.refundInFlight == false)
                if failRefund { await host.governor.armAssetTransferRefundFailureForTesting(count: 20) }
                await host.resources.releaseGate()
                await tail.wait()
                try #require(await tail.hasArrived, "Must reach the final assembler refund boundary")
                // The main cleanup loop has ended; the real assembler call is NEXT.
                // This does not claim suspension inside the governor or disposalInFlight.
                let held = await host.runtime.assetLifecycleSnapshotForTesting(owner: host.owner)
                #expect(!held.activeAdmission && held.cleanupPending && held.deferredAssemblers == 0)
                #expect(held.assembler?.reservationID == reservationID && held.assembler?.phase == "disposing")
                #expect(held.assembler?.refundInFlight == false)
                #expect(
                    await host.governor.assetTransferRefundSnapshotForTesting(reservationID).attempts == before.attempts
                )
                #expect(host.adapter.cancelledServiceIngresses(consumerA.incarnation) == 1)
                #expect(host.adapter.payload(consumerA.incarnation) == nil && host.replyDelivery == nil)
                let completionB = try #require(
                    host.adapter.stage(
                        host.completionBytes(requestID: idB, bytes: 65_536, padding: 17),
                        connection: host.provider,
                        sequence  : 1,
                        kind      : .completion
                    )
                )
                #expect(
                    try await host.runtime.receiveServiceCompletionOutput(
                        completionB,
                        connection: host.provider
                    ) == .pendingServiceCompletion
                )
                #expect(host.adapter.hasIngress(host.provider.incarnation))
                if let anotherRefund {
                    // New cleanup queued during this tail has not yet attempted a refund.
                    #expect(try await host.runtime.endAssetPublicationForTesting(anotherRefund.binding))
                }

                await tail.release()
                guard case .admitted = await admissionA.value else {
                    throw AddonFailure(
                        code  : .invalidPayload,
                        reason: "A lost its correlated refusal"
                    )
                }

                // No external runtime event or A receipt precedes these assertions.
                let refunded = await host.governor.assetTransferRefundSnapshotForTesting(reservationID)
                let refundCount: UInt64 = enqueueAnotherRefund ? 2 : 1
                #expect(refunded.attempts == before.attempts + refundCount)
                #expect(refunded.successes == before.successes + (failRefund ? 0 : refundCount))
                #expect(
                    refunded.lastReservationID == (anotherRefund?.reservationID ?? reservationID)
                        && refunded.present == failRefund
                )
                #expect(refunded.memoryBytes == (failRefund ? 4_352 : 0))
                if let anotherRefund {
                    let other = await host.governor.assetTransferRefundSnapshotForTesting(
                        anotherRefund.reservationID
                    )
                    #expect(other.present == failRefund && other.memoryBytes == (failRefund ? 4_352 : 0))
                }

                #expect(
                    await host.runtime.assetLifecycleSnapshotForTesting(owner: host.owner).deferredAssemblers
                        == (failRefund ? Int(refundCount) : 0)
                )
                guard case .serviceReply(let replyA) = host.adapter.payload(consumerA.incarnation) else {
                    throw AddonFailure(code: .invalidPayload, reason: "Missing A refusal")
                }

                let decodedA = try ServiceFrameCodec.decodeInvocationReply(replyA.payload, profile: .v1_3)
                try decodedA.validate(matching: requestA)
                guard case .refused(let code, _) = decodedA.result else {
                    throw AddonFailure(code: .invalidPayload, reason: "A must not dispatch")
                }

                #expect(code == .resourceDenied)
                #expect(host.adapter.hasIngress(host.provider.incarnation) == false)
                #expect(host.adapter.finishedServiceIngresses(host.provider.incarnation) == 1)
                #expect(host.adapter.cancelledServiceIngresses(host.provider.incarnation) == 0)
                #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
                #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
                #expect(host.adapter.serviceInvocationHandoffs(host.provider.incarnation) == 1)
                let replyB   = try #require(host.replyDelivery, "B must finish without A receipt or another event")
                let decodedB = try ServiceFrameCodec.decodeInvocationReply(replyB.payload, profile: .v1_3)
                try decodedB.validate(matching: requestB)
                #expect(decodedB.result == .completed(try host.response(bytes: 65_536)))
                #expect(host.adapter.payload(consumerA.incarnation) == .serviceReply(replyA))
                #expect(host.adapter.settled.isEmpty)
                // Later physical receipts may retry the retained failed refund, after the
                // once-per-outer-cycle assertion has already been made above.
                await host.governor.armAssetTransferRefundFailureForTesting(count: 0)
                #expect(await host.runtime.receiveServiceReceipt(replyB.receipt, connection: host.consumer))
                #expect(await host.runtime.receiveServiceReceipt(replyB.receipt, connection: host.consumer) == false)
                #expect(await host.runtime.receiveServiceReceipt(replyA.receipt, connection: consumerA))
                #expect(await host.runtime.receiveServiceReceipt(replyA.receipt, connection: consumerA) == false)
                #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider) == false)
                let settled = await host.governor.assetTransferRefundSnapshotForTesting(reservationID)
                #expect(!settled.present && settled.successes == before.successes + refundCount)
                #expect(settled.attempts == before.attempts + (failRefund ? 2 * refundCount : refundCount))
                if let anotherRefund {
                    #expect(
                        await host.governor.assetTransferRefundSnapshotForTesting(
                            anotherRefund.reservationID
                        ).present == false
                    )
                }

                #expect(host.adapter.finishedServiceIngresses(host.provider.incarnation) == 1)
                #expect(host.adapter.serviceInvocationHandoffs(host.provider.incarnation) == 1)
            } catch {
                await host.resources.releaseGate()
                await tail.release()
                _ = await admissionA.value
                await host.governor.armAssetTransferRefundFailureForTesting(count: 0)
                throw error
            }
        }
    }

    @Test(arguments: [false, true])
    func completionArrivingDuringAnotherConsumersReplyDrainsWithoutReceiptOrExtraEvent(closeB: Bool) async throws {
        try await withInvocationHost(secondConsumer: true) { host in
            // B is the original consumer; A is a second canonically installed consumer.
            let launchA   = try await host.runtime.requestLaunch(owner: host.leaf)
            let consumerA = try await host.runtime.attach(
                launchID: launchA,
                offer   : InvocationMessageHost.offer(3)
            )
            let permissionA = try await host.runtime.authorizeService(
                connection           : consumerA,
                requirementID        : host.contractID,
                scope                : ServiceScope(featureID: "summary", operation: host.operation),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )
            let acquisitionA = try await host.runtime.acquireService(
                connection  : consumerA,
                permissionID: permissionA,
                lifetime    : .seconds(30)
            )
            #expect(acquisitionA.grant.generation == consumerA.publicationConnection.generation)
            #expect(await host.governor.usage(.providers) == 3)
            let invocationB = try host.invocation()
            let idB         = invocationB.requestID
            let rawRequestB = try ServiceFrameCodec.encode(
                ServiceInvocationRequest(grantID: host.acquisition.grant.id, invocation: invocationB),
                profile: .v1_3
            )
            let ingressB = try #require(
                host.adapter.stage(rawRequestB, connection: host.consumer, sequence: 1, kind: .invocation)
            )
            guard case .admitted(let routeB) = await host.runtime.receiveServiceRequest(
                ingressB,
                connection: host.consumer
            ) else {
                Issue.record("B must dispatch before A")
                return
            }

            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            let invocationA = try host.invocation()
            let requestA    = try ServiceInvocationRequest(
                grantID   : acquisitionA.grant.id,
                invocation: invocationA
            )
            let rawA     = try ServiceFrameCodec.encode(requestA, profile: .v1_3)
            let ingressA = try #require(
                host.adapter.stage(rawA, connection: consumerA, sequence: 1, kind: .invocation)
            )
            let gate       = InvocationRouteGate()
            let admissionA = Task {
                await AddonRuntime.$serviceInvocationObserver.withValue({ checkpoint in
                    if checkpoint == .encoded { await gate.pause() }
                }) {
                    let result = await host.runtime.receiveServiceRequest(ingressA, connection: consumerA)
                    await gate.release()

                    return result
                }
            }

            do {
                await gate.wait()
                #expect(await gate.hasArrived)
                #expect(host.adapter.serviceInvocationHandoffs(host.provider.incarnation) == 1)
                let rawB = try host.completionBytes(
                    requestID: idB,
                    bytes    : 65_536,
                    padding  : 17
                )
                let completionB = try #require(
                    host.adapter.stage(rawB, connection: host.provider, sequence: 1, kind: .completion)
                )
                #expect(
                    try await host.runtime.receiveServiceCompletionOutput(
                        completionB,
                        connection: host.provider
                    ) == .pendingServiceCompletion
                )
                #expect(host.adapter.hasIngress(host.provider.incarnation))
                #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
                #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
                if closeB { await host.runtime.closeConnection(host.consumer) }
                await gate.release()
                guard case .admitted(let routeA) = await admissionA.value else {
                    Issue.record("A lost its correlated route")
                    return
                }

                // No receipt, expiry, admission or other runtime event occurs here.
                if closeB {
                    // Closing B invalidates the suspended admission and suppresses both
                    // replies. Deferred completion cancellation must dispose its exact raw
                    // input and settle both routes before any modeled exit arrives.
                    #expect(host.replyDelivery == nil)
                    #expect(host.adapter.payload(consumerA.incarnation) == nil)
                    #expect(host.adapter.hasIngress(host.provider.incarnation) == false)
                    #expect(host.adapter.finishedServiceIngresses(host.provider.incarnation) == 0)
                    #expect(host.adapter.cancelledServiceIngresses(host.provider.incarnation) == 1)
                    let settlements = host.adapter.settled
                    #expect(settlements.count == 2)
                    #expect(
                        settlements.contains(
                            RuntimeServiceSettlement(
                                routeID        : routeA,
                                incarnation    : consumerA.incarnation,
                                connectionToken: consumerA.token,
                                sequence       : 1
                            )
                        )
                    )
                    #expect(
                        settlements.contains(
                            RuntimeServiceSettlement(
                                routeID        : routeB,
                                incarnation    : host.consumer.incarnation,
                                connectionToken: host.consumer.token,
                                sequence       : 1
                            )
                        )
                    )
                    #expect(host.adapter.serviceInvocationHandoffs(host.provider.incarnation) == 1)
                    #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
                    #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
                    // Only actual exit retires physically handed-off command/job work.
                    #expect(
                        await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider) == false
                    )
                    await host.runtime.observeExit(host.provider.incarnation)
                    #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
                    #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
                    #expect(host.adapter.settled == settlements)
                    return
                }
                // A's accepted refusal remains physically retained while B must finish.
                guard case .serviceReply(let replyA) = host.adapter.payload(consumerA.incarnation) else {
                    Issue.record("Missing A refusal")
                    return
                }

                let refusalA = try ServiceFrameCodec.decodeInvocationReply(replyA.payload, profile: .v1_3)
                try refusalA.validate(matching: requestA)
                guard case .refused(let code, _) = refusalA.result else {
                    Issue.record("A must not dispatch")
                    return
                }

                #expect(code == .resourceDenied)
                #expect(host.adapter.hasIngress(host.provider.incarnation) == false)
                #expect(host.adapter.finishedServiceIngresses(host.provider.incarnation) == 1)
                #expect(host.adapter.cancelledServiceIngresses(host.provider.incarnation) == 0)
                #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
                #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
                #expect(host.adapter.serviceInvocationHandoffs(host.provider.incarnation) == 1)
                let replyB   = try #require(host.replyDelivery, "B must deliver without A's receipt or another event")
                let expected = try host.response(bytes: 65_536)
                #expect(
                    try ServiceFrameCodec.decodeInvocationReply(replyB.payload, profile: .v1_3).result
                        == .completed(expected)
                )
                #expect(host.adapter.payload(consumerA.incarnation) == .serviceReply(replyA))
                #expect(host.adapter.settled.isEmpty)
                #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider) == false)
                #expect(await host.runtime.receiveServiceReceipt(replyB.receipt, connection: host.consumer))
                #expect(await host.runtime.receiveServiceReceipt(replyB.receipt, connection: host.consumer) == false)
                #expect(await host.runtime.receiveServiceReceipt(replyA.receipt, connection: consumerA))
                #expect(await host.runtime.receiveServiceReceipt(replyA.receipt, connection: consumerA) == false)
                #expect(host.adapter.finishedServiceIngresses(host.provider.incarnation) == 1)
                #expect(host.adapter.serviceInvocationHandoffs(host.provider.incarnation) == 1)
            } catch {
                await gate.release()
                _ = await admissionA.value
                throw error
            }
        }
    }

    @Test(
        arguments: [AddonRuntime.ServiceInvocationCheckpoint.historyRead, .encoded, .handoff],
        ["disable", "close", "expire"]
    )
    func canonicalLossAtHistoryEncodingAndHandoffSettlesWithoutKnownReply(
        checkpoint: AddonRuntime.ServiceInvocationCheckpoint,
        loss      : String
    ) async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            let gate       = InvocationRouteGate()
            let completion = Task {
                do {
                    try await AddonRuntime.$serviceInvocationObserver.withValue({ point in
                        if point == checkpoint { await gate.pause() }
                    }) { try await host.complete(id, bytes: 65_536) }
                } catch {
                    await gate.release()
                    throw error
                }
            }

            await gate.wait()
            #expect(await gate.hasArrived, "The exact canonical reply checkpoint must be reached")
            switch loss {
                case "disable": await host.runtime.disable(owner: host.owner)
                case "close": await host.runtime.closeConnection(host.consumer)
                default: host.clock.advance(31)
            }

            await gate.release()
            do {
                try await completion.value
            } catch { #expect((error as? AddonFailure)?.code == .sessionRevoked) }
            #expect(host.replyDelivery == nil)
            #expect(host.adapter.settled.count == 1)
            #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
            #expect(await host.governor.usage(.providers, owner: host.provider.identity.addonID) == 1)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
        }
    }

    @Test
    func expiredAttachCleanupSuspensionCannotReturnOrReplaceProvisionalConnection() async throws {
        try await withInvocationHost { host in
            let launch = try await host.runtime.requestLaunch(owner: host.leaf)
            host.clock.advance(31)
            await host.resources.armRelease()
            let attaching = Task {
                do {
                    return try await host.runtime.attach(
                        launchID: launch,
                        offer   : InvocationMessageHost.offer(3)
                    )
                } catch {
                    await host.resources.releaseGate()
                    throw error
                }
            }

            await host.resources.waitForArrival()
            // The real broker disconnect has removed its session and refunded its
            // reservation, while rollback still owns the short admission. The exact
            // provisional publication close occurs before this cleanup suspension.
            #expect(await host.governor.usage(.providers, owner: host.leaf) == 1)
            do {
                _ = try await host.runtime.attach(launchID: launch, offer: InvocationMessageHost.offer(3))
                Issue.record("Replaced provisional connection during cleanup")
            } catch { #expect((error as? AddonFailure)?.code == .resourceDenied) }
            await host.runtime.disable(owner: host.leaf)
            await host.resources.releaseGate()
            do {
                _ = try await attaching.value
                Issue.record("Returned expired provisional connection")
            } catch { #expect((error as? AddonFailure)?.code == .sessionRevoked) }
            #expect(await host.governor.usage(.providers, owner: host.leaf) == 1)
            let start = try #require(host.adapter.starts.first { $0.identity.addonID == host.leaf })
            await host.runtime.observeExit(start.incarnation)
            #expect(await host.governor.usage(.providers, owner: host.leaf) == 0)
        }
    }

    @Test(arguments: ["completed", "refused", "unknown"])
    func maximumCanonicalIdentifiersCorrelateFullInputAndAllReplyOutcomes(outcome: String) async throws {
        try await withInvocationHost(maximumMetadata: true) { host in
            let invocation = try host.invocation(bytes: 65_536)
            #expect(invocation.contractID.utf8.count == 128 && invocation.operation.utf8.count == 128)
            let request = try ServiceInvocationRequest(
                grantID   : host.acquisition.grant.id,
                invocation: invocation
            )
            let raw = try ServiceFrameCodec.encode(request, profile: .v1_3)
            #expect(raw.count > 131_072 && raw.count <= 196_608)
            host.adapter.rejectProviderHandoff = outcome == "refused"
            let ingress = try #require(
                host.adapter.stage(raw, connection: host.consumer, sequence: 1, kind: .invocation)
            )
            guard case .admitted = await host.runtime.receiveServiceRequest(
                ingress,
                connection: host.consumer
            ) else {
                Issue.record("No correlated route")
                return
            }

            if outcome != "refused" {
                let provider = try #require(host.providerDelivery)
                #expect(provider.payload.count > 131_072)
                #expect(
                    try ServiceFrameCodec.decodeProviderFrame(provider.payload, profile: .v1_3)
                        == .invocation(invocation)
                )
                #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
                if outcome == "completed" {
                    let completion = try host.completionBytes(
                        requestID: invocation.requestID,
                        bytes    : 65_536,
                        padding  : 17
                    )
                    #expect(completion.count > 131_072 && completion.count <= 196_608)
                    let input = try #require(
                        host.adapter.stage(completion, connection: host.provider, sequence: 1, kind: .completion)
                    )
                    _ = try await host.runtime.receiveServiceCompletionOutput(
                        input,
                        connection: host.provider
                    )
                } else { await host.runtime.disable(owner: host.provider.identity.addonID) }
            }

            let delivery = try #require(host.replyDelivery)
            let reply    = try ServiceFrameCodec.decodeInvocationReply(delivery.payload, profile: .v1_3)
            try reply.validate(matching: request)
            switch outcome {
                case "completed":
                    #expect(delivery.payload.count > 131_072 && delivery.payload.count <= 196_608)
                    let expected = try host.response(bytes: 65_536)
                    #expect(reply.result == .completed(expected))

                case "refused":
                    guard case .refused(let code, _) = reply.result else {
                        Issue.record("No dispatch refusal")
                        return
                    }

                    #expect(code == .dependencyUnavailable)

                default:
                    #expect(reply.result == .outcomeUnknown)
                    #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
            }

            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.consumer))
        }
    }

    @Test
    func providerReservationSurvivesSharedFamilyCompetitionDuringActualJobAdmission() async throws {
        try await withInvocationHost { host in
            let request = try host.invocation()
            let raw     = try ServiceFrameCodec.encode(
                ServiceInvocationRequest(grantID: host.acquisition.grant.id, invocation: request),
                profile: .v1_3
            )
            let input = try #require(host.adapter.stage(raw, connection: host.consumer, sequence: 1, kind: .invocation))
            await host.resources.armJobAdmission()
            let admission = Task { await host.runtime.receiveServiceRequest(input, connection: host.consumer) }
            await host.resources.waitForArrival()
            do {
                let storageRaw = try StorageFrameCodec.encode(
                    StorageRequest(
                        requestID: UUID(),
                        operation: .read,
                        key      : "busy"
                    ),
                    profile: .v1_1
                )
                let storage = try #require(
                    host.adapter.stageStorage(storageRaw, connection: host.provider, sequence: 1)
                )
                #expect(
                    await host.runtime.receiveStorageRequest(storage, connection: host.provider)
                        == .refused(.resourceDenied)
                )
                let assetRaw = try AssetTransferFrameCodec.encode(
                    AssetTransferRequest(
                        requestID : UUID(),
                        operation : .abort,
                        transferID: UUID()
                    ),
                    profile: .v1
                )
                let asset = try #require(host.adapter.stageAsset(assetRaw, connection: host.provider, sequence: 1))
                #expect(
                    await host.runtime.receiveAssetRequest(asset, connection: host.provider)
                        == .refused(.resourceDenied)
                )
                let genericRaw = try host.adapter.stagePublication(
                    ProviderOutput(
                        schemaVersion: 1,
                        publications : [],
                        operations   : [],
                        completion   : nil,
                        checkpoint   : nil
                    ),
                    connection: host.provider
                )
                let generic = try #require(genericRaw)
                await #expect(throws: AddonFailure.self) {
                    _ = try await host.runtime.receivePublicationOutput(
                        generic,
                        connection: host.provider,
                        sequence  : 1
                    )
                }

                let premature = try #require(
                    host.adapter.stage(
                        try host.completionBytes(requestID: request.requestID),
                        connection: host.provider,
                        sequence  : 1,
                        kind      : .completion
                    )
                )
                await #expect(throws: AddonFailure.self) {
                    _ = try await host.runtime.receiveServiceCompletionOutput(
                        premature,
                        connection: host.provider
                    )
                }

                #expect(host.providerDelivery == nil)
            } catch {
                await host.resources.releaseGate()
                _ = await admission.value
                throw error
            }

            await host.resources.releaseGate()
            guard case .admitted = await admission.value else {
                Issue.record("Reservation stolen while governor suspended")
                return
            }

            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            try await host.complete(request.requestID)
            #expect(host.replyDelivery != nil)
        }
    }

    @Test
    func realSDKCloseDuringHeldAdmissionJoinsPhysicalUnknownSettlement() async throws {
        try await withInvocationHost { host in
            let channel  = InvocationRuntimeByteChannel(host: host)
            let executor = try ServiceInvocationExchange(channel: channel)
            let request  = try host.invocation()
            let invoking = Task { try await executor.invoke(grantID: host.acquisition.grant.id, invocation: request) }
            await host.adapter.providerEvent.wait()
            await channel.requestReturned.wait()
            await host.resources.armResize()
            let held = Task {
                do {
                    return try await host.runtime.assignPublication(
                        owner     : host.leaf,
                        featureID : "controls",
                        instanceID: UUID()
                    )
                } catch {
                    await host.resources.releaseGate()
                    throw error
                }
            }

            await host.resources.waitForArrival()
            invoking.cancel()
            let closing = Task { await executor.close() }
            await channel.closeStarted.wait()
            #expect(channel.hasPhysicalExchange)
            #expect(host.adapter.settled.isEmpty)
            #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
            await host.resources.releaseGate()
            do {
                _ = try await held.value
                Issue.record("Expected changed authority")
            } catch { #expect((error as? AddonFailure)?.code == .sessionRevoked) }
            await closing.value
            do {
                _ = try await invoking.value
                Issue.record("Expected cancellation unknown")
            } catch { #expect((error as? AddonFailure)?.code == .outcomeUnknown) }
            #expect(channel.hasPhysicalExchange == false)
            #expect(host.adapter.settled.count == 1)
            #expect(host.replyDelivery == nil)
        }
    }

    @Test
    func occupiedCanonicalDependencySlotRefusesBeforeBrokerRetentionAndSameIDCanRetry() async throws {
        try await withInvocationHost(dependency: true) { host in
            let leaf = try #require(host.leafConnection)
            let read = try StorageFrameCodec.encode(
                StorageRequest(
                    requestID: UUID(),
                    operation: .read,
                    key      : "dependency"
                ),
                profile: .v1_1
            )
            let storage = try #require(host.adapter.stageStorage(read, connection: leaf, sequence: 1))
            _ = await host.runtime.receiveStorageRequest(storage, connection: leaf)
            guard case .storageResponse(let held) = host.adapter.payload(leaf.incarnation) else {
                Issue.record("No actual dependency reply")
                return
            }

            let id = UUID()
            _ = try await host.begin(requestID: id)
            let reply = try #require(host.replyDelivery)
            guard case .refused(let code, _) = try ServiceFrameCodec.decodeInvocationReply(
                reply.payload,
                profile: .v1_3
            ).result else {
                Issue.record("No slot refusal")
                return
            }

            #expect(code == .resourceDenied)
            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer))
            #expect(await host.runtime.receiveStorageReceipt(held.receipt, connection: leaf))
            _ = try await host.begin(sequence: 2, requestID: id)
            let invocation = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(invocation.receipt, connection: host.provider))
            try await host.complete(id)
            let completed = try #require(host.replyDelivery)
            guard case .completed = try ServiceFrameCodec.decodeInvocationReply(
                completed.payload,
                profile: .v1_3
            ).result else {
                Issue.record("Retry retained no prior broker request")
                return
            }

            #expect(await host.runtime.receiveServiceReceipt(completed.receipt, connection: host.consumer))
        }
    }

    @Test
    func realSDKStorageAssetsAndInternalServiceUseSameCanonicalGeneration() async throws {
        try await withInvocationHost { host in
            let storageChannel = InvocationRuntimeStorageChannel(host: host)
            let assetChannel   = InvocationRuntimeAssetChannel(host: host)
            let serviceChannel = InvocationRuntimeByteChannel(host: host)
            #expect(storageChannel.generation == assetChannel.generation)
            #expect(serviceChannel.generation == storageChannel.generation)
            #expect(host.acquisition.grant.generation == serviceChannel.generation)
            let storage  = try MessageAddonStorageClient(channel: storageChannel)
            let assets   = MessageAddonAssetClient(channel: assetChannel)
            let services = try ServiceInvocationExchange(channel: serviceChannel)
            let context  = try AddonContext(
                services  : InvocationContextServiceClient(exchange: services),
                storage   : storage,
                assets    : assets,
                generation: host.consumer.publicationConnection.generation,
                grants    : [host.acquisition.grant]
            )
            let grant = try #require(context.grants.first)
            #expect(context.generation == grant.generation)
            let request  = try host.invocation()
            let invoking = Task { try await context.services.invoke(request, grant: grant) }
            do {
                await host.adapter.providerEvent.wait()
                let provider = try #require(host.providerDelivery)
                #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
                try await host.complete(request.requestID)
                let expected = try host.response()
                #expect(try await invoking.value == expected)
            } catch {
                await services.close()
                _ = try? await invoking.value
                throw error
            }

            try await context.storage.write(Data([7]), key: "sdk")
            #expect(try await context.storage.read(key: "sdk") == Data([7]))
            let png = try #require(
                Data(
                    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGP4z8DwHx9mGBkKAMLXf4EvceABAAAAAElFTkSuQmCC"
                )
            )
            let asset = try await context.assets.importAsset(png, publicationID: host.publicationID)
            #expect(asset.width == 8 && asset.height == 8)
            #expect(asset.publicationID == host.publicationID)
            try await context.assets.releaseAsset(asset)
            #expect(await host.runtime.diagnostics(owner: host.owner)?.hasOutstandingDelivery == false)
            await services.close()
            await storage.close()
            await assets.close()
        }
    }

    @Test
    func attachRegistrationSuspensionRevokesProvisionalAuthorityAndKeepsProcessCharged() async throws {
        try await withInvocationHost { host in
            let launch = try await host.runtime.requestLaunch(owner: host.leaf)
            await host.resources.armStateAdmission()
            let attaching = Task {
                try await host.runtime.attach(launchID: launch, offer: InvocationMessageHost.offer(3))
            }

            await host.resources.waitForArrival()
            await host.runtime.disable(owner: host.leaf)
            await host.resources.releaseGate()
            do {
                _ = try await attaching.value
                Issue.record("Returned a revoked attach")
            } catch { #expect((error as? AddonFailure)?.code == .sessionRevoked) }
            #expect(await host.governor.usage(.providers, owner: host.leaf) == 1)
            await #expect(throws: AddonFailure.self) { try await host.runtime.enable(owner: host.leaf) }
            let start = try #require(host.adapter.starts.first { $0.identity.addonID == host.leaf })
            await host.runtime.observeExit(start.incarnation)
            #expect(await host.governor.usage(.providers, owner: host.leaf) == 0)
            try await host.runtime.enable(owner: host.leaf)
            let freshLaunch = try await host.runtime.requestLaunch(owner: host.leaf)
            let fresh       = try await host.runtime.attach(
                launchID: freshLaunch,
                offer   : InvocationMessageHost.offer(3)
            )
            #expect(fresh.publicationConnection.negotiatedProtocol.minor == 3)
        }
    }

    @Test(arguments: [false, true])
    func routePoolGrowthRechecksRevocationAndDeadlineBeforeRetention(expire: Bool) async throws {
        try await withInvocationHost { host in
            let request = try host.invocation()
            let raw     = try ServiceFrameCodec.encode(
                ServiceInvocationRequest(grantID: host.acquisition.grant.id, invocation: request),
                profile: .v1_3
            )
            let ingress = try #require(
                host.adapter.stage(raw, connection: host.consumer, sequence: 1, kind: .invocation)
            )
            await host.resources.armResize()
            let admission = Task { await host.runtime.receiveServiceRequest(ingress, connection: host.consumer) }
            await host.resources.waitForArrival()
            if expire { host.clock.advance(31) } else { await host.runtime.closeConnection(host.consumer) }
            await host.resources.releaseGate()
            let outcome = await admission.value
            if expire {
                guard case .admitted = outcome else {
                    Issue.record("Expected correlated expired request")
                    return
                }

                let reply = try #require(host.replyDelivery)
                guard case .refused(let code, _) = try ServiceFrameCodec.decodeInvocationReply(
                    reply.payload,
                    profile: .v1_3
                ).result else {
                    Issue.record("Expected refusal")
                    return
                }

                #expect(code == .sessionRevoked)
                #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer))
            } else { #expect(outcome == .refused(.sessionRevoked)) }
            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
        }
    }

    @Test
    func oneRouteAndPaidMetadataSurviveExecutionCleanupUntilExactReplyReceipt() async throws {
        try await withInvocationHost { host in
            let initial = try #require(await host.runtime.diagnostics(owner: host.owner)).reservedStateBytes
            let id      = try await host.begin()
            let second  = try ServiceFrameCodec.encode(
                ServiceInvocationRequest(grantID: host.acquisition.grant.id, invocation: host.invocation()),
                profile: .v1_3
            )
            let ingress = try #require(
                host.adapter.stage(second, connection: host.consumer, sequence: 2, kind: .invocation)
            )
            #expect(
                await host.runtime.receiveServiceRequest(ingress, connection: host.consumer)
                    == .refused(.resourceDenied)
            )
            #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            try await host.complete(id)
            let retained = try #require(await host.runtime.diagnostics(owner: host.owner)).reservedStateBytes
            #expect(retained >= initial + RuntimeServiceInvocationExchange.routeBytes)
            let reply = try #require(host.replyDelivery)
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer))
            let released = try #require(await host.runtime.diagnostics(owner: host.owner)).reservedStateBytes
            #expect(retained - released == RuntimeServiceInvocationExchange.routeBytes)
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer) == false)
        }
    }

    @Test
    func commonGenerationRealStorageAndAssetTransactionsShareServiceSlots() async throws {
        try await withInvocationHost { host in
            #expect(host.acquisition.grant.generation == host.consumer.publicationConnection.generation)
            let id  = try await host.begin()
            let raw = try StorageFrameCodec.encode(
                StorageRequest(
                    requestID: UUID(),
                    operation: .write,
                    key      : "key",
                    value    : Data([7])
                ),
                profile: .v1_1
            )
            let busy = try #require(host.adapter.stageStorage(raw, connection: host.consumer, sequence: 1))
            #expect(
                await host.runtime.receiveStorageRequest(busy, connection: host.consumer) == .refused(.resourceDenied)
            )
            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            try await host.withHeldAdmission {
                let completion = try #require(
                    host.adapter.stage(
                        try host.completionBytes(requestID: id),
                        connection: host.provider,
                        sequence  : 1,
                        kind      : .completion
                    )
                )
                #expect(
                    try await host.runtime.receiveServiceCompletionOutput(
                        completion,
                        connection: host.provider
                    ) == .pendingServiceCompletion
                )
                #expect(host.adapter.stageStorage(raw, connection: host.provider, sequence: 1) == nil)
                #expect(host.adapter.stageAsset(Data([1]), connection: host.provider, sequence: 1) == nil)
                #expect(
                    try host.adapter.stagePublication(
                        ProviderOutput(
                            schemaVersion: 1,
                            publications : [],
                            operations   : [],
                            completion   : nil,
                            checkpoint   : nil
                        ),
                        connection: host.provider
                    ) == nil
                )
            }

            let reply = try #require(host.replyDelivery)
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer))
            let write = try #require(host.adapter.stageStorage(raw, connection: host.consumer, sequence: 1))
            _ = await host.runtime.receiveStorageRequest(write, connection: host.consumer)
            guard case .storageResponse(let written) = host.adapter.payload(host.consumer.incarnation) else {
                Issue.record("No storage reply")
                return
            }

            #expect(try StorageFrameCodec.decodeResponse(written.payload, profile: .v1_1).result == .acknowledged)
            #expect(await host.runtime.receiveStorageReceipt(written.receipt, connection: host.consumer))
            let read = try #require(
                host.adapter.stageStorage(
                    try StorageFrameCodec.encode(
                        StorageRequest(requestID: UUID(), operation: .read, key: "key"),
                        profile: .v1_1
                    ),
                    connection: host.consumer,
                    sequence  : 2
                )
            )
            _ = await host.runtime.receiveStorageRequest(read, connection: host.consumer)
            guard case .storageResponse(let value) = host.adapter.payload(host.consumer.incarnation) else {
                Issue.record("No read reply")
                return
            }

            #expect(try StorageFrameCodec.decodeResponse(value.payload, profile: .v1_1).value == Data([7]))
            #expect(await host.runtime.receiveStorageReceipt(value.receipt, connection: host.consumer))
            let begun = try await host.asset(
                AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: host.publicationID,
                    totalBytes   : 1
                ),
                sequence: 1
            )
            let transfer = try #require(begun.transferID)
            _ = try await host.asset(
                AssetTransferRequest(
                    requestID : UUID(),
                    operation : .chunk,
                    transferID: transfer,
                    offset    : 0,
                    bytes     : Data([1])
                ),
                sequence: 2
            )
            _ = try await host.asset(
                AssetTransferRequest(
                    requestID : UUID(),
                    operation : .abort,
                    transferID: transfer
                ),
                sequence: 3
            )
            let stagedOutput = try host.adapter.stagePublication(
                ProviderOutput(
                    schemaVersion: 1,
                    publications : [],
                    operations   : [],
                    completion   : nil,
                    checkpoint   : nil
                ),
                connection: host.provider
            )
            let output = try #require(stagedOutput)
            _ = try await host.runtime.receivePublicationOutput(
                output,
                connection: host.provider,
                sequence  : 2
            )
        }
    }

    @Test
    func revokeAfterBrokerCommitReductionNeverDisclosesKnownHistory() async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let delivery = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.provider))
            await host.resources.armReduction()
            let completion = Task { try await host.complete(id) }
            await host.resources.waitForArrival()
            // commitInvocationCompletion commits history synchronously before this
            // real result-capacity reduction await. No fake broker or response lookup.
            await host.runtime.disable(owner: host.owner)
            await host.resources.releaseGate()
            do {
                try await completion.value
                Issue.record("Expected revoked completion return")
            } catch { #expect((error as? AddonFailure)?.code == .sessionRevoked) }
            #expect(host.replyDelivery == nil)
            #expect(host.adapter.settled.count == 1)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
        }
    }

    @Test(arguments: ["contract", "operation", "foreign", "partitionField", "featureField"])
    func theftAndUntrustedScopesFailBeforeDispatch(damage: String) async throws {
        try await withInvocationHost { host in
            let invocation = try ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : damage == "contract" ? "wrong.service" : "com.example.focus.sessions",
                operation    : damage == "operation" ? "write" : "read",
                payload      : Data(),
                deadline     : host.clock.now().wall.addingTimeInterval(20)
            )
            var raw = try ServiceFrameCodec.encode(
                ServiceInvocationRequest(grantID: host.acquisition.grant.id, invocation: invocation),
                profile: .v1_3
            )
            if damage == "partitionField" || damage == "featureField" {
                var object = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
                object[damage == "partitionField" ? "partition" : "featureID"] = "stolen"
                raw = try JSONSerialization.data(withJSONObject: object)
            }

            let connection = damage == "foreign" ? host.provider : host.consumer
            let ingress    = try #require(
                host.adapter.stage(raw, connection: connection, sequence: 1, kind: .invocation)
            )
            let outcome = await host.runtime.receiveServiceRequest(ingress, connection: connection)
            if case .refused(let code) = outcome {
                #expect(code == .invalidPayload)
            } else {
                guard case .serviceReply(let reply) = host.adapter.payload(connection.incarnation) else {
                    Issue.record("No correlated refusal")
                    return
                }

                guard case .refused(let code, _) = try ServiceFrameCodec.decodeInvocationReply(
                    reply.payload,
                    profile: .v1_3
                ).result else {
                    Issue.record("No refusal")
                    return
                }

                #expect(code == .permissionDenied)
                #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: connection))
            }

            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
        }
    }

    @Test
    func providerPayloadReceiptRemainsExactAfterLogicalCompletionRetiresRow() async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let delivery = try #require(host.providerDelivery)
            try await host.complete(id)
            #expect(host.replyDelivery != nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(host.providerDelivery == delivery)
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.provider))
            #expect(host.providerDelivery == nil)
        }
    }

    @Test
    func completionRawCapAndBothDecodedPayloadCapsRejectBeforeCommit() async throws {
        try await withInvocationHost { host in
            let request = try ServiceInvocationRequest(
                grantID   : host.acquisition.grant.id,
                invocation: host.invocation()
            )
            let raw        = try ServiceFrameCodec.encode(request, profile: .v1_3)
            var object     = try #require(JSONSerialization.jsonObject(with: raw) as? [String: Any])
            var invocation = try #require(object["invocation"] as? [String: Any])
            invocation["payload"] = Data(repeating: 0, count: 65_537).base64EncodedString()
            object["invocation"] = invocation
            let oversized = try JSONSerialization.data(withJSONObject: object)
            let input     = try #require(
                host.adapter.stage(oversized, connection: host.consumer, sequence: 1, kind: .invocation)
            )
            #expect(
                await host.runtime.receiveServiceRequest(input, connection: host.consumer) == .refused(.invalidPayload)
            )
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            let id       = try await host.begin(sequence: 2)
            let tooLarge = try #require(
                host.adapter.stage(
                    Data(repeating: 32, count: 196_609),
                    connection: host.provider,
                    sequence  : 1,
                    kind      : .completion
                )
            )
            await #expect(throws: AddonFailure.self) {
                _ = try await host.runtime.receiveServiceCompletionOutput(tooLarge, connection: host.provider)
            }

            let completionRaw    = try host.completionBytes(requestID: id)
            var completionObject = try #require(JSONSerialization.jsonObject(with: completionRaw) as? [String: Any])
            var completion       = try #require(completionObject["completion"] as? [String: Any])
            var service          = try #require(completion["service"] as? [String: Any])
            var response         = try #require(service["response"] as? [String: Any])
            response["payload"] = Data(repeating: 0, count: 65_537).base64EncodedString()
            service["response"] = response
            completion["service"] = service
            completionObject["completion"] = completion
            let invalid = try #require(
                host.adapter.stage(
                    try JSONSerialization.data(withJSONObject: completionObject),
                    connection: host.provider,
                    sequence  : 1,
                    kind      : .completion
                )
            )
            await #expect(throws: AddonFailure.self) {
                _ = try await host.runtime.receiveServiceCompletionOutput(invalid, connection: host.provider)
            }

            #expect(host.replyDelivery == nil)
            try await host.complete(id)
            #expect(host.replyDelivery != nil)
        }
    }

    @Test(arguments: [false, true])
    func sdkUsesActualFourLegHostAndRejectedReplyIsUnknown(rejectReply: Bool) async throws {
        try await withInvocationHost { host in
            let channel  = InvocationRuntimeByteChannel(host: host)
            let executor = try ServiceInvocationExchange(channel: channel)
            let request  = try host.invocation(bytes: 65_536)
            let work     = Task { try await executor.invoke(grantID: host.acquisition.grant.id, invocation: request) }
            do {
                await host.adapter.providerEvent.wait()
                let invocation = try #require(host.providerDelivery)
                #expect(
                    try ServiceFrameCodec.decodeProviderFrame(invocation.payload, profile: .v1_3)
                        == .invocation(request)
                )
                #expect(await host.runtime.receiveServiceReceipt(invocation.receipt, connection: host.provider))
                host.adapter.rejectReplyHandoff = rejectReply
                try await host.complete(request.requestID, bytes: 65_536)
                if rejectReply {
                    do {
                        _ = try await work.value
                        Issue.record("Expected local unknown")
                    } catch { #expect((error as? AddonFailure)?.code == .outcomeUnknown) }
                } else {
                    let result = try await work.value
                    #expect(result == .completed(try host.response(bytes: 65_536)))
                }
            } catch {
                await executor.close()
                _ = try? await work.value
                throw error
            }

            await executor.close()
        }
    }

    @Test(arguments: [0, 65_536])
    func fourRawLegsAndProviderPayloadReceiptBeforeCompletion(bytes: Int) async throws {
        try await withInvocationHost { host in
            let request = try ServiceInvocationRequest(
                grantID   : host.acquisition.grant.id,
                invocation: host.invocation(bytes: bytes)
            )
            let raw = try ServiceFrameCodec.encode(request, profile: .v1_3)
            if bytes == 65_536 { #expect(raw.count > 131_072) }
            let ingress = try #require(
                host.adapter.stage(raw, connection: host.consumer, sequence: 1, kind: .invocation)
            )
            guard case .admitted = await host.runtime.receiveServiceRequest(
                ingress,
                connection: host.consumer
            ) else {
                Issue.record("No service route admitted")
                return
            }

            let dispatched = try #require(host.providerDelivery)
            if bytes == 65_536 { #expect(dispatched.payload.count > 131_072) }
            #expect(
                try ServiceFrameCodec.decodeProviderFrame(dispatched.payload, profile: .v1_3)
                    == .invocation(request.invocation)
            )
            #expect(await host.runtime.receiveServiceReceipt(dispatched.receipt, connection: host.provider))
            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 1)
            let completionRaw = try host.completionBytes(
                requestID: request.invocation.requestID,
                bytes    : bytes,
                padding  : 17
            )
            if bytes == 65_536 { #expect(completionRaw.count > 131_072) }
            let completion = try #require(
                host.adapter.stage(completionRaw, connection: host.provider, sequence: 1, kind: .completion)
            )
            guard case .committed = try await host.runtime.receiveServiceCompletionOutput(
                completion,
                connection: host.provider
            ) else {
                Issue.record("Completion did not commit")
                return
            }

            let replyDelivery = try #require(host.replyDelivery)
            if bytes == 65_536 { #expect(replyDelivery.payload.count > 131_072) }
            let reply = try ServiceFrameCodec.decodeInvocationReply(replyDelivery.payload, profile: .v1_3)
            try reply.validate(matching: request)
            #expect(reply.result == .completed(try host.response(bytes: bytes)))
            #expect(await host.runtime.receiveServiceReceipt(replyDelivery.receipt, connection: host.consumer))
            #expect(await host.runtime.receiveServiceReceipt(replyDelivery.receipt, connection: host.consumer) == false)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == 0)
            let generic = try JSONEncoder().encode(AddonEvent.serviceRequest(request.invocation))
            if bytes == 65_536 { #expect(throws: AddonFailure.self) { _ = try AddonEvent.decode(generic) } }
        }
    }

    @Test
    func originalRawCountMismatchAndCapsDoNotConsumeCommand() async throws {
        try await withInvocationHost { host in
            let request = try ServiceInvocationRequest(
                grantID   : host.acquisition.grant.id,
                invocation: host.invocation()
            )
            let raw   = try ServiceFrameCodec.encode(request, profile: .v1_3)
            let wrong = try #require(
                host.adapter.stage(
                    raw,
                    connection     : host.consumer,
                    sequence       : 1,
                    kind           : .invocation,
                    advertisedBytes: raw.count + 1
                )
            )
            #expect(
                await host.runtime.receiveServiceRequest(wrong, connection: host.consumer) == .refused(.invalidPayload)
            )
            let tooLarge = try #require(
                host.adapter.stage(
                    Data(repeating: 32, count: 196_609),
                    connection: host.consumer,
                    sequence  : 2,
                    kind      : .invocation
                )
            )
            #expect(
                await host.runtime.receiveServiceRequest(tooLarge, connection: host.consumer)
                    == .refused(.invalidPayload)
            )
            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            let id       = try await host.begin(sequence: 3)
            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            let output   = try host.completionBytes(requestID: id)
            let mismatch = try #require(
                host.adapter.stage(
                    output,
                    connection     : host.provider,
                    sequence       : 1,
                    kind           : .completion,
                    advertisedBytes: output.count + 1
                )
            )
            await #expect(throws: AddonFailure.self) {
                _ = try await host.runtime.receiveServiceCompletionOutput(mismatch, connection: host.provider)
            }

            let valid = try #require(
                host.adapter.stage(output, connection: host.provider, sequence: 1, kind: .completion)
            )
            _ = try await host.runtime.receiveServiceCompletionOutput(valid, connection: host.provider)
            #expect(host.replyDelivery != nil)
        }
    }

    @Test
    func exactKindsAndNoncesDoNotFreeOtherFamiliesOrJobs() async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let delivery = try #require(host.providerDelivery)
            let original = delivery.receipt
            let bad      = [
                RuntimeServiceReceipt(
                    token          : UUID(),
                    incarnation    : original.incarnation,
                    connectionToken: original.connectionToken,
                    sequence       : original.sequence,
                    requestID      : original.requestID,
                    kind           : original.kind
                ),
                RuntimeServiceReceipt(
                    token          : original.token,
                    incarnation    : RuntimeIncarnation(),
                    connectionToken: original.connectionToken,
                    sequence       : original.sequence,
                    requestID      : original.requestID,
                    kind           : original.kind
                ),
                RuntimeServiceReceipt(
                    token          : original.token,
                    incarnation    : original.incarnation,
                    connectionToken: UUID(),
                    sequence       : original.sequence,
                    requestID      : original.requestID,
                    kind           : original.kind
                ),
                RuntimeServiceReceipt(
                    token          : original.token,
                    incarnation    : original.incarnation,
                    connectionToken: original.connectionToken,
                    sequence       : 2,
                    requestID      : original.requestID,
                    kind           : original.kind
                ),
                RuntimeServiceReceipt(
                    token          : original.token,
                    incarnation    : original.incarnation,
                    connectionToken: original.connectionToken,
                    sequence       : original.sequence,
                    requestID      : UUID(),
                    kind           : original.kind
                ),
                RuntimeServiceReceipt(
                    token          : original.token,
                    incarnation    : original.incarnation,
                    connectionToken: original.connectionToken,
                    sequence       : original.sequence,
                    requestID      : original.requestID,
                    kind           : .consumerReply
                ),
                RuntimeServiceReceipt(
                    token          : original.token,
                    incarnation    : original.incarnation,
                    connectionToken: original.connectionToken,
                    sequence       : original.sequence,
                    requestID      : original.requestID,
                    kind           : .providerInvocation(workID: UUID())
                )
            ]
            for receipt in bad {
                #expect(await host.runtime.receiveServiceReceipt(receipt, connection: host.provider) == false)
            }

            #expect(
                await host.runtime.receiveStorageReceipt(
                    RuntimeStorageReceipt(
                        token          : original.token,
                        incarnation    : original.incarnation,
                        connectionToken: original.connectionToken,
                        sequence       : original.sequence,
                        requestID      : original.requestID,
                        operation      : .read
                    ),
                    connection: host.provider
                ) == false
            )
            #expect(
                await host.runtime.receiveAssetReceipt(
                    RuntimeAssetReceipt(
                        token          : original.token,
                        incarnation    : original.incarnation,
                        connectionToken: original.connectionToken,
                        sequence       : original.sequence,
                        requestID      : original.requestID,
                        operation      : .abort
                    ),
                    connection: host.provider
                ) == false
            )
            #expect(host.providerDelivery == delivery)
            #expect(await host.runtime.receiveServiceReceipt(original, connection: host.provider))
            #expect(await host.runtime.receiveServiceReceipt(original, connection: host.provider) == false)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
            try await host.complete(id)
            #expect(host.replyDelivery != nil)
        }
    }

    @Test
    func heldAdmissionDefersCommitThenActualFinishDeliversOnce() async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            try await host.withHeldAdmission {
                let raw     = try host.completionBytes(requestID: id)
                let ingress = try #require(
                    host.adapter.stage(raw, connection: host.provider, sequence: 1, kind: .completion)
                )
                #expect(
                    try await host.runtime.receiveServiceCompletionOutput(
                        ingress,
                        connection: host.provider
                    ) == .pendingServiceCompletion
                )
                #expect(host.replyDelivery == nil)
                #expect(await host.governor.usage(.commands, owner: host.owner) == 1)
            }

            let reply = try #require(host.replyDelivery)
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer))
            #expect(host.replyDelivery == nil)
        }
    }

    @Test(arguments: [false, true])
    func deferredRevocationOrExpiryPhysicallySettlesWithoutKnownReply(expire: Bool) async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let provider = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(provider.receipt, connection: host.provider))
            try await host.withHeldAdmission(expectRevoked: !expire) {
                let raw     = try host.completionBytes(requestID: id)
                let ingress = try #require(
                    host.adapter.stage(raw, connection: host.provider, sequence: 1, kind: .completion)
                )
                #expect(
                    try await host.runtime.receiveServiceCompletionOutput(
                        ingress,
                        connection: host.provider
                    ) == .pendingServiceCompletion
                )
                if expire {
                    host.clock.advance(31)
                } else {
                    await host.runtime.disable(owner: host.owner)
                }
            }

            if expire, let unknown = host.replyDelivery {
                #expect(
                    try ServiceFrameCodec.decodeInvocationReply(
                        unknown.payload,
                        profile: .v1_3
                    ).result == .outcomeUnknown
                )
                #expect(await host.runtime.receiveServiceReceipt(unknown.receipt, connection: host.consumer))
            } else { #expect(host.adapter.settled.count == 1) }
            #expect(host.replyDelivery == nil)
            // A timely received canonical completion can commit after the clock moves;
            // disclosure still expires. Revoked unresolved work stays charged until exit.
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == (expire ? 0 : 1))
            #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
        }
    }

    @Test
    func rejectedDispatchAndDuplicateRetainedIDKeepExactRefusal() async throws {
        try await withInvocationHost { host in
            host.adapter.rejectProviderHandoff = true
            let requestID = try await host.begin()
            let delivery  = try #require(host.replyDelivery)
            let reply     = try ServiceFrameCodec.decodeInvocationReply(delivery.payload, profile: .v1_3)
            guard case .refused(let code, _) = reply.result else {
                Issue.record("Expected refused")
                return
            }

            #expect(code == .dependencyUnavailable)
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.consumer))
            host.adapter.rejectProviderHandoff = false
            _ = try await host.begin(sequence: 2, requestID: requestID)
            let replay = try #require(host.replyDelivery)
            guard case .refused(let replayCode, _) = try ServiceFrameCodec.decodeInvocationReply(
                replay.payload,
                profile: .v1_3
            ).result else {
                Issue.record("Expected replay refusal")
                return
            }

            #expect(replayCode == .invalidPayload)
            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
        }
    }

    @Test
    func rejectedReplySettlesWhileAuthorizedCommittedHistorySurvives() async throws {
        try await withInvocationHost { host in
            let id       = try await host.begin()
            let delivery = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.provider))
            host.adapter.rejectReplyHandoff = true
            try await host.complete(id)
            #expect(host.replyDelivery == nil)
            #expect(host.adapter.settled.count == 1)
            #expect(
                try await host.runtime.serviceOutcome(
                    connection: host.consumer,
                    grantID   : host.acquisition.grant.id,
                    requestID : id
                )
                    == .completed(try host.response())
            )
        }
    }

    @Test
    func paidWorkspacePressureRefusesBeforeRetention() async throws {
        try await withInvocationHost { host in
            let pressure = try await host.governor.admit(
                .temporaryMemory(bytes: 60 * 1_024 * 1_024 - 8 * 1_024 * 1_024),
                owner: host.owner
            )
            do {
                let request = try ServiceInvocationRequest(
                    grantID   : host.acquisition.grant.id,
                    invocation: host.invocation()
                )
                let ingress = try #require(
                    host.adapter.stage(
                        try ServiceFrameCodec.encode(request, profile: .v1_3),
                        connection: host.consumer,
                        sequence  : 1,
                        kind      : .invocation
                    )
                )
                #expect(
                    await host.runtime.receiveServiceRequest(ingress, connection: host.consumer)
                        == .refused(.resourceDenied)
                )
                #expect(host.providerDelivery == nil)
                #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
            } catch {
                try? await host.governor.release(pressure.id, owner: host.owner)
                throw error
            }

            try await host.governor.release(pressure.id, owner: host.owner)
        }
    }

    @Test
    func completeAssemblyNegotiatesServiceAndComposesGeneration() async throws {
        try await withInvocationHost { host in
            #expect(host.consumer.publicationConnection.negotiatedProtocol.minor == 3)
            #expect(host.acquisition.grant.generation == host.consumer.publicationConnection.generation)
        }
    }
}

/// withInvocationHost keeps fixture allocations (including all four raw representations and
/// SDK return buffers) in a protected canonical governor scope through joined work and
/// modeled exits.
func withInvocationHost(
    minor               : Int = 3,
    maximumEnvelopeBytes: Int = 524_288,
    providerMinor       : Int? = nil,
    dependency          : Bool = false,
    maximumMetadata     : Bool = false,
    secondConsumer      : Bool = false,
    _ body              : @Sendable (InvocationMessageHost) async throws -> Void
) async throws {
    let governor = ResourceGovernor()
    let owner    = try #require(AddonID(rawValue: "com.example.consumer"))
    try await governor.withAssetDecodeReservation(bytes: 8 * 1_024 * 1_024, owner: owner) {
        let host = try await InvocationMessageHost.make(
            governor            : governor,
            minor               : minor,
            maximumEnvelopeBytes: maximumEnvelopeBytes,
            providerMinor       : providerMinor,
            dependency          : dependency,
            maximumMetadata     : maximumMetadata,
            secondConsumer      : secondConsumer
        )
        do {
            try await body(host)
        } catch {
            await host.cleanup()
            throw error
        }

        await host.cleanup()
    }
    // Keyed backend retains its 16 KiB canonical control allocation across logical close.
    let remainingMemory = await governor.usage(.admittedMemoryBytes, owner: owner)
    #expect(remainingMemory == 16_384, "Remaining memory: \(remainingMemory)")
}
