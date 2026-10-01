//
//  AddonRuntimeDelegatedCPUHealthTests.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonRuntimeDelegatedCPUHealthTests {

    @Test
    func activeThreeOwnerChainChargesEachContributorAndKeepsUnmeasuredConsumerPaused() async throws {
        let fixture = try await ChainFixture()
        let oldWork = try await fixture.runtime.beginServiceInvocation(
            connection: fixture.consumer,
            grantID   : fixture.firstAcquisition.grant.id,
            invocation: fixture.invocation()
        )
        let baseline = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(observations(baseline).count == 3)

        fixture.clock.set(fixture.instant(1))
        let overCredit = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let observed   = observations(overCredit)
        #expect(observed.count == 3)

        for owner in [fixture.consumer.identity, fixture.middle.identity] {
            let item = try #require(observed.first(where: { $0.owner == owner }))
            #expect(item.classification == .moderate)
            #expect(item.decision == .keep)
            #expect(item.status == .current)
        }

        let leaf = try #require(observed.first(where: { $0.owner == fixture.leaf.identity }))
        #expect(leaf.classification == .noNewViolation)
        #expect(fixture.read.bindings.count == 4)

        #expect(await fixture.runtime.resourceHealthSnapshot(

            for: try fixture.version(fixture.consumer.identity)

        )?.moderateIncidentCount == 1)
        #expect(await fixture.runtime.resourceHealthSnapshot(
            for: try fixture.version(fixture.middle.identity)
        )?.moderateIncidentCount == 1)

        #expect(try await fixture.runtime.pumpServiceInvocation(oldWork.id))

        let oldResult = try await fixture.runtime.receiveServiceCompletion(
            oldWork.id,
            connection: fixture.middle,
            response  : ServiceResponse(
                schemaVersion: 1,
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([2])
            )
        )
        guard case .accepted = oldResult else {
            Issue.record("Work admitted before the CPU incident must finish.")
            return
        }

        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumer,
                grantID   : fixture.firstAcquisition.grant.id,
                invocation: fixture.invocation()
            )
        }

        fixture.clock.set(fixture.instant(12))
        let credited = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(observations(credited).first(
            where: { $0.owner == fixture.middle.identity }
        )?.classification == .noNewViolation)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumer,
                grantID   : fixture.firstAcquisition.grant.id,
                invocation: fixture.invocation()
            )
        }
    }

    @Test
    func disabledPhysicalContributorDuringReadCannotRecordDelegatedHealth() async throws {
        let gate    = ChainReadGate()
        let fixture = try await ChainFixture(gate: gate)
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)

        fixture.clock.set(fixture.instant(1))
        let sampling = Task {
            try await fixture.runtime.sampleResources(reason: .jobBoundary)
        }

        defer { gate.release() }
        #expect(gate.waitForArrival())

        let disabled  = ChainDisableSignal()
        let runtime   = fixture.runtime
        let leafID    = fixture.leaf.identity.addonID
        let disabling = Task {
            await AddonRuntime.$cpuDisableCheckpoint.withValue({ owner in
                if owner == leafID { disabled.signal() }
            }) {
                await runtime.disable(owner: leafID)
            }
        }

        #expect(disabled.waitForArrival())

        gate.release()

        let result = try await sampling.value
        await disabling.value

        let values = observations(result)
        #expect(values.count == 3)

        for owner in [fixture.consumer.identity, fixture.middle.identity] {
            let item = try #require(values.first(where: { $0.owner == owner }))
            #expect(item.status == .stale)
            #expect(item.decision == nil)
        }

        #expect(try await fixture.runtime.registerProcessMetrics(
            incarnation: fixture.middle.incarnation,
            binding    : fixture.middleBinding
        ) == .duplicate)

        // Launch now registers durable health before a metric binding exists;
        // stale delegated CPU must leave that record at zero incidents.
        #expect(await fixture.runtime.resourceHealthSnapshot(
            for: try fixture.version(fixture.consumer.identity)
        )?.moderateIncidentCount == 0)
    }

    @Test
    func processlessRetainedConsumerRecordsProviderDebtInFallbackSession() async throws {
        let fixture = try await ChainFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await fixture.resources.armJobAdmission()

        let admitted = Task {
            try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumer,
                grantID   : fixture.firstAcquisition.grant.id,
                invocation: fixture.invocation()
            )
        }

        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("The retained-interest job gate did not arrive within five seconds.")
                await fixture.resources.releaseGate()
            } catch is CancellationError {
                // The bounded gate was observed and released.
            } catch {
                Issue.record("The retained-interest watchdog failed: \(error)")
                await fixture.resources.releaseGate()
            }
        }

        defer {
            watchdog.cancel()
            admitted.cancel()
            Task { await fixture.resources.releaseGate() }
        }

        await fixture.resources.waitForArrival()
        await fixture.runtime.observeExit(fixture.consumer.incarnation)
        fixture.clock.set(fixture.instant(1))

        let result = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let owner  = try #require(observations(result).first(where: { $0.owner == fixture.consumer.identity }))

        #expect(owner.classification == .moderate)
        #expect(owner.status == .current)
        #expect(owner.decision == .keep)
        #expect(await fixture.runtime.resourceHealthSnapshot(
            for: try fixture.version(fixture.consumer.identity)
        )?.moderateIncidentCount == 1)

        await fixture.resources.releaseGate()
        _ = try? await admitted.value
    }

    @Test
    func quarantinedDelegatedOwnerDoesNotBindAnotherFallbackSession() async throws {
        let fixture = try await ChainFixture(sustainedCPU: true)
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)

        for second in 1...3 {
            fixture.clock.set(fixture.instant(second))
            let result = try await fixture.runtime.sampleResources(reason: .jobBoundary)
            let owner  = try #require(observations(result).first(where: { $0.owner == fixture.consumer.identity }))
            #expect(owner.classification == .moderate)
            #expect(owner.decision == (second == 3 ? .quarantine : .keep))
        }

        #expect(await fixture.runtime.resourceHealthSnapshot(

            for: try fixture.version(fixture.consumer.identity)

        )?.isQuarantined == true)

        fixture.clock.set(fixture.instant(4))
        let repeated = try await fixture.runtime.sampleResources(reason: .jobBoundary)

        let owner    = try #require(observations(repeated).first(where: { $0.owner == fixture.consumer.identity }))
        #expect(owner.classification == .moderate)
        #expect(owner.status == .stale)
        #expect(owner.decision == nil)
        #expect(await fixture.runtime.resourceHealthSnapshot(
            for: try fixture.version(fixture.consumer.identity)
        )?.isQuarantined == true)
    }

    @Test
    func processlessDelegatedCPURecordsThroughPendingCrashTicket() async throws {
        let fixture = try await ChainFixture(sustainedCPU: true)
        let version = try fixture.version(fixture.middle.identity)
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)

        await fixture.runtime.observeExit(fixture.middle.incarnation, cause: .unexpected)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == true)

        fixture.clock.set(fixture.instant(1))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)

        fixture.clock.set(fixture.instant(2))
        let result = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let middle = try #require(observations(result).first(where: { $0.owner == fixture.middle.identity }))
        #expect(middle.classification == .moderate)
        #expect(middle.decision == .keep)
        #expect(middle.status == .current)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.moderateIncidentCount == 1)
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.hasPendingRetry == true)
    }

    private func observations(_ result: AddonRuntime.ResourceSampleResult) -> [AddonRuntime.ResourceOwnerObservation] {
        guard case .sampled(let values) = result else { return [] }

        return values
    }

    private struct ChainFixture {

        let runtime         : AddonRuntime
        let clock           : MutableRuntimeClock
        let read            : ChainReadSource
        let resources       : GatedRuntimeResourceAccess
        let consumer        : RuntimeConnection
        let middle          : RuntimeConnection
        let leaf            : RuntimeConnection
        let firstAcquisition: ServiceAcquisition
        let middleBinding   : ProcessMetricBinding
        let leafBinding     : ProcessMetricBinding

        init(
            gate        : ChainReadGate? = nil,
            sustainedCPU: Bool = false
        ) async throws {
            let consumerAddon = try installedFixture("consumer", publisher: "TEST-ONLY.shared")
            let middleAddon   = try replacing(
                installedFixture("focus", publisher: "TEST-ONLY.shared"),
                requires: [requirement("com.example.leaf.service", ">=1.0.0 <2.0.0")]
            )

            let leafAddon = try replacing(
                installedFixture("focus", publisher: "TEST-ONLY.shared"),
                id      : "com.example.leaf.cascade",
                provides: [ProvidedService(
                    kind   : .service,
                    id     : "com.example.leaf.service",
                    version: "1.0.0"
                )]
            )

            middleBinding = Self.binding(1)
            leafBinding   = Self.binding(2)

            let ticks: [UInt64] = sustainedCPU
                ? [0, 60_000_000, 120_000_000, 180_000_000, 240_000_000]
                : [0, 60_000_000, 60_000_000]

            read = ChainReadSource(
                [middleBinding.token: ticks, leafBinding.token: ticks],
                gatedToken: gate == nil ? nil : leafBinding.token,
                gate      : gate
            )

            clock = MutableRuntimeClock(instant: RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000),
                monotonic: .zero
            ))

            let adapter  = RecordingRuntimeAdapter()
            let governor = ResourceGovernor()
            resources = GatedRuntimeResourceAccess(target: governor)

            runtime   = try await AddonRuntime.make(
                catalog               : [consumerAddon, middleAddon, leafAddon],
                environment           : HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [
                        consumerAddon.manifest.id: [],
                        middleAddon.manifest.id  : [],
                        leafAddon.manifest.id    : []
                    ],
                    explicitBindings: []
                ),
                governor              : governor,
                resourceAccess        : resources,
                serviceDecisionFactory: { $0 },
                adapter               : adapter,
                clock                 : clock,
                metricRead            : read.read
            )

            let offer = try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )

            let consumerLaunch = try await runtime.requestLaunch(owner: consumerAddon.manifest.id)
            consumer = try await runtime.attach(launchID: consumerLaunch, offer: offer)

            let firstPermission = try await runtime.authorizeService(
                connection           : consumer,
                requirementID        : "com.example.focus.sessions",
                scope                : ServiceScope(featureID: "summary", operation: "read"),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )

            do {
                _ = try await runtime.acquireService(
                    connection  : consumer,
                    permissionID: firstPermission,
                    lifetime    : .seconds(30)
                )
                Issue.record("The missing provider path should be launched.")
            } catch let error as AddonFailure {
                #expect(error.code == .dependencyUnavailable)
            }

            let middleStart = try #require(adapter.lastStart(owner: middleAddon.manifest.id))
            let leafStart   = try #require(adapter.lastStart(owner: leafAddon.manifest.id))
            middle = try await runtime.attach(launchID: middleStart.launchID, offer: offer)
            leaf   = try await runtime.attach(launchID: leafStart.launchID, offer: offer)

            firstAcquisition = try await runtime.acquireService(
                connection  : consumer,
                permissionID: firstPermission,
                lifetime    : .seconds(30)
            )

            #expect(try await runtime.receiveSourceStartupCompletion(firstAcquisition.sourceID, connection: middle))

            let secondPermission = try await runtime.authorizeService(
                connection           : middle,
                requirementID        : "com.example.leaf.service",
                scope                : ServiceScope(featureID: "localTimer", operation: "read"),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )

            let secondAcquisition = try await runtime.acquireService(
                connection  : middle,
                permissionID: secondPermission,
                lifetime    : .seconds(30)
            )
            #expect(try await runtime.receiveSourceStartupCompletion(secondAcquisition.sourceID, connection: leaf))

            _ = try await runtime.registerProcessMetrics(
                incarnation: middle.incarnation,
                binding    : middleBinding
            )
            _ = try await runtime.registerProcessMetrics(incarnation: leaf.incarnation, binding: leafBinding)
        }

        func instant(_ second: Int) -> RuntimeInstant {
            RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000 + Double(second)),
                monotonic: .seconds(second)
            )
        }

        func version(_ identity: VerifiedAddonIdentity) throws -> AddonVersionIdentity {
            try AddonVersionIdentity(verifiedIdentity: identity, version: SemanticVersion(1, 0, 0))
        }

        func invocation() throws -> ServiceInvocation {
            try ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([1]),
                deadline     : Date(timeIntervalSince1970: 2_000_000_020)
            )
        }

        private static func binding(_ index: UInt8) -> ProcessMetricBinding {
            ProcessMetricBinding(
                pid               : Int32(50 + index),
                birthAbsoluteTicks: 100,
                executableUUID    : UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)),
                token             : UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, index)),
                clockDomain       : UUID(uuid: (3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3))
            )
        }
    }
}
