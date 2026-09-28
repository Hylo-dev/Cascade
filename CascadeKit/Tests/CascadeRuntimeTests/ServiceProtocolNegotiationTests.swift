import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ServiceProtocolNegotiationTests {
    @Test func standaloneBrokerRegistrationStillMintsIndependentGenerations() async throws {
        try await withInvocationHost { host in
            let fixture = BrokerFixture()
            let broker = ServiceBroker(governor: host.governor)
            do {
                let (first, acquisition) = try await fixture.connect(broker)
                await broker.disconnect(first)
                let second = try await broker.registerSession(identity: fixture.owner)
                let secondGrant = try await broker.acquire(session: second, requirementID: "requirement",
                    scope: ServiceScope(featureID: "main", operation: "read"), now: fixture.now, lifetime: .seconds(30))
                #expect(secondGrant.grant.generation != acquisition.grant.generation)
                #expect(acquisition.grant.generation != host.consumer.publicationConnection.generation)
                await broker.disconnect(first)
                await broker.disconnect(second)
                await broker.shutdown()
            } catch { await broker.shutdown(); throw error }
        }
    }

    @Test func reconnectComposesFreshGenerationAndOldAuthorityCannotReleaseNewPayload() async throws {
        try await withInvocationHost { host in
            _ = try await host.begin()
            let oldDelivery = try #require(host.providerDelivery)
            await host.runtime.closeConnection(host.consumer)
            await host.runtime.observeExit(host.consumer.incarnation)
            await host.runtime.observeExit(host.provider.incarnation)
            let launch = try await host.runtime.requestLaunch(owner: host.owner)
            let consumer = try await host.runtime.attach(launchID: launch, offer: InvocationMessageHost.offer(3))
            #expect(consumer.publicationConnection.generation != host.consumer.publicationConnection.generation)
            let permission = host.permissionID
            do { _ = try await host.runtime.acquireService(connection: consumer, permissionID: permission, lifetime: .seconds(30)); Issue.record("Expected provider startup") }
            catch { #expect((error as? AddonFailure)?.code == .dependencyUnavailable) }
            let start = try #require(host.adapter.starts.last { $0.identity.addonID == host.provider.identity.addonID })
            let provider = try await host.runtime.attach(launchID: start.launchID, offer: InvocationMessageHost.offer(3))
            let acquired = try await host.runtime.acquireService(connection: consumer, permissionID: permission, lifetime: .seconds(30))
            #expect(try await host.runtime.receiveSourceStartupCompletion(acquired.sourceID, connection: provider))
            #expect(acquired.grant.generation == consumer.publicationConnection.generation)
            #expect(acquired.grant.generation != host.acquisition.grant.generation)
            let request = try host.invocation()
            let raw = try ServiceFrameCodec.encode(ServiceInvocationRequest(grantID: acquired.grant.id, invocation: request), profile: .v1_3)
            let h = try #require(host.adapter.stage(raw, connection: consumer, sequence: 1, kind: .invocation))
            guard case .admitted = await host.runtime.receiveServiceRequest(h, connection: consumer) else { Issue.record("No fresh dispatch"); return }
            guard case .serviceInvocation(let delivery) = host.adapter.payload(provider.incarnation) else { Issue.record("No fresh payload"); return }
            #expect(await host.runtime.receiveServiceReceipt(oldDelivery.receipt, connection: provider) == false)
            #expect(await host.runtime.receiveServiceReceipt(oldDelivery.receipt, connection: host.provider) == false)
            await host.runtime.closeConnection(host.consumer)
            #expect(host.adapter.payload(provider.incarnation) == .serviceInvocation(delivery))
            #expect(await host.runtime.receiveServiceReceipt(delivery.receipt, connection: provider))
            let output = try #require(host.adapter.stage(try host.completionBytes(requestID: request.requestID), connection: provider, sequence: 1, kind: .completion))
            _ = try await host.runtime.receiveServiceCompletionOutput(output, connection: provider)
            guard case .serviceReply(let reply) = host.adapter.payload(consumer.incarnation) else { Issue.record("No fresh reply"); return }
            let expected = try host.response()
            #expect(try ServiceFrameCodec.decodeInvocationReply(reply.payload, profile: .v1_3).result == .completed(expected))
            #expect(await host.runtime.receiveServiceReceipt(reply.receipt, connection: consumer))
            #expect(await host.runtime.receiveServiceRequest(h, connection: host.consumer) == .refused(.sessionRevoked))
        }
    }

    @Test func mixedProviderCannotDispatchDedicatedFrames() async throws {
        try await withInvocationHost(providerMinor: 2) { host in
            #expect(host.consumer.publicationConnection.negotiatedProtocol.minor == 3)
            #expect(host.provider.publicationConnection.negotiatedProtocol.minor == 2)
            _ = try await host.begin()
            let d = try #require(host.replyDelivery)
            guard case .refused(let code, _) = try ServiceFrameCodec.decodeInvocationReply(d.payload, profile: .v1_3).result else { Issue.record("Expected mixed-version refusal"); return }
            #expect(code == .versionConflict)
            #expect(host.providerDelivery == nil)
            #expect(await host.governor.usage(.commands, owner: host.owner) == 0)
        }
    }

    @Test(arguments: [0, 1, 2])
    func legacyRuntimePeersKeepIndependentServiceGeneration(minor: Int) async throws {
        try await withInvocationHost(minor: minor) { host in
            let p = host.consumer.publicationConnection.negotiatedProtocol
            #expect(p.minor == minor)
            #expect(p.serviceInvocationFrameProfile == nil)
            #expect(host.acquisition.grant.generation != host.consumer.publicationConnection.generation)
            let raw = try ServiceFrameCodec.encode(ServiceInvocationRequest(grantID: host.acquisition.grant.id,
                                                                            invocation: host.invocation()), profile: .v1_3)
            let h = try #require(host.adapter.stage(raw, connection: host.consumer, sequence: 1, kind: .invocation))
            #expect(await host.runtime.receiveServiceRequest(h, connection: host.consumer) == .refused(.versionConflict))
            #expect(host.providerDelivery == nil)
        }
    }

    @Test func smallPrepaidIngressCannotAdvertiseFullServiceSupport() async throws {
        try await withInvocationHost(maximumEnvelopeBytes: 196_607) { host in
            #expect(host.consumer.publicationConnection.negotiatedProtocol.minor == 2)
            #expect(host.adapter.starts.allSatisfy { $0.maximumServiceIngressBytes == 0 })
        }
    }

    @Test func publicOffersAndSyntaxProfilesCannotActivateServiceHost() throws {
        let offer = try ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 65_535, contentSchemas: [1])
        let manifest = try ProtocolVersion(major: 1, minimumMinor: 0)
        for storage in [false, true] {
            for assets in [false, true] {
                let p = try ProtocolNegotiator.negotiate(offer: offer, manifestProtocol: manifest,
                    supportsKeyedStorageFrames: storage, supportsAssetFrames: assets)
                #expect(p.minor == (storage ? (assets ? 2 : 1) : 0))
                #expect(p.serviceInvocationFrameProfile == nil)
            }
        }
        let enabled = try ProtocolNegotiator.negotiate(offer: offer, manifestProtocol: manifest,
            supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true)
        #expect(enabled.minor == 3)
        for maximum in [0, 1, 2, 3] {
            let p = try ProtocolNegotiator.negotiate(
                offer: ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: maximum, contentSchemas: [1]),
                manifestProtocol: manifest, supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true)
            #expect(p.minor == maximum)
        }
        #expect(throws: AddonFailure.self) {
            _ = try ProtocolNegotiator.negotiate(offer: ProtocolOffer(major: 1, minimumMinor: 4, maximumMinor: 4, contentSchemas: [1]),
                manifestProtocol: manifest, supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true)
        }
        #expect(throws: AddonFailure.self) {
            _ = try ProtocolNegotiator.negotiate(offer: offer, manifestProtocol: ProtocolVersion(major: 1, minimumMinor: 4),
                supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true)
        }
        #expect(throws: AddonFailure.self) {
            _ = try ProtocolNegotiator.negotiate(offer: offer, manifestProtocol: ProtocolVersion(major: 2, minimumMinor: 0),
                supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true)
        }
        #expect(throws: AddonFailure.self) {
            _ = try ProtocolNegotiator.negotiate(offer: ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 3, contentSchemas: [7]),
                manifestProtocol: manifest, supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true)
        }
    }
}

extension ServiceProtocolNegotiationTests {
    @Test(arguments: ["major", "minimum", "schema"])
    func completeHostRejectedAttachRollsBackAndSameLaunchCanNegotiate(difference: String) async throws {
        try await withInvocationHost(minor: 4) { host in
            await host.runtime.closeConnection(host.consumer)
            await host.runtime.observeExit(host.consumer.incarnation)
            let launch = try await host.runtime.requestLaunch(owner: host.owner)
            let before = await host.governor.usage(.retainedStateBytes)
            let offer = try ProtocolOffer(major: difference == "major" ? 2 : 1,
                minimumMinor: difference == "minimum" ? 5 : 0,
                maximumMinor: difference == "minimum" ? 5 : 4,
                contentSchemas: difference == "schema" ? [3] : [1])
            do { _ = try await host.runtime.attach(launchID: launch, offer: offer); Issue.record("Incompatible offer attached") }
            catch { #expect((error as? AddonFailure)?.code == .versionConflict) }
            #expect(await host.governor.usage(.retainedStateBytes) == before)
            #expect(await host.governor.usage(.providers) == 2)
            let connection = try await host.runtime.attach(launchID: launch, offer: InvocationMessageHost.offer(4))
            #expect(connection.publicationConnection.negotiatedProtocol.minor == 4)
            #expect(connection.publicationConnection.generation != host.consumer.publicationConnection.generation)
        }
    }

    @Test func completeSubscriptionsRequireCumulativeHostAndCompatibleOffer() throws {
        let manifest = try ProtocolVersion(major: 1, minimumMinor: 0)
        for storage in [false, true] {
            for assets in [false, true] {
                for invocation in [false, true] {
                    for subscription in [false, true] {
                        let p = try ProtocolNegotiator.negotiate(offer: InvocationMessageHost.offer(4), manifestProtocol: manifest,
                            supportsKeyedStorageFrames: storage, supportsAssetFrames: assets, serviceHost: invocation, subscriptionHost: subscription)
                        let expected = storage ? (assets ? (invocation ? (subscription ? 4 : 3) : 2) : 1) : 0
                        #expect(p.minor == expected)
                        #expect((p.serviceSubscriptionFrameProfile != nil) == (expected == 4))
                    }
                }
            }
        }
        for maximum in 0...4 {
            let p = try ProtocolNegotiator.negotiate(offer: InvocationMessageHost.offer(maximum), manifestProtocol: manifest,
                supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true, subscriptionHost: true)
            #expect(p.minor == maximum)
        }
        #expect(throws: AddonFailure.self) {
            _ = try ProtocolNegotiator.negotiate(offer: ProtocolOffer(major: 1, minimumMinor: 5, maximumMinor: 5, contentSchemas: [1]),
                manifestProtocol: manifest, supportsKeyedStorageFrames: true, supportsAssetFrames: true, serviceHost: true, subscriptionHost: true)
        }
    }

    @Test(arguments: [2, 3])
    func actualMixedProviderRefusesSubscriptionAcquisitionBeforeIntent(providerMinor: Int) async throws {
        try await withInvocationHost(minor: 4, providerMinor: providerMinor) { host in
            #expect(host.consumer.publicationConnection.negotiatedProtocol.minor == 4)
            #expect(host.provider.publicationConnection.negotiatedProtocol.minor == providerMinor)
            let reply = try await host.control(ServiceControlRequest(requestID: UUID(), action: .acquire(.requestService(requirementID: host.contractID,
                scope: host.acquisition.grant.scope))), sequence: 1)
            guard case .refused(let code, _) = reply.result else { Issue.record("Mixed peer created intent"); return }
            #expect(code == .versionConflict)
        }
    }
}
