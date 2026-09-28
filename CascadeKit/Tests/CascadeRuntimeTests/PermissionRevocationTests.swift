import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct PermissionRevocationTests {
    @Test func expiryUsesMonotonicTimeAcrossWallClockChanges() async throws {
        let f = BrokerFixture(), broker = ServiceBroker()
        _ = try await broker.authorize(f.permission())
        let session = try await broker.registerSession(identity: f.owner)
        let value = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        let work = try await broker.beginInvocation(session: session, grantID: value.grant.id,
            invocation: f.invocation(), now: f.now)
        _ = try await broker.consumeInvocation(work.id, now: f.now)
        let response = try ServiceResponse(schemaVersion: 1, contractID: "test.service",
            operation: "read", payload: Data([2]))
        let shifted = RuntimeInstant(wall: f.now.wall.addingTimeInterval(100_000), monotonic: .seconds(11))
        #expect(try await broker.completeInvocation(work.id, response: response, now: shifted) == response)
        let expired = RuntimeInstant(wall: f.now.wall.addingTimeInterval(-100_000), monotonic: .seconds(41))
        await #expect(throws: AddonFailure.self) {
            try await broker.beginInvocation(session: session, grantID: value.grant.id,
                invocation: f.invocation(), now: expired)
        }
    }

    @Test func revocationInvalidatesOutstandingResultsAndStopsTheSource() async throws {
        let f = BrokerFixture(), governor = ResourceGovernor()
        let broker = ServiceBroker(governor: governor)
        let permission = try await broker.authorize(f.permission())
        let session = try await broker.registerSession(identity: f.owner)
        let baseline = await governor.usage(.retainedStateBytes)
        let value = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        let work = try await broker.beginInvocation(session: session, grantID: value.grant.id,
            invocation: f.invocation(), now: f.now)
        #expect(await broker.revoke(permissionID: permission) == [.stopSource(value.sourceID)])
        await #expect(throws: AddonFailure.self) {
            try await broker.completeInvocation(work.id,
                response: ServiceResponse(schemaVersion: 1, contractID: "test.service",
                    operation: "read", payload: Data()), now: f.now)
        }
        #expect(await governor.usage(.retainedStateBytes) > baseline)
        #expect(await broker.sourceChanged(value.sourceID, now: f.now).isEmpty)
        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func disablingOneFeaturePreservesIndependentFeatureAndNeverRebinds() async throws {
        let f = BrokerFixture(), broker = ServiceBroker()
        _ = try await broker.authorize(f.permission())
        _ = try await broker.authorize(f.permission(feature: "other", version: SemanticVersion(2, 0, 0)))
        let session = try await broker.registerSession(identity: f.owner)
        let first = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        let second = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "other", operation: "read"), now: f.now, lifetime: .seconds(30))
        #expect(await broker.disable(consumer: f.owner, featureID: "main") == [.stopSource(first.sourceID)])
        _ = try await broker.beginInvocation(session: session, grantID: second.grant.id,
            invocation: f.invocation(), now: f.now)
        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(session: session, requirementID: "requirement",
                scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        }
        await #expect(throws: AddonFailure.self) {
            try await broker.authorize(f.permission(feature: "other", version: SemanticVersion(3, 0, 0)))
        }
    }

    @Test func deniedAdmissionAndGrantBoundsDoNotLeakReservations() async throws {
        let f = BrokerFixture(), governor = ResourceGovernor()
        let broker = ServiceBroker(governor: governor, limits: ServiceBrokerLimits(grantsPerOwner: 1))
        _ = try await broker.authorize(f.permission())
        let session = try await broker.registerSession(identity: f.owner)
        _ = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        let before = await governor.usage(.retainedStateBytes)
        try await expectServiceResourceDenied {
            try await broker.acquire(session: session, requirementID: "requirement",
                scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        }
        #expect(await governor.usage(.retainedStateBytes) == before)
        await broker.shutdown()
        #expect(await governor.usage(.retainedStateBytes) == 0)
        let small = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 8_000))
        let constrained = ServiceBroker(governor: small)
        _ = try await constrained.authorize(f.permission())
        let constrainedSession = try await constrained.registerSession(identity: f.owner)
        let admitted = await small.usage(.retainedStateBytes)
        try await expectServiceResourceDenied {
            try await constrained.acquire(session: constrainedSession, requirementID: "requirement",
                scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        }
        #expect(await small.usage(.retainedStateBytes) == admitted)
    }

    @Test func authorityRejectsMissingConsentOversizeAndNoncanonicalVersion() async throws {
        let f = BrokerFixture(), broker = ServiceBroker()
        for permission in [f.permission(consent: false), f.permission(partition: String(repeating: "x", count: 257)),
            f.permission(version: SemanticVersion(-1, 0, 0)),
            f.permission(version: SemanticVersion(1, 0, 0, prerelease: "01"))] {
            await #expect(throws: AddonFailure.self) { try await broker.authorize(permission) }
        }
        let samePublisher = VerifiedAddonIdentity(publisher: "provider", addonID: f.owner.addonID)
        let session = try await broker.registerSession(identity: samePublisher)
        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(session: session, requirementID: "requirement",
                scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        }
        _ = try await broker.authorize(f.permission(samePublisher, consent: false))
    }
    @Test func commonExpiryDrainReleasesExpiredInterestsSourcesAndWork() async throws {
        let f = BrokerFixture(), governor = ResourceGovernor()
        let broker = ServiceBroker(governor: governor)
        _ = try await broker.authorize(f.permission())
        let session = try await broker.registerSession(identity: f.owner)
        let baseline = await governor.usage(.retainedStateBytes)
        let value = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        let work = try await broker.beginInvocation(session: session, grantID: value.grant.id,
            invocation: f.invocation(), now: f.now)
        #expect(await broker.nextDeadline() == .seconds(30))
        let now = RuntimeInstant(wall: f.now.wall.addingTimeInterval(-500), monotonic: .seconds(41))
        #expect(await broker.expire(now: now) == [.stopSource(value.sourceID)])
        #expect(await broker.nextDeadline() == .seconds(610))
        #expect(await governor.usage(.retainedStateBytes) > baseline)
        await #expect(throws: AddonFailure.self) {
            try await broker.completeInvocation(work.id,
                response: ServiceResponse(schemaVersion: 1, contractID: "test.service", operation: "read",
                    payload: Data()), now: now)
        }
        let fresh = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: now, lifetime: .seconds(30))
        #expect(fresh.sourceID != value.sourceID)
    }

    @Test func providerLossReturnsOnlyAffectedFeaturesAndRevokesTheirOutstandingWork() async throws {
        let f = BrokerFixture(), broker = ServiceBroker()
        _ = try await broker.authorize(f.permission())
        let otherProvider = VerifiedAddonIdentity(publisher: "other", addonID: AddonID(rawValue: "com.test.other")!)
        let independent = HostServicePermission(consumer: f.owner,
            binding: ServiceBinding(requirementID: "independent", consumer: f.owner.addonID,
                provider: otherProvider.addonID, providerIdentity: otherProvider,
                contractVersion: SemanticVersion(1, 0, 0), digest: "other-digest", featureID: "other"),
            serviceID: "test.service", partition: "account-a", operation: "read", crossPublisherConsent: true)
        _ = try await broker.authorize(independent)
        let session = try await broker.registerSession(identity: f.owner)
        let main = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        let other = try await broker.acquire(session: session, requirementID: "independent",
            scope: ServiceScope(featureID: "other", operation: "read"), now: f.now, lifetime: .seconds(30))
        let work = try await broker.beginInvocation(session: session, grantID: main.grant.id,
            invocation: f.invocation(), now: f.now)
        let impact = await broker.providerUnavailable(f.provider)
        #expect(impact.affectedFeatures == [ResolvedFeature(addonID: f.owner.addonID, featureID: "main")])
        #expect(impact.decisions == [.stopSource(main.sourceID)])
        await #expect(throws: AddonFailure.self) {
            try await broker.completeInvocation(work.id,
                response: ServiceResponse(schemaVersion: 1, contractID: "test.service", operation: "read",
                    payload: Data()), now: f.now)
        }
        _ = try await broker.beginInvocation(session: session, grantID: other.grant.id,
            invocation: f.invocation(), now: f.now)
        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(session: session, requirementID: "requirement",
                scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        }
    }

    @Test func disablingAddonAlsoDisconnectsSessionAndReleasesItsProviderDependencies() async throws {
        let f = BrokerFixture(), broker = ServiceBroker()
        _ = try await broker.authorize(f.permission())
        let session = try await broker.registerSession(identity: f.owner)
        let value = try await broker.acquire(session: session, requirementID: "requirement",
            scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        #expect(await broker.disableAddon(f.provider).decisions == [.stopSource(value.sourceID)])
        _ = await broker.disableAddon(f.owner)
        _ = try await broker.authorize(f.permission())
        await #expect(throws: AddonFailure.self) {
            try await broker.acquire(session: session, requirementID: "requirement",
                scope: ServiceScope(featureID: "main", operation: "read"), now: f.now, lifetime: .seconds(30))
        }
    }

    @Test func timeoutRecoveryBeforeOrAfterRevocationCannotUseOldOrReplacedAuthority() async throws {
        for revokeBeforeRecovery in [true, false] {
            let fixture = BrokerFixture()
            let governor = ResourceGovernor()
            let broker = ServiceBroker(governor: governor)
            let permission = try await broker.authorize(fixture.permission())
            let session = try await broker.registerSession(identity: fixture.owner)
            let scope = try ServiceScope(featureID: "main", operation: "read")
            let grant = try await broker.acquire(
                session: session, requirementID: "requirement", scope: scope,
                now: fixture.now, lifetime: .seconds(3_600)
            )
            let request = try fixture.invocation()
            let work = try await broker.beginInvocation(
                session: session, grantID: grant.grant.id, invocation: request, now: fixture.now
            )
            _ = try await broker.consumeInvocation(work.id, now: fixture.now)
            let timeout = RuntimeInstant(wall: fixture.now.wall.addingTimeInterval(21), monotonic: .seconds(31))
            if !revokeBeforeRecovery {
                #expect(try await broker.requestOutcome(
                    session: session, grantID: grant.grant.id, requestID: request.requestID, now: timeout
                ) == .unknown)
                #expect(await governor.usage(.retainedStateBytes) == 24_577)
            }
            _ = await broker.revoke(permissionID: permission)
            #expect(await governor.usage(.retainedStateBytes) == 11_265)
            await #expect(throws: AddonFailure.self) {
                try await broker.requestOutcome(
                    session: session, grantID: grant.grant.id, requestID: request.requestID, now: timeout
                )
            }
            _ = try await broker.authorize(fixture.permission(partition: "different-account"))
            let replacement = try await broker.acquire(
                session: session, requirementID: "requirement", scope: scope,
                now: timeout, lifetime: .seconds(3_600)
            )
            await #expect(throws: AddonFailure.self) {
                try await broker.requestOutcome(
                    session: session, grantID: replacement.grant.id, requestID: request.requestID, now: timeout
                )
            }
            #expect(await governor.usage(.retainedStateBytes) == 24_577)
            await broker.shutdown()
            #expect(await governor.usage(.retainedStateBytes) == 0)
        }
    }

}
