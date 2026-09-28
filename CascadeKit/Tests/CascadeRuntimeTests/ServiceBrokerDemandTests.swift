//
//  ServiceBrokerDemandTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct ServiceBrokerDemandTests {
    private func later(_ fixture: BrokerFixture, _ seconds: Double) -> RuntimeInstant {
        RuntimeInstant(
            wall: fixture.now.wall.addingTimeInterval(seconds),
            monotonic: fixture.now.monotonic + .seconds(seconds)
        )
    }

    @Test func currentDemandRequiresOneLiveCanonicalInterestForExactProvider() async throws {
        let fixture = BrokerFixture()
        let governor = ResourceGovernor()
        let broker = ServiceBroker(governor: governor)
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now) == false)

        _ = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now) == false)

        let acquisition = try await broker.acquire(
            session: session,
            requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"),
            now: fixture.now,
            lifetime: .seconds(30)
        )
        let grantsBeforeRead = await broker.activeGrantIDs()
        let sourcesBeforeRead = await broker.activeSourceIDs()
        let usageBeforeRead = await governor.usage(.retainedStateBytes)
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now))
        #expect(await broker.activeGrantIDs() == grantsBeforeRead)
        #expect(await broker.activeSourceIDs() == sourcesBeforeRead)
        #expect(await governor.usage(.retainedStateBytes) == usageBeforeRead)
        #expect(try await broker.hasCurrentDemand(for: fixture.other, at: fixture.now) == false)
        let wrongPublisher = VerifiedAddonIdentity(
            publisher: "different-publisher",
            addonID: fixture.provider.addonID
        )
        #expect(try await broker.hasCurrentDemand(for: wrongPublisher, at: fixture.now) == false)

        await broker.disconnect(session)
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now))
        await broker.providerExitedPreservingInterests(fixture.provider)
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now))
        #expect(try await broker.hasCurrentDemand(
            for: fixture.provider,
            at: later(fixture, 30)
        ) == false)
        #expect(try await broker.hasCurrentDemand(
            for: fixture.provider,
            at: later(fixture, 31)
        ) == false)

        _ = acquisition
    }

    @Test func currentDemandClearsOnRevocationAndShutdownAndRejectsBadTime() async throws {
        let fixture = BrokerFixture()
        let broker = ServiceBroker()
        let permission = try await broker.authorize(fixture.permission())
        let session = try await broker.registerSession(identity: fixture.owner)
        _ = try await broker.acquire(
            session: session,
            requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"),
            now: fixture.now,
            lifetime: .seconds(30)
        )
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now))

        let malformed = RuntimeInstant(wall: fixture.now.wall, monotonic: .seconds(-1))
        await #expect(throws: AddonFailure.self) {
            try await broker.hasCurrentDemand(for: fixture.provider, at: malformed)
        }

        _ = await broker.revoke(permissionID: permission)
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now) == false)

        let replacementPermission = try await broker.authorize(fixture.permission())
        _ = replacementPermission
        _ = try await broker.acquire(
            session: session,
            requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"),
            now: fixture.now,
            lifetime: .seconds(30)
        )
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now))
        _ = await broker.shutdown()
        #expect(try await broker.hasCurrentDemand(for: fixture.provider, at: fixture.now) == false)
    }
}
