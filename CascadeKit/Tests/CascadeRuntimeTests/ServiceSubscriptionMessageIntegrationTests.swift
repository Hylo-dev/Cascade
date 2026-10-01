//
//  ServiceSubscriptionMessageIntegrationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ServiceSubscriptionMessageIntegrationTests {
    @Test(arguments: ["disable", "expiry"], [false, true])
    func disconnectedSharedInterestRecoversAfterStarterAuthorityIsRemoved(removal: String, handed: Bool) async throws {
        try await withInvocationHost(minor: 4, secondConsumer: true) { host in
            // The second interest must outlive the original without extending either.
            if removal == "expiry" { host.clock.advance(3_599) }
            await host.runtime.observeExit(host.provider.incarnation)
            let secondLaunch = try await host.runtime.requestLaunch(owner: host.leaf)
            let second = try await host.runtime.attach(launchID: secondLaunch, offer: InvocationMessageHost.offer(4))
            _ = try await host.runtime.authorizeService(connection: second, requirementID: host.contractID,
                scope: host.acquisition.grant.scope, partition: "TEST-ONLY.account", crossPublisherConsent: true)
            let secondExpiry = host.clock.now().wall.addingTimeInterval(3_600)
            let action = OperationRequest.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)
            let firstRequest = try ServiceControlRequest(requestID: UUID(), action: .acquire(action))
            let firstInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(firstRequest, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(firstInput, connection: host.consumer),
                  case .serviceControl(let firstAck) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No starter admission"); return }
            let providerLaunch = try #require(host.adapter.starts.last { $0.identity == host.provider.identity })
            let secondRequest = try ServiceControlRequest(requestID: UUID(), action: .acquire(action))
            let secondInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(secondRequest, profile: .v1_4), connection: second, sequence: 1, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(secondInput, connection: second),
                  case .serviceControl(let secondAck) = host.adapter.payload(second.incarnation) else { Issue.record("No shared admission"); return }
            var runningProvider: RuntimeConnection?
            var activeStart: ServiceSourceStartFrame?
            if handed {
                let provider = try await host.runtime.attach(launchID: providerLaunch.launchID, offer: InvocationMessageHost.offer(4))
                runningProvider = provider
                guard case .serviceSourceStart(let delivery) = host.adapter.payload(provider.incarnation) else { Issue.record("No initial shared source start"); return }
                let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(delivery.payload, profile: .v1_4)
                activeStart = start
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: provider))
                let complete = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
                let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(complete, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
                #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .accepted)
                #expect(await host.governor.usage(.jobs) == 0)
            }
            await host.runtime.closeConnection(second)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(secondAck.receipt, connection: second) == false)
            if removal == "disable" {
                await host.runtime.disable(owner: host.owner)
                await #expect(throws: AddonFailure.self) { try await host.runtime.requestLaunch(owner: host.owner) }
            } else {
                host.clock.advance(1)
                _ = try await host.runtime.serviceDeadlines()
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(firstAck.receipt, connection: host.consumer))
                guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No expired starter terminal"); return }
                #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .outcomeUnknown)
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
                let stale = try await host.control(ServiceControlRequest(requestID: UUID(), action: .subscribe(requirementID: host.contractID, grantID: host.acquisition.grant.id)), sequence: 3)
                guard case .refused = stale.result else { Issue.record("Expired starter authority revived"); return }
            }
            #expect(await host.governor.usage(.providers) == 3)
            let provider: RuntimeConnection
            if let runningProvider { provider = runningProvider }
            else { provider = try await host.runtime.attach(launchID: providerLaunch.launchID, offer: InvocationMessageHost.offer(4)) }
            #expect(host.adapter.payload(provider.incarnation) == nil)
            await host.runtime.observeExit(second.incarnation)
            let reconnectLaunch = try await host.runtime.requestLaunch(owner: host.leaf)
            let reconnected = try await host.runtime.attach(launchID: reconnectLaunch, offer: InvocationMessageHost.offer(4))
            #expect(reconnected.token != second.token)
            let launchCount = host.adapter.starts.count
            let recovery = try ServiceControlRequest(requestID: UUID(), action: .acquire(action))
            let recoveryInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(recovery, profile: .v1_4), connection: reconnected, sequence: 1, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(recoveryInput, connection: reconnected),
                  case .serviceControl(let ack) = host.adapter.payload(reconnected.incarnation) else { Issue.record("No first recovery admission"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(ack.payload, profile: .v1_4).result == .accepted)
            if handed {
                #expect(host.adapter.payload(provider.incarnation) == nil, "Already handed startup must not be reset by stale starter cleanup")
                #expect(await host.governor.usage(.jobs) == 0)
            } else {
                guard case .serviceSourceStart(let delivery) = host.adapter.payload(provider.incarnation) else {
                    Issue.record("First explicit recovery stranded the surviving shared interest while provider remained alive"); return
                }
                let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(delivery.payload, profile: .v1_4)
                activeStart = start
                #expect(start.sourceID == host.acquisition.sourceID && start.startNonce != host.sourceStart?.startNonce)
                #expect(host.adapter.starts.count == launchCount)
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: provider))
                let complete = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
                let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(complete, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
                #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .accepted)
            }
            #expect(host.adapter.starts.count == launchCount)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: reconnected))
            guard case .serviceControl(let terminal) = host.adapter.payload(reconnected.incarnation),
                  case .acquired(let grant) = try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result else { Issue.record("First recovery not ready"); return }
            #expect(grant.owner == host.leaf && grant.expiresAt == secondExpiry)
            #expect(grant.id != host.acquisition.grant.id && grant.generation == reconnected.publicationConnection.generation)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: reconnected))
            let exactStart = try #require(activeStart)
            let update = try ServiceSourceOutputFrame(sourceID: exactStart.sourceID, startNonce: exactStart.startNonce,
                output: .sourceUpdate(host.response(bytes: 7)))
            let updateInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(update, profile: .v1_4), connection: provider, sequence: 2, kind: .sourceOutput))
            #expect(await host.runtime.receiveServiceSourceOutput(updateInput, connection: provider) == .accepted,
                    "Persistent canonical authority must survive stale starter cleanup")
            if removal == "disable" {
                await #expect(throws: AddonFailure.self) { try await host.runtime.requestLaunch(owner: host.owner) }
            }
            #expect(await host.governor.usage(.jobs) == 0)
            #expect(await host.governor.usage(.providers) == 3)
        }
    }

    @Test func revokedStarterDispositionPreservesDisconnectedCanonicalInterest() async throws {
        let fixture = BrokerFixture()
        let governor = ResourceGovernor()
        let broker = ServiceBroker(governor: governor)
        let firstPermission = try await broker.authorize(fixture.permission())
        _ = try await broker.authorize(fixture.permission(fixture.other))
        let firstSession = try await broker.registerSession(identity: fixture.owner)
        let secondSession = try await broker.registerSession(identity: fixture.other)
        let scope = try ServiceScope(featureID: "main", operation: "read")
        let first = try await broker.acquire(session: firstSession, requirementID: "requirement", scope: scope, now: fixture.now, lifetime: .seconds(60))
        let second = try await broker.acquire(session: secondSession, requirementID: "requirement", scope: scope, now: fixture.now, lifetime: .seconds(120))
        #expect(first.sourceID == second.sourceID && second.decisions.isEmpty)
        await broker.disconnect(secondSession)
        #expect(await broker.revoke(permissionID: firstPermission).isEmpty)
        #expect(await broker.abandonUnhandedAcquisition(first, startTransferred: false))
        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(session: firstSession, requirementID: "requirement", scope: scope, now: fixture.now, lifetime: .seconds(60))
        }
        let reconnect = try await broker.registerSession(identity: fixture.other)
        let recovered = try await broker.acquire(session: reconnect, requirementID: "requirement", scope: scope, now: fixture.now, lifetime: .seconds(3_600))
        #expect(recovered.interestID == second.interestID && recovered.sourceID == second.sourceID)
        #expect(recovered.grant.expiresAt == second.grant.expiresAt && recovered.grant.id != second.grant.id)
        #expect(recovered.decisions == [.startSource(second.sourceID)])
        _ = try await broker.consumeSourceStart(recovered.sourceID, now: fixture.now)
        _ = await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test(arguments: [false, true], [false, true])
    func cachedEventPreparationRevalidatesAfterPaidWorkspaceAndCanonicalRead(afterBinding: Bool, expire: Bool) async throws {
        try await withInvocationHost(minor: 4) { host in
            _ = try await host.subscribe(sequence: 2)
            #expect(try await host.update(bytes: 13, sequence: 2) == .accepted)
            let first = try #require(host.eventDelivery)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(first.receipt, connection: host.consumer))
            let before = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
            let gate = SubscriptionPreparationGate()
            let publishing = Task {
                do {
                    let result = try await AddonRuntime.$serviceSubscriptionObserver.withValue({ point in
                        if point == (afterBinding ? .eventBindingRead : .eventWorkspaceReady) { await gate.pause() }
                    }) { try await host.update(bytes: 23, sequence: 3) }
                    await gate.release()
                    return result
                } catch { await gate.release(); throw error }
            }
            await gate.wait()
            #expect(await gate.arrived)
            #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) >= before + 8 * 1_024 * 1_024)
            #expect(host.eventDelivery == nil)
            if expire { host.clock.advance(3_601) }
            else { await host.runtime.disable(owner: host.owner) }
            await gate.release()
            #expect(try await publishing.value == .accepted) // Cache update preceded the held delivery preparation.
            #expect(host.eventDelivery == nil)
            #expect(await host.runtime.diagnostics(owner: host.owner)?.hasOutstandingDelivery == false)
            #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) <= before)
            _ = try await host.runtime.serviceDeadlines()
            #expect(host.eventDelivery == nil)
            if expire {
                let reply = try await host.control(ServiceControlRequest(requestID: UUID(), action: .subscribe(requirementID: host.contractID, grantID: host.acquisition.grant.id)), sequence: 3)
                guard case .refused = reply.result else { Issue.record("Expired cache authority resurrected"); return }
            }
        }
    }

    @Test func abandonedStarterTransfersToLiveSharedInterestWithoutReleasingProcesses() async throws {
        try await withInvocationHost(minor: 4, secondConsumer: true) { host in
            await host.runtime.observeExit(host.provider.incarnation)
            let secondLaunch = try await host.runtime.requestLaunch(owner: host.leaf)
            let second = try await host.runtime.attach(launchID: secondLaunch, offer: InvocationMessageHost.offer(4))
            _ = try await host.runtime.authorizeService(connection: second, requirementID: host.contractID,
                scope: host.acquisition.grant.scope, partition: "TEST-ONLY.account", crossPublisherConsent: true)
            let action = OperationRequest.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)
            let firstRequest = try ServiceControlRequest(requestID: UUID(), action: .acquire(action))
            let firstInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(firstRequest, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(firstInput, connection: host.consumer),
                  case .serviceControl(let firstAck) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("First interest missing"); return }
            let providerLaunch = try #require(host.adapter.starts.last { $0.identity == host.provider.identity })
            let secondRequest = try ServiceControlRequest(requestID: UUID(), action: .acquire(action))
            let secondInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(secondRequest, profile: .v1_4), connection: second, sequence: 1, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(secondInput, connection: second),
                  case .serviceControl(let secondAck) = host.adapter.payload(second.incarnation) else { Issue.record("Shared interest missing"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(secondAck.payload, profile: .v1_4).result == .accepted)
            await host.runtime.closeConnection(host.consumer)
            #expect(await host.governor.usage(.providers) == 3)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(firstAck.receipt, connection: host.consumer) == false)
            let provider = try await host.runtime.attach(launchID: providerLaunch.launchID, offer: InvocationMessageHost.offer(4))
            guard case .serviceSourceStart(let source) = host.adapter.payload(provider.incarnation) else { Issue.record("Pending start was not transferred"); return }
            let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(source.payload, profile: .v1_4)
            #expect(start.sourceID == host.acquisition.sourceID && start.startNonce != host.sourceStart?.startNonce)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(source.receipt, connection: provider))
            let complete = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
            let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(complete, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
            #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(secondAck.receipt, connection: second))
            guard case .serviceControl(let terminal) = host.adapter.payload(second.incarnation),
                  case .acquired(let grant) = try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result else { Issue.record("Other live grant was invalidated"); return }
            #expect(grant.owner == host.leaf && grant.expiresAt == host.acquisition.grant.expiresAt)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: second))
            #expect(await host.governor.usage(.providers) == 3)
            #expect(await host.governor.usage(.jobs) == 0)
        }
    }

    @Test(arguments: ["rejectedAck", "expiredAfterCommit"])
    func abandonedColdIntentRecoversOnFirstExplicitAttempt(schedule: String) async throws {
        try await withInvocationHost(minor: 4) { host in
            await host.runtime.observeExit(host.provider.incarnation)
            let starts = host.adapter.starts.count
            let operation = OperationRequest.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)
            let first = try ServiceControlRequest(requestID: UUID(), action: .acquire(operation))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(first, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            host.adapter.rejectControlHandoff = schedule == "rejectedAck"
            let admission = await AddonRuntime.$serviceSubscriptionObserver.withValue({ point in
                if schedule == "expiredAfterCommit", point == .acquisitionCommitted { host.clock.advance(31) }
            }) { await host.runtime.receiveServiceControl(ingress, connection: host.consumer) }
            guard case .admitted = admission else { Issue.record("Intent did not commit"); return }
            host.adapter.rejectControlHandoff = false
            if schedule == "rejectedAck" {
                #expect(host.adapter.settled.count == 1)
                #expect(host.adapter.payload(host.consumer.incarnation) == nil)
            } else {
                guard case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("Missing admission"); return }
                #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(ack.payload, profile: .v1_4).result == .accepted)
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
                guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("Missing unknown"); return }
                #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .outcomeUnknown)
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
            }
            #expect(host.adapter.starts.count == starts)
            #expect(await host.governor.usage(.providers) == 1)
            let recovery = try ServiceControlRequest(requestID: UUID(), action: .acquire(operation))
            let retry = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(recovery, profile: .v1_4), connection: host.consumer, sequence: 3, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(retry, connection: host.consumer),
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No recovery admission"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(ack.payload, profile: .v1_4).result == .accepted)
            guard host.adapter.starts.count == starts + 1 else { Issue.record("First recovery did not start; a sacrificial timeout would be required"); return }
            let launch = try #require(host.adapter.starts.last { $0.identity == host.provider.identity })
            let provider = try await host.runtime.attach(launchID: launch.launchID, offer: InvocationMessageHost.offer(4))
            guard case .serviceSourceStart(let source) = host.adapter.payload(provider.incarnation) else { Issue.record("No recovered source start"); return }
            let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(source.payload, profile: .v1_4)
            #expect(start.sourceID == host.acquisition.sourceID && start.startNonce != host.sourceStart?.startNonce)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(source.receipt, connection: provider))
            let complete = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
            let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(complete, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
            #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation),
                  case .acquired(let grant) = try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result else { Issue.record("First explicit recovery never became ready"); return }
            #expect(grant.id != host.acquisition.grant.id && grant.expiresAt == host.acquisition.grant.expiresAt)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
        }
    }

    @Test(arguments: ["close", "disable", "reconcile", "decision"])
    func heldSourceReceiptRetiresWithItsPayingRowBeforeProcessExit(stop: String) async throws {
        try await withInvocationHost(minor: 4) { host in
            await host.runtime.observeExit(host.provider.incarnation)
            let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer),
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No admission"); return }
            let launch = try #require(host.adapter.starts.last { $0.identity == host.provider.identity })
            let provider = try await host.runtime.attach(launchID: launch.launchID, offer: InvocationMessageHost.offer(4))
            guard case .serviceSourceStart(let source) = host.adapter.payload(provider.incarnation) else { Issue.record("No start receipt"); return }
            let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(source.payload, profile: .v1_4)
            let complete = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
            let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(complete, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
            #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .accepted)
            #expect(await host.governor.usage(.jobs) == 0)
            #expect(await host.runtime.diagnostics(owner: provider.identity.addonID)?.hasOutstandingDelivery == true)
            let before = await host.governor.usage(.retainedStateBytes, owner: provider.identity.addonID)
            switch stop {
            case "close": await host.runtime.closeConnection(provider)
            case "disable": await host.runtime.disable(owner: provider.identity.addonID)
            case "reconcile": await host.runtime.disable(owner: host.owner)
            default:
                // Settle the finite control, leaving the source's exact receipt held.
                host.clock.advance(31)
                _ = try await host.runtime.serviceDeadlines()
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
                guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No expired control"); return }
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
                // Existing internal canonical acquisition can supply a grant independently
                // of public 1.4 readiness; no invented grant or test broker is injected.
                let canonical = try await host.runtime.acquireService(connection: host.consumer, permissionID: host.permissionID, lifetime: .seconds(3_600))
                let alias = try await host.subscribe(grant: canonical.grant, sequence: 3)
                let reply = try await host.control(ServiceControlRequest(requestID: UUID(), action: .unsubscribe(subscriptionID: alias)), sequence: 4)
                #expect(reply.result == .acknowledged)
            }
            #expect(host.adapter.payload(provider.incarnation) == nil)
            #expect(await host.runtime.diagnostics(owner: provider.identity.addonID)?.hasOutstandingDelivery == false)
            #expect(await host.governor.usage(.retainedStateBytes, owner: provider.identity.addonID) <= before - RuntimeServiceSourceBinding.bytes)
            #expect(await host.governor.usage(.providers) == 2)
            #expect(await host.governor.usage(.jobs) == 0)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(source.receipt, connection: provider) == false)
        }
    }

    // Missing actual cold acquisition, phase receipts, persistent startup or common
    // generation breaks this fixture before any public subscription can run.
    @Test func completeHostNegotiatesSubscriptions() async throws {
        try await withInvocationHost(minor: 4) { host in
            #expect(host.consumer.publicationConnection.negotiatedProtocol.minor == 4)
            #expect(host.provider.publicationConnection.negotiatedProtocol.minor == 4)
            #expect(host.acquisition.grant.generation == host.consumer.publicationConnection.generation)
            #expect(await host.governor.usage(.jobs) == 0)
        }
    }

    @Test func missingScopeAndForeignAliasRefuseBeforeEffects() async throws {
        try await withInvocationHost(minor: 4) { host in
            let before = await host.governor.usage(.providers)
            let missing = try ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID,
                scope: ServiceScope(featureID: "summary", operation: "write"))))
            let reply = try await host.control(missing, sequence: 2)
            guard case .refused(let code, _) = reply.result else { Issue.record("Unowned scope admitted"); return }
            #expect(code == .permissionDenied)
            let wrong = try await host.control(ServiceControlRequest(requestID: UUID(), action: .unsubscribe(subscriptionID: UUID())), sequence: 3)
            guard case .refused(let aliasCode, _) = wrong.result else { Issue.record("Unknown alias adopted"); return }
            #expect(aliasCode == .permissionDenied)
            #expect(await host.governor.usage(.providers) == before)
        }
    }

    @Test func repeatedSubscribeRefreshesOneAliasAndUnsubscribeInvalidatesAllGrants() async throws {
        try await withInvocationHost(minor: 4) { host in
            let alias = try await host.subscribe(sequence: 2)
            #expect(try await host.subscribe(sequence: 3) == alias)
            let acquired = try await host.control(ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID,
                scope: host.acquisition.grant.scope))), sequence: 4)
            guard case .acquired(let fresh) = acquired.result else { Issue.record("No fresh canonical grant"); return }
            #expect(fresh.id != host.acquisition.grant.id)
            #expect(fresh.expiresAt == host.acquisition.grant.expiresAt)
            #expect(try await host.subscribe(grant: fresh, sequence: 5) == alias)
            #expect(await host.governor.usage(.providers) == 2)
            let work = try await host.runtime.beginServiceInvocation(connection: host.consumer, grantID: host.acquisition.grant.id, invocation: host.invocation())
            #expect(try await host.runtime.pumpServiceInvocation(work.id))
            let unsubscribed = try await host.control(ServiceControlRequest(requestID: UUID(), action: .unsubscribe(subscriptionID: alias)), sequence: 6)
            #expect(unsubscribed.result == .acknowledged)
            // Logical withdrawal does not claim provider process/job exit.
            #expect(await host.governor.usage(.providers) == 2)
            await #expect(throws: AddonFailure.self) {
                _ = try await host.runtime.serviceOutcome(connection: host.consumer, grantID: fresh.id, requestID: work.invocation.requestID)
            }
            let denied = try await host.control(ServiceControlRequest(requestID: UUID(), action: .subscribe(requirementID: host.contractID, grantID: fresh.id)), sequence: 7)
            guard case .refused = denied.result else { Issue.record("Removed interest grant resurrected"); return }
        }
    }

    @Test(arguments: [false, true])
    func fullEscapedSourcePayloadAndExactEventReceiptKeepNewerRevisionDirty(maximumMetadata: Bool) async throws {
        try await withInvocationHost(minor: 4, maximumMetadata: maximumMetadata) { host in
            let alias = try await host.subscribe(sequence: 2)
            #expect(try await host.update(bytes: 65_536, sequence: 2, escaped: true) == .accepted)
            let first = try #require(host.eventDelivery)
            let event = try ServiceSubscriptionFrameCodec.decodeServiceEvent(first.payload, profile: .v1_4)
            #expect(event.subscriptionID == alias && event.token == host.acquisition.grant)
            #expect(event.response.payload == Data(repeating: 255, count: 65_536))
            #expect(try await host.update(bytes: 17, sequence: 3) == .accepted)
            #expect(host.eventDelivery == first)
            let wrong = RuntimeServiceSubscriptionReceipt(token: first.receipt.token, incarnation: first.receipt.incarnation,
                connectionToken: first.receipt.connectionToken, sequence: first.receipt.sequence,
                kind: .control(requestID: UUID(), kind: .subscribe, phase: .terminal))
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(wrong, connection: host.consumer) == false)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(first.receipt, connection: host.consumer))
            let latest = try #require(host.eventDelivery)
            #expect(try ServiceSubscriptionFrameCodec.decodeServiceEvent(latest.payload, profile: .v1_4).response.payload.count == 17)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(first.receipt, connection: host.consumer) == false)
            #expect(host.eventDelivery == latest)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(latest.receipt, connection: host.consumer))
            #expect(host.eventDelivery == nil)
        }
    }

    @Test func latestCoalescingReplyPriorityAndParkedRawIngress() async throws {
        try await withInvocationHost(minor: 4) { host in
            let alias = try await host.subscribe(sequence: 2)
            let requestID = try await host.begin(sequence: 3)
            let delivery = try #require(host.providerDelivery)
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: host.provider))
            #expect(try await host.update(bytes: 1, sequence: 2) == .accepted)
            #expect(try await host.update(bytes: 2, sequence: 3) == .accepted)
            #expect(host.eventDelivery == nil)
            try await host.complete(requestID, sequence: 4)
            let reply = try #require(host.replyDelivery)
            #expect(host.eventDelivery == nil)
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: host.consumer))
            let owed = try #require(host.eventDelivery)
            #expect(try ServiceSubscriptionFrameCodec.decodeServiceEvent(owed.payload, profile: .v1_4).response.payload.count == 2)
            let request = try ServiceControlRequest(requestID: UUID(), action: .unsubscribe(subscriptionID: alias))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 4, kind: .control))
            let finishedBefore = host.adapter.finishedServiceIngresses(host.consumer.incarnation)
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer) else { Issue.record("No parked route"); return }
            #expect(host.adapter.hasIngress(host.consumer.incarnation))
            #expect(host.adapter.finishedServiceIngresses(host.consumer.incarnation) == finishedBefore)
            #expect(try await host.update(bytes: 3, sequence: 5) == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(owed.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("Parked request did not resume"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .acknowledged)
            #expect(host.adapter.hasIngress(host.consumer.incarnation) == false)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
            #expect(host.eventDelivery == nil)
        }
    }

    @Test func realReplacementOverlapDenialRetainsOldCache() async throws {
        try await withInvocationHost(minor: 4) { host in
            _ = try await host.subscribe(sequence: 2)
            #expect(try await host.update(bytes: 65_536, sequence: 2) == .accepted)
            let event = try #require(host.eventDelivery)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(event.receipt, connection: host.consumer))
            let used = await host.governor.usage(.retainedStateBytes)
            let pressure = try await host.governor.admit(.state(bytes: 8 * 1_024 * 1_024 - used - 1_024 - 4_096), owner: host.leaf)
            do {
                #expect(try await host.update(bytes: 65_536, sequence: 3) == .refused(.resourceDenied))
                #expect(host.eventDelivery == nil)
                try await host.governor.release(pressure.id, owner: host.leaf)
            } catch { try? await host.governor.release(pressure.id, owner: host.leaf); throw error }
            // Refresh delivery association exposes the previously paid state, not denied bytes/revision.
            _ = try await host.subscribe(sequence: 3)
            let retained = try #require(host.eventDelivery)
            #expect(try ServiceSubscriptionFrameCodec.decodeServiceEvent(retained.payload, profile: .v1_4).response.payload.count == 65_536)
            guard case .event(_, _, let revision) = retained.receipt.kind else { Issue.record("No event revision"); return }
            #expect(revision == 1)
        }
    }

    @Test(arguments: ["nonce", "source", "contract", "operation", "peer", "sequence", "count", "rawCap"])
    func sourceOutputRejectsWrongAuthorityAndRawBounds(mutation: String) async throws {
        try await withInvocationHost(minor: 4) { host in
            let start = try #require(host.sourceStart)
            let response = try ServiceResponse(schemaVersion: 1, contractID: mutation == "contract" ? "other" : host.contractID,
                                               operation: mutation == "operation" ? "other" : host.operation, payload: Data([7]))
            let output = try ServiceSourceOutputFrame(sourceID: mutation == "source" ? UUID() : start.sourceID,
                startNonce: mutation == "nonce" ? UUID() : start.startNonce, output: .sourceUpdate(response))
            var raw = try ServiceSubscriptionFrameCodec.encode(output, profile: .v1_4)
            if mutation == "rawCap" { raw.append(Data(repeating: 32, count: 196_609 - raw.count)) }
            let connection = mutation == "peer" ? host.consumer : host.provider
            let ingress = try #require(host.adapter.stage(raw, connection: connection, sequence: mutation == "sequence" ? 1 : 2, kind: .sourceOutput,
                advertisedBytes: mutation == "count" ? raw.count + 1 : nil))
            guard case .refused = await host.runtime.receiveServiceSourceOutput(ingress, connection: connection) else { Issue.record("Invalid source update accepted"); return }
            #expect(host.eventDelivery == nil)
            #expect(try await host.update(bytes: 1, sequence: 3) == .accepted)
        }
    }
}

extension InvocationMessageHost {
    var eventDelivery: RuntimeServiceSubscriptionDelivery? {
        if case .serviceEvent(let value) = adapter.payload(consumer.incarnation) { return value }; return nil
    }
    func control(_ request: ServiceControlRequest, sequence: UInt64) async throws -> ServiceControlReply {
        let ingress = try #require(adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: consumer, sequence: sequence, kind: .control))
        guard case .admitted = await runtime.receiveServiceControl(ingress, connection: consumer) else {
            throw AddonFailure(code: .invalidPayload, reason: "Control not admitted")
        }
        for _ in 0..<2 {
            guard case .serviceControl(let delivery) = adapter.payload(consumer.incarnation) else { throw AddonFailure(code: .invalidPayload, reason: "Missing control payload") }
            let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(delivery.payload, profile: .v1_4)
            try reply.validate(matching: request)
            #expect(await runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: consumer))
            if reply.phase == .terminal { return reply }
        }
        throw AddonFailure(code: .invalidPayload, reason: "Too many phases")
    }
    func subscribe(grant: Grant? = nil, sequence: UInt64) async throws -> UUID {
        let reply = try await control(ServiceControlRequest(requestID: UUID(), action: .subscribe(requirementID: contractID,
            grantID: (grant ?? acquisition.grant).id)), sequence: sequence)
        guard case .subscribed(let id) = reply.result else { throw AddonFailure(code: .invalidPayload, reason: "Subscribe refused") }
        return id
    }
    func update(bytes: Int, sequence: UInt64, escaped: Bool = false) async throws -> RuntimeServiceSourceOutputResult {
        let start = try #require(sourceStart)
        let output = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .sourceUpdate(response(bytes: bytes)))
        var raw = try ServiceSubscriptionFrameCodec.encode(output, profile: .v1_4)
        if escaped { raw = Data(String(decoding: raw, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "/", with: "\\/").utf8) }
        #expect(raw.count <= 196_608)
        let ingress = try #require(adapter.stage(raw, connection: provider, sequence: sequence, kind: .sourceOutput))
        return await runtime.receiveServiceSourceOutput(ingress, connection: provider)
    }
}

extension ServiceSubscriptionMessageIntegrationTests {
    // Canonical broker/projection evidence, deliberately not a transport fixture:
    // build metadata compares equal semantically but must remain a different source.
    @Test(arguments: ["build", "digest"])
    func canonicalBindingRetainsExactSelectedVersionAndDigest(difference: String) async throws {
        let fixture = BrokerFixture(), governor = ResourceGovernor()
        let broker = ServiceBroker(governor: governor)
        let firstVersion = try #require(SemanticVersion("1.0.0+one"))
        let secondVersion = try #require(SemanticVersion(difference == "build" ? "1.0.0+two" : "1.0.0+one"))
        #expect(firstVersion == secondVersion)
        let first = fixture.permission(version: firstVersion)
        let second = HostServicePermission(consumer: fixture.other,
            binding: ServiceBinding(requirementID: "requirement", consumer: fixture.other.addonID,
                provider: fixture.provider.addonID, providerIdentity: fixture.provider, contractVersion: secondVersion,
                digest: difference == "digest" ? "other-verified-digest" : first.binding.digest, featureID: "main"),
            serviceID: "test.service", partition: "account-a", operation: "read", crossPublisherConsent: true)
        _ = try await broker.authorize(first)
        _ = try await broker.authorize(second)
        let a = try await broker.registerSession(identity: fixture.owner)
        let b = try await broker.registerSession(identity: fixture.other)
        let scope = try ServiceScope(featureID: "main", operation: "read")
        let acquiredA = try await broker.acquire(session: a, requirementID: "requirement", scope: scope, now: fixture.now, lifetime: .seconds(30))
        let acquiredB = try await broker.acquire(session: b, requirementID: "requirement", scope: scope, now: fixture.now, lifetime: .seconds(30))
        let boundA = try await broker.bindSubscription(session: a, grantID: acquiredA.grant.id, requirementID: "requirement", now: fixture.now)
        let boundB = try await broker.bindSubscription(session: b, grantID: acquiredB.grant.id, requirementID: "requirement", now: fixture.now)
        #expect(boundA.sourceID != boundB.sourceID && boundA.key != boundB.key)
        #expect(boundA.key.version == firstVersion.description && boundB.key.version == secondVersion.description)
        #expect(try await broker.sourceBinding(sourceID: boundA.sourceID, now: fixture.now).key == boundA.key)
        #expect(try await broker.sourceBinding(sourceID: boundB.sourceID, now: fixture.now).key == boundB.key)
        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func deadlineImmediatelyAfterCanonicalCommitStillAcknowledgesIntentBeforeUnknown() async throws {
        try await withInvocationHost(minor: 4) { host in
            let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            let result = await AddonRuntime.$serviceSubscriptionObserver.withValue({ point in
                if point == .acquisitionCommitted { host.clock.advance(31) }
            }) { await host.runtime.receiveServiceControl(ingress, connection: host.consumer) }
            guard case .admitted = result, case .serviceControl(let admission) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No committed intent reply"); return }
            let ack = try ServiceSubscriptionFrameCodec.decodeControlReply(admission.payload, profile: .v1_4)
            #expect(ack.phase == .admission && ack.result == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(admission.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No terminal after ack receipt"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .outcomeUnknown)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(admission.receipt, connection: host.consumer) == false)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
        }
    }

    @Test func revokedReplacementWhileRealPoolGrowthIsHeldCannotPublish() async throws {
        try await withInvocationHost(minor: 4) { host in
            _ = try await host.subscribe(sequence: 2)
            #expect(try await host.update(bytes: 13, sequence: 2) == .accepted)
            let old = try #require(host.eventDelivery)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(old.receipt, connection: host.consumer))
            let before = await host.governor.usage(.retainedStateBytes)
            await host.resources.armResize()
            let replacement = Task {
                do {
                    let result = try await host.update(bytes: 65_536, sequence: 3)
                    await host.resources.releaseGate()
                    return result
                } catch { await host.resources.releaseGate(); throw error }
            }
            await host.resources.waitForArrival()
            #expect(await host.governor.usage(.retainedStateBytes) >= before + 65_536)
            await host.runtime.disable(owner: host.owner)
            #expect(host.eventDelivery == nil)
            await host.resources.releaseGate()
            guard case .refused = try await replacement.value else { Issue.record("Revoked preparation committed"); return }
            #expect(host.eventDelivery == nil)
            #expect(await host.governor.usage(.providers) == 2)
            #expect(await host.governor.usage(.retainedStateBytes) <= before)
        }
    }

    @Test(arguments: [false, true])
    func acceptedColdOrSourceTimeoutIsUnknownAndRetainsPhysicalCharges(attached: Bool) async throws {
        try await withInvocationHost(minor: 4) { host in
            await host.runtime.observeExit(host.provider.incarnation)
            let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer),
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No accepted intent"); return }
            let start = try #require(host.adapter.starts.last { $0.identity == host.provider.identity })
            if attached {
                let provider = try await host.runtime.attach(launchID: start.launchID, offer: InvocationMessageHost.offer(4))
                guard case .serviceSourceStart(let source) = host.adapter.payload(provider.incarnation) else { Issue.record("No source start"); return }
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(source.receipt, connection: provider))
                #expect(await host.governor.usage(.jobs) == 1)
                let descriptor = try ServiceSubscriptionFrameCodec.decodeSourceStart(source.payload, profile: .v1_4)
                let early = try ServiceSourceOutputFrame(sourceID: descriptor.sourceID, startNonce: descriptor.startNonce,
                                                        output: .sourceUpdate(host.response()))
                let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(early, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
                #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .refused(.permissionDenied))
            }
            host.clock.advance(attached ? 31 : 3)
            _ = try await host.runtime.serviceDeadlines()
            #expect(await host.governor.usage(.providers) == 2)
            #expect(await host.governor.usage(.jobs) == (attached ? 1 : 0))
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("Timeout did not settle"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .outcomeUnknown)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
            await host.runtime.observeExit(start.incarnation)
            #expect(await host.governor.usage(.providers) == 1)
            #expect(await host.governor.usage(.jobs) == 0)
        }
    }

    @Test func absentConsumerWakeRetriesOnlyOnExistingEventsAfterStartDenial() async throws {
        try await withInvocationHost(minor: 4) { host in
            _ = try await host.subscribe(sequence: 2)
            await host.runtime.closeConnection(host.consumer)
            await host.runtime.observeExit(host.consumer.incarnation)
            let starts = host.adapter.starts.count
            host.adapter.rejectStartOwners = [host.owner]
            #expect(try await host.update(bytes: 1, sequence: 2) == .accepted)
            #expect(try await host.update(bytes: 2, sequence: 3) == .accepted)
            #expect(host.adapter.starts.count == starts)
            #expect(await host.governor.usage(.providers) == 1)
            host.adapter.rejectStartOwners = []
            _ = try await host.runtime.serviceDeadlines()
            #expect(host.adapter.starts.count == starts + 1)
            #expect(await host.governor.usage(.providers) == 2)
            #expect(try await host.update(bytes: 3, sequence: 4) == .accepted)
            #expect(host.adapter.starts.count == starts + 1)
            let launch = try #require(host.adapter.starts.last { $0.identity.addonID == host.owner })
            let fresh = try await host.runtime.attach(launchID: launch.launchID, offer: InvocationMessageHost.offer(4))
            #expect(fresh.token != host.consumer.token)
            #expect(host.adapter.payload(fresh.incarnation) == nil)
        }
    }

    @Test func realPublicClientContextAndReceiptBeforeReentrantHandler() async throws {
        try await withInvocationHost(minor: 4) { host in
            #expect(try await host.update(bytes: 13, sequence: 2) == .accepted)
            // Fresh physical connection: all service acquisition/control/invocation
            // sequence values originate in this one actual SDK arbiter.
            await host.runtime.closeConnection(host.consumer)
            await host.runtime.observeExit(host.consumer.incarnation)
            let launch = try await host.runtime.requestLaunch(owner: host.owner)
            let connection = try await host.runtime.attach(launchID: launch, offer: InvocationMessageHost.offer(4))
            let channel = SubscriptionRuntimeChannel(host: host, connection: connection, providerSequence: 2)
            let box = SubscriptionHandlerBox()
            let services = try TransportServiceClient(channel: channel, owner: host.owner, handleEvent: { event in
                await box.handle(event)
            })
            let storage = try MessageAddonStorageClient(channel: InvocationRuntimeStorageChannel(host: host, connection: connection))
            let assets = MessageAddonAssetClient(channel: InvocationRuntimeAssetChannel(host: host, connection: connection))
            let context = try await services.acquireContext(operations: [.requestService(requirementID: host.contractID,
                scope: host.acquisition.grant.scope)], storage: storage, assets: assets)
            let grant = try #require(context.grants.first)
            #expect(grant.generation == connection.publicationConnection.generation)
            #expect(grant.generation != host.acquisition.grant.generation)
            #expect(grant.expiresAt == host.acquisition.grant.expiresAt)
            let alias = try await context.services.subscribe(requirementID: host.contractID, grant: grant)
            await box.waitForInitial()
            #expect(await box.payloadBytes == 13)
            let invocation = try host.invocation()
            #expect(try await context.services.invoke(invocation, grant: grant) == host.response())
            try await context.storage.write(Data([7]), key: "subscriptions")
            #expect(try await context.storage.read(key: "subscriptions") == Data([7]))
            let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGP4z8DwHx9mGBkKAMLXf4EvceABAAAAAElFTkSuQmCC"))
            let asset = try await context.assets.importAsset(png, publicationID: host.publicationID)
            #expect(asset.width == 8 && asset.height == 8)
            try await context.assets.releaseAsset(asset)
            try await box.install(context: context, invocation: host.invocation(), alias: alias)
            #expect(try await channel.update(bytes: 65_536) == .accepted)
            try await channel.consumeEvent()
            await box.wait()
            #expect(await box.payloadBytes == 65_536)
            #expect(await box.failure == nil)
            #expect(await box.finished)
            // Handler invoked and unsubscribed through the actual host after event receipt.
            #expect(channel.sequences == [1, 2, 3, 4, 5])
            #expect(await host.runtime.diagnostics(owner: host.owner)?.hasOutstandingDelivery == false)
            await services.close(); await storage.close(); await assets.close()
        }
    }
}

extension ServiceSubscriptionMessageIntegrationTests {
    @Test(arguments: [false, true])
    func parkedRawIngressIsDisposedOnCloseOrDeadline(close: Bool) async throws {
        try await withInvocationHost(minor: 4) { host in
            _ = try await host.subscribe(sequence: 2)
            #expect(try await host.update(bytes: 1, sequence: 2) == .accepted)
            let event = try #require(host.eventDelivery)
            let ingress = try #require(host.adapter.stage(Data("{}".utf8), connection: host.consumer, sequence: 3, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer) else { Issue.record("Not parked"); return }
            #expect(host.adapter.hasIngress(host.consumer.incarnation))
            if close { await host.runtime.closeConnection(host.consumer) }
            else {
                let delay = try #require(await host.runtime.nextDelay(at: host.clock.now()))
                #expect(delay <= .seconds(30))
                host.clock.advance(31)
                _ = try await host.runtime.serviceDeadlines()
            }
            #expect(host.adapter.hasIngress(host.consumer.incarnation) == false)
            #expect(host.adapter.settled.count == 1)
            if !close {
                #expect(host.eventDelivery == event)
                #expect(await host.runtime.receiveServiceSubscriptionReceipt(event.receipt, connection: host.consumer))
            }
        }
    }

    @Test func failedColdIntentRecoversAndStartupCompletionDuringAdmissionProgressesOnFinish() async throws {
        try await withInvocationHost(minor: 4) { host in
            #expect(try await host.update(bytes: 13, sequence: 2) == .accepted)
            await host.runtime.observeExit(host.provider.incarnation)
            #expect(await host.governor.usage(.providers) == 1)
            host.adapter.rejectStartOwners = [host.provider.identity.addonID]
            let operation = OperationRequest.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)
            let failed = try await host.control(ServiceControlRequest(requestID: UUID(), action: .acquire(operation)), sequence: 2)
            #expect(failed.result == .outcomeUnknown)
            #expect(await host.governor.usage(.providers) == 1)
            host.adapter.rejectStartOwners = []
            let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(operation))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 3, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer),
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No accepted recovery intent"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(ack.payload, profile: .v1_4).result == .accepted)
            let launch = try #require(host.adapter.starts.last { $0.identity == host.provider.identity })
            let provider = try await host.runtime.attach(launchID: launch.launchID, offer: InvocationMessageHost.offer(4))
            guard case .serviceSourceStart(let delivery) = host.adapter.payload(provider.incarnation) else { Issue.record("No fresh startup"); return }
            let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(delivery.payload, profile: .v1_4)
            #expect(start.sourceID == host.acquisition.sourceID)
            #expect(start.startNonce != host.sourceStart?.startNonce)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: provider))
            try await host.withHeldAdmission {
                let completed = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
                let output = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(completed, profile: .v1_4), connection: provider, sequence: 1, kind: .sourceOutput))
                #expect(await host.runtime.receiveServiceSourceOutput(output, connection: provider) == .accepted)
                #expect(host.adapter.payload(host.consumer.incarnation) == .serviceControl(ack))
            }
            // Releasing the unrelated admission is the only progress event here.
            #expect(await host.governor.usage(.jobs) == 0)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No ready result after completion/finish"); return }
            let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4)
            guard case .acquired(let fresh) = reply.result else { Issue.record("Not acquired"); return }
            #expect(fresh.id != host.acquisition.grant.id)
            #expect(fresh.expiresAt == host.acquisition.grant.expiresAt)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
            _ = try await host.subscribe(grant: fresh, sequence: 4)
            let retained = try #require(host.eventDelivery)
            let retainedEvent = try ServiceSubscriptionFrameCodec.decodeServiceEvent(retained.payload, profile: .v1_4)
            #expect(retainedEvent.token == fresh && retainedEvent.response.payload.count == 13)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(retained.receipt, connection: host.consumer))
            let obsolete = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: try #require(host.sourceStart).startNonce, output: .sourceUpdate(host.response()))
            let obsoleteIngress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(obsolete, profile: .v1_4), connection: provider, sequence: 2, kind: .sourceOutput))
            guard case .refused = await host.runtime.receiveServiceSourceOutput(obsoleteIngress, connection: provider) else { Issue.record("Old nonce authorized new incarnation"); return }
        }
    }
}

extension ServiceSubscriptionMessageIntegrationTests {
    @Test func readyAcquisitionCannotDiscloseGrantAfterPathPeerExitsBehindAdmissionAck() async throws {
        try await withInvocationHost(minor: 4, dependency: true) { host in
            let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID, scope: host.acquisition.grant.scope)))
            let ingress = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 2, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer),
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("No admission"); return }
            let leaf = try #require(host.leafConnection)
            await host.runtime.observeExit(leaf.incarnation)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else { Issue.record("Authenticated route needs unknown result"); return }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .outcomeUnknown)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
        }
    }

    @Test func malformedParkedIngressSettlesOriginalRouteWithoutAnotherEvent() async throws {
        try await withInvocationHost(minor: 4) { host in
            _ = try await host.subscribe(sequence: 2)
            #expect(try await host.update(bytes: 1, sequence: 2) == .accepted)
            let event = try #require(host.eventDelivery)
            let raw = try #require(host.adapter.stage(Data("{}".utf8), connection: host.consumer, sequence: 3, kind: .control))
            guard case .admitted(let routeID) = await host.runtime.receiveServiceControl(raw, connection: host.consumer) else { Issue.record("Not parked"); return }
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(event.receipt, connection: host.consumer))
            #expect(host.adapter.settled.last?.routeID == routeID)
            #expect(host.adapter.hasIngress(host.consumer.incarnation) == false)
            #expect(host.adapter.payload(host.consumer.incarnation) == nil)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(event.receipt, connection: host.consumer) == false)
            _ = try await host.subscribe(sequence: 4)
        }
    }
}

extension ServiceSubscriptionMessageIntegrationTests {
    @Test func twoCanonicalScopesStaySeparateAndEventDrainIsRoundRobin() async throws {
        try await withInvocationHost(minor: 4) { host in
            let readAlias = try await host.subscribe(sequence: 2)
            let scope = try ServiceScope(featureID: "summary", operation: "write")
            _ = try await host.runtime.authorizeService(connection: host.consumer, requirementID: host.contractID,
                scope: scope, partition: "TEST-ONLY.other-account", crossPublisherConsent: true)
            let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID, scope: scope)))
            let raw = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4), connection: host.consumer, sequence: 3, kind: .control))
            guard case .admitted = await host.runtime.receiveServiceControl(raw, connection: host.consumer),
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation),
                  case .serviceSourceStart(let delivery) = host.adapter.payload(host.provider.incarnation) else { Issue.record("Missing actual second source"); return }
            let start = try ServiceSubscriptionFrameCodec.decodeSourceStart(delivery.payload, profile: .v1_4)
            #expect(start.sourceID != host.acquisition.sourceID)
            #expect(start.partition == "TEST-ONLY.other-account" && start.scope == scope)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(delivery.receipt, connection: host.provider))
            let ready = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .startupCompleted)
            let readyInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(ready, profile: .v1_4), connection: host.provider, sequence: 2, kind: .sourceOutput))
            #expect(await host.runtime.receiveServiceSourceOutput(readyInput, connection: host.provider) == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation),
                  case .acquired(let grant) = try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result else { Issue.record("Second source not ready"); return }
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
            let writeAlias = try await host.subscribe(grant: grant, sequence: 4)
            #expect(writeAlias != readAlias)
            #expect(try await host.update(bytes: 1, sequence: 3) == .accepted)
            let first = try #require(host.eventDelivery)
            let response = try ServiceResponse(schemaVersion: 1, contractID: host.contractID, operation: "write", payload: Data([8]))
            let update = try ServiceSourceOutputFrame(sourceID: start.sourceID, startNonce: start.startNonce, output: .sourceUpdate(response))
            let updateInput = try #require(host.adapter.stage(ServiceSubscriptionFrameCodec.encode(update, profile: .v1_4), connection: host.provider, sequence: 4, kind: .sourceOutput))
            #expect(await host.runtime.receiveServiceSourceOutput(updateInput, connection: host.provider) == .accepted)
            #expect(try await host.update(bytes: 2, sequence: 5) == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(first.receipt, connection: host.consumer))
            let second = try #require(host.eventDelivery)
            let writeEvent = try ServiceSubscriptionFrameCodec.decodeServiceEvent(second.payload, profile: .v1_4)
            #expect(writeEvent.subscriptionID == writeAlias && writeEvent.token == grant && writeEvent.response == response)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(second.receipt, connection: host.consumer))
            let third = try #require(host.eventDelivery)
            let readEvent = try ServiceSubscriptionFrameCodec.decodeServiceEvent(third.payload, profile: .v1_4)
            #expect(readEvent.subscriptionID == readAlias && readEvent.token == host.acquisition.grant && readEvent.response.payload.count == 2)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(third.receipt, connection: host.consumer))
        }
    }
}
