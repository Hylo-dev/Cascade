//
//  AddonRuntimeProviderMemoryTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonRuntimeProviderMemoryTests {
    @Test func moderateEpisodePausesFreshWorkOnceUntilOwnFootprintRecovers() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let harness = try await MemoryHarness(footprints: [target, target + 1, target + 2, target, target + 1])
        let accepted = try harness.request()
        #expect(try await harness.runtime.submitAction(accepted) == .admitted)

        _ = try await harness.sample(at: 0)
        _ = try await harness.sample(at: 1)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.submitAction(harness.request())
        }
        #expect(try await harness.runtime.submitAction(accepted) == .duplicate(.queued))
        #expect(try await harness.runtime.pumpReady())
        try await harness.completeLastAction()
        #expect(await harness.incidentCount == 1)

        _ = try await harness.sample(at: 2)
        #expect(await harness.incidentCount == 1)
        _ = try await harness.sample(at: 3)
        _ = try await harness.runtime.submitAction(harness.request())

        _ = try await harness.sample(at: 4)
        #expect(await harness.incidentCount == 2)
    }

    @Test func sameBatchCPUAndMemoryViolationRecordsOneIncidentAndKeepsCPUGateIndependent() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let harness = try await MemoryHarness(
            userTicks : [0, 150_000_000, 150_000_000],
            footprints: [target, target + 1, target]
        )

        _ = try await harness.sample(at: 0)
        let combined = try await harness.sample(at: 1)
        #expect(harness.firstObservation(combined)?.classification == .moderate)
        #expect(await harness.incidentCount == 1)

        _ = try await harness.sample(at: 2)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.submitAction(harness.request())
        }
        #expect(await harness.incidentCount == 1)
    }

    @Test func severeFootprintStopsExpectedAndKeepsPhysicalReservationUntilExit() async throws {
        let moderate = UInt64(96 * 1_024 * 1_024)
        let severe = UInt64(96 * 1_024 * 1_024 + 1)
        let harness = try await MemoryHarness(footprints: [64, moderate, severe])

        _ = try await harness.sample(at: 0)
        _ = try await harness.runtime.submitAction(harness.request())
        _ = try await harness.sample(at: 1)
        #expect(harness.adapter.stopCount(incarnation: harness.incarnation) == 0)
        _ = try await harness.sample(at: 2)

        #expect(harness.adapter.stopCount(incarnation: harness.incarnation) == 1)
        #expect(harness.adapter.stopReason(incarnation: harness.incarnation) == .stopped)
        #expect(await harness.governor.usage(.providers, owner: harness.owner) == 1)
        await harness.runtime.observeExit(harness.incarnation, cause: .unexpected)
        #expect(await harness.governor.usage(.providers, owner: harness.owner) == 0)
        #expect(await harness.snapshot?.crashRetryCount == 0)
        #expect(await harness.snapshot?.hasPendingRetry == false)
    }

    @Test func CPUArithmeticFailureStillAppliesOwnFootprintAndMissingReadDoesNotRecover() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let harness = try await MemoryHarness(
            userTicks : [0, UInt64.max, nil],
            systemTicks: [0, 1, nil],
            footprints: [target, target + 1, nil]
        )

        _ = try await harness.sample(at: 0)
        let overflow = try await harness.sample(at: 1)
        #expect(harness.firstObservation(overflow)?.classification == .unavailable)
        #expect(await harness.incidentCount == 1)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.submitAction(harness.request())
        }

        _ = try await harness.sample(at: 2)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.submitAction(harness.request())
        }
        #expect(await harness.incidentCount == 1)
    }

    @Test func wakeAndReregistrationKeepEpisodeWhileNewIncarnationStartsAnother() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let harness = try await MemoryHarness(footprints: [
            target, target + 1, target + 2, target + 3, target + 4, target
        ])

        _ = try await harness.sample(at: 0)
        _ = try await harness.sample(at: 1)
        #expect(await harness.incidentCount == 1)
        #expect(try await harness.runtime.resetProcessMetricsAfterWake() == .completed)
        _ = try await harness.sample(at: 2)
        #expect(await harness.incidentCount == 1)
        #expect(try await harness.runtime.registerProcessMetrics(
            incarnation: harness.incarnation,
            binding    : harness.binding
        ) == .duplicate)
        _ = try await harness.sample(at: 3)
        #expect(await harness.incidentCount == 1)

        await harness.runtime.observeExit(harness.incarnation)
        let replacement = try await harness.restart()
        #expect(try await harness.runtime.registerProcessMetrics(
            incarnation: replacement.incarnation,
            binding    : harness.binding
        ) == .registered)
        try await harness.publish(on: replacement, revision: 2)
        _ = try await harness.sample(at: 4)
        #expect(await harness.incidentCount == 2)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.submitAction(harness.request(revision: 2))
        }

        _ = try await harness.sample(at: 5)
        _ = try await harness.runtime.submitAction(harness.request(revision: 2))
    }

    @Test func memoryRecoveryCannotReopenDurablyQuarantinedVersion() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let harness = try await MemoryHarness(footprints: [
            target, target + 1, target, target + 1, target, target + 1, target
        ])

        for second in 0...6 {
            _ = try await harness.sample(at: second)
        }
        #expect(await harness.snapshot?.isQuarantined == true)
        await #expect(throws: AddonFailure.self) {
            try await harness.runtime.submitAction(harness.request())
        }
    }

    @Test func memoryPauseKeepsAcceptedServiceAndReuseButRefusesFreshSource() async throws {
        let binding = ProcessMetricBinding(
            pid               : 54,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
        let target = UInt64(64 * 1_024 * 1_024)
        let source = MemoryReadSource(
            binding    : binding,
            userTicks  : [0, 0],
            systemTicks: [0, 0],
            footprints : [target, target + 1]
        )
        let host = try await InvocationMessageHost.make(
            governor            : ResourceGovernor(),
            minor               : 4,
            maximumEnvelopeBytes: 524_288,
            metricRead          : source.read
        )
        do {
            _ = try await host.runtime.registerProcessMetrics(
                incarnation: host.provider.incarnation,
                binding    : binding
            )
            let oldWork = try await host.runtime.beginServiceInvocation(
                connection: host.consumer,
                grantID   : host.acquisition.grant.id,
                invocation: host.invocation()
            )
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            host.clock.advance(1)
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)

            #expect(try await host.runtime.pumpServiceInvocation(oldWork.id))
            guard case .accepted = try await host.runtime.receiveServiceCompletion(
                oldWork.id,
                connection: host.provider,
                response  : host.response()
            ) else {
                Issue.record("Accepted service work did not complete after memory pause.")
                await host.cleanup()
                return
            }
            let reused = try await host.runtime.acquireService(
                connection  : host.consumer,
                permissionID: host.permissionID,
                lifetime    : .seconds(30)
            )
            #expect(reused.sourceID == host.acquisition.sourceID)

            let scope = try ServiceScope(featureID: "summary", operation: "write")
            _ = try await host.runtime.authorizeService(
                connection           : host.consumer,
                requirementID        : host.contractID,
                scope                : scope,
                partition            : "TEST-ONLY.other-account",
                crossPublisherConsent: true
            )
            let request = try ServiceControlRequest(
                requestID: UUID(),
                action   : .acquire(.requestService(
                    requirementID: host.contractID,
                    scope        : scope
                ))
            )
            let ingress = try #require(host.adapter.stage(
                ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4),
                connection: host.consumer,
                sequence  : 2,
                kind      : .control
            ))
            let startsBefore = host.adapter.starts.count
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer),
                  case .serviceControl(let delivery) = host.adapter.payload(host.consumer.incarnation) else {
                Issue.record("Missing memory admission refusal receipt.")
                await host.cleanup()
                return
            }
            let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(delivery.payload, profile: .v1_4)
            guard case .refused(let code, _) = reply.result else {
                Issue.record("Memory-paused provider committed a fresh source.")
                await host.cleanup()
                return
            }
            #expect(code == .resourceDenied)
            #expect(host.adapter.starts.count == startsBefore)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(
                delivery.receipt,
                connection: host.consumer
            ))
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    @Test func staleDelegatedCPUContributorCannotDiscardCurrentOwnMemory() async throws {
        let providerBinding = metricBinding(1)
        let leafBinding = metricBinding(2)
        let target = UInt64(64 * 1_024 * 1_024)
        let gate = MemoryReadGate()
        let source = DelegatedMemoryReadSource(
            samples: [
                providerBinding.token: [(0, target), (0, target + 1)],
                leafBinding.token    : [(0, 4_096), (0, 4_096)]
            ],
            gatedToken: leafBinding.token,
            gate      : gate
        )
        let host = try await InvocationMessageHost.make(
            governor            : ResourceGovernor(),
            minor               : 4,
            maximumEnvelopeBytes: 524_288,
            dependency          : true,
            metricRead          : source.read
        )
        do {
            let leaf = try #require(host.leafConnection)
            _ = try await activateLeaf(on: host, leaf: leaf)
            _ = try await host.runtime.registerProcessMetrics(
                incarnation: host.provider.incarnation,
                binding    : providerBinding
            )
            _ = try await host.runtime.registerProcessMetrics(
                incarnation: leaf.incarnation,
                binding    : leafBinding
            )
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            host.clock.advance(1)
            let sampling = Task {
                try await host.runtime.sampleResources(reason: .jobBoundary)
            }
            defer { gate.release() }
            #expect(gate.waitForArrival())
            let disabled = MemoryDisableSignal()
            let runtime = host.runtime
            let disabling = Task {
                await AddonRuntime.$cpuDisableCheckpoint.withValue({ owner in
                    if owner == host.leaf { disabled.signal() }
                }) {
                    await runtime.disable(owner: host.leaf)
                }
            }
            #expect(disabled.waitForArrival())
            gate.release()
            let result = try await sampling.value
            await disabling.value
            let provider = try #require(observations(result).first {
                $0.owner == host.provider.identity
            })
            #expect(provider.status == .stale)
            let version = try AddonVersionIdentity(
                verifiedIdentity: host.provider.identity,
                version         : SemanticVersion(1, 0, 0)
            )
            #expect(await host.runtime.resourceHealthSnapshot(for: version)?.moderateIncidentCount == 1)
            await #expect(throws: AddonFailure.self) {
                try await host.runtime.beginServiceInvocation(
                    connection: host.consumer,
                    grantID   : host.acquisition.grant.id,
                    invocation: host.invocation()
                )
            }
            #expect(try await host.runtime.registerProcessMetrics(
                incarnation: host.provider.incarnation,
                binding    : providerBinding
            ) == .duplicate)
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    @Test func severePhysicalContributorDoesNotInvalidateRecipientsReducedCPUCharge() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let severe = UInt64(96 * 1_024 * 1_024 + 1)
        let leafBinding = metricBinding(3)
        let source = DelegatedMemoryReadSource(samples: [
            leafBinding.token: [(0, target), (150_000_000, severe)]
        ])
        let host = try await InvocationMessageHost.make(
            governor            : ResourceGovernor(),
            minor               : 4,
            maximumEnvelopeBytes: 524_288,
            dependency          : true,
            metricRead          : source.read
        )
        do {
            let leaf = try #require(host.leafConnection)
            _ = try await activateLeaf(on: host, leaf: leaf)
            _ = try await host.runtime.registerProcessMetrics(
                incarnation: leaf.incarnation,
                binding    : leafBinding
            )
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            host.clock.advance(1)
            let result = try await host.runtime.sampleResources(reason: .jobBoundary)
            let leafObservation = try #require(observations(result).first {
                $0.owner == leaf.identity
            })
            #expect(leafObservation.classification == .moderate)
            #expect(leafObservation.decision == .stop)
            let provider = try #require(observations(result).first {
                $0.owner == host.provider.identity
            })
            #expect(provider.classification == .moderate)
            #expect(provider.status == .current)
            let version = try AddonVersionIdentity(
                verifiedIdentity: host.provider.identity,
                version         : SemanticVersion(1, 0, 0)
            )
            #expect(await host.runtime.resourceHealthSnapshot(for: version)?.moderateIncidentCount == 1)
            let leafVersion = try AddonVersionIdentity(
                verifiedIdentity: leaf.identity,
                version         : SemanticVersion(1, 0, 0)
            )
            #expect(await host.runtime.resourceHealthSnapshot(for: leafVersion)?.moderateIncidentCount == 0)
            #expect(host.adapter.stopReason(leaf.incarnation) == .stopped)
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    @Test func physicalMemoryPauseDoesNotPropagateToTransitiveConsumerAdmission() async throws {
        let target = UInt64(64 * 1_024 * 1_024)
        let leafBinding = metricBinding(4)
        let source = DelegatedMemoryReadSource(samples: [
            leafBinding.token: [(0, target), (0, target + 1)]
        ])
        let host = try await InvocationMessageHost.make(
            governor            : ResourceGovernor(),
            minor               : 4,
            maximumEnvelopeBytes: 524_288,
            dependency          : true,
            metricRead          : source.read
        )
        do {
            let leaf = try #require(host.leafConnection)
            _ = try await activateLeaf(on: host, leaf: leaf)
            _ = try await host.runtime.registerProcessMetrics(
                incarnation: leaf.incarnation,
                binding    : leafBinding
            )
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            host.clock.advance(1)
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            _ = try await host.runtime.beginServiceInvocation(
                connection: host.consumer,
                grantID   : host.acquisition.grant.id,
                invocation: host.invocation()
            )
            let leafVersion = try AddonVersionIdentity(
                verifiedIdentity: leaf.identity,
                version         : SemanticVersion(1, 0, 0)
            )
            #expect(await host.runtime.resourceHealthSnapshot(for: leafVersion)?.moderateIncidentCount == 1)
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    private func activateLeaf(
        on host: InvocationMessageHost,
        leaf   : RuntimeConnection
    ) async throws -> ServiceAcquisition {
        let permission = try await host.runtime.authorizeService(
            connection           : host.provider,
            requirementID        : "com.example.runtime.leaf",
            scope                : ServiceScope(featureID: "localTimer", operation: "read"),
            partition            : "TEST-ONLY.account",
            crossPublisherConsent: true
        )
        let acquisition = try await host.runtime.acquireService(
            connection  : host.provider,
            permissionID: permission,
            lifetime    : .seconds(30)
        )
        #expect(try await host.runtime.receiveSourceStartupCompletion(
            acquisition.sourceID,
            connection: leaf
        ))
        return acquisition
    }

    private func observations(
        _ result: AddonRuntime.ResourceSampleResult
    ) -> [AddonRuntime.ResourceOwnerObservation] {
        guard case .sampled(let values) = result else { return [] }
        return values
    }

    private func metricBinding(_ index: UInt8) -> ProcessMetricBinding {
        ProcessMetricBinding(
            pid               : Int32(60 + index),
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, index)),
            token             : UUID(uuid: (2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, index)),
            clockDomain       : UUID(uuid: (3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3))
        )
    }
}
