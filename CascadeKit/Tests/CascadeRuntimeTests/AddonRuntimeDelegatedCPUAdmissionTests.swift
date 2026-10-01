//
//  AddonRuntimeDelegatedCPUAdmissionTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonRuntimeDelegatedCPUAdmissionTests {
    @Test func pausedConsumerCannotLaunchMissingProviderForNewInterest() async throws {
        let fixture = try await ConsumerAdmissionFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        let incident = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(incident)?.classification == .moderate)
        do {
            _ = try await fixture.runtime.acquireService(
                connection  : fixture.consumer,
                permissionID: fixture.permissionID,
                lifetime    : .seconds(30)
            )
            Issue.record("A paused consumer created a new canonical interest.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(fixture.adapter.lastStart(owner: fixture.providerID) == nil)
        #expect(await fixture.governor.usage(.providers, owner: fixture.providerID) == 0)
    }

    @Test func incidentDuringProviderReservationRollsBackUnexposedInterest() async throws {
        let fixture = try await ConsumerAdmissionFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await fixture.resources.armProviderAdmission()
        let acquisition = Task {
            try await fixture.runtime.acquireService(
                connection  : fixture.consumer,
                permissionID: fixture.permissionID,
                lifetime    : .seconds(30)
            )
        }
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("Provider reservation gate was never reached or released.")
                await fixture.resources.releaseGate()
            } catch is CancellationError {
                // The causal gate finished before its bounded watchdog.
            } catch {
                Issue.record("Provider reservation watchdog failed: \(error)")
                await fixture.resources.releaseGate()
            }
        }
        defer {
            watchdog.cancel()
            Task { await fixture.resources.releaseGate() }
        }
        #expect(await fixture.resources.waitForArrival())
        fixture.clock.set(fixture.instant(1))
        let incident = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(firstObservation(incident)?.classification == .moderate)
        await fixture.resources.releaseGate()
        do {
            _ = try await acquisition.value
            Issue.record("A new interest escaped after its consumer paused during reservation.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(fixture.adapter.lastStart(owner: fixture.providerID) == nil)
        #expect(await fixture.governor.usage(.providers, owner: fixture.providerID) == 0)
    }

    @Test func v14ConsumerPauseAfterBrokerCommitReportsUnknown() async throws {
        let binding = ProcessMetricBinding(
            pid               : 49,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
        let reader = ConsumerMetricReadSource(binding: binding)
        let host = try await InvocationMessageHost.make(
            governor            : ResourceGovernor(),
            minor               : 4,
            maximumEnvelopeBytes: 524_288,
            metricRead          : reader.read
        )
        do {
            _ = try await host.runtime.registerProcessMetrics(
                incarnation: host.consumer.incarnation,
                binding    : binding
            )
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
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
                action   : .acquire(.requestService(requirementID: host.contractID, scope: scope))
            )
            let ingress = try #require(host.adapter.stage(
                ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4),
                connection: host.consumer,
                sequence  : 2,
                kind      : .control
            ))
            let incidentObserved = CPUIncidentObserved()
            let admission = await AddonRuntime.$serviceSubscriptionObserver.withValue({ point in
                guard point == .acquisitionCommitted else { return }
                host.clock.advance(1)
                let result = try? await host.runtime.sampleResources(reason: .jobBoundary)
                if let result,
                   case .sampled(let owners) = result,
                   owners.contains(where: { $0.owner == host.consumer.identity && $0.classification == .moderate }) {
                    incidentObserved.mark()
                }
            }) {
                await host.runtime.receiveServiceControl(ingress, connection: host.consumer)
            }
            #expect(incidentObserved.value)
            guard case .admitted = admission,
                  case .serviceControl(let ack) = host.adapter.payload(host.consumer.incarnation) else {
                Issue.record("The committed v1.4 control did not return an acknowledgement.")
                await host.cleanup()
                return
            }
            let admissionReply = try ServiceSubscriptionFrameCodec.decodeControlReply(ack.payload, profile: .v1_4)
            #expect(admissionReply.phase == .admission)
            #expect(admissionReply.result == .accepted)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(ack.receipt, connection: host.consumer))
            guard case .serviceControl(let terminal) = host.adapter.payload(host.consumer.incarnation) else {
                Issue.record("The committed v1.4 control did not return a terminal outcome.")
                await host.cleanup()
                return
            }
            #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(terminal.payload, profile: .v1_4).result == .outcomeUnknown)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: host.consumer))
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    private func firstObservation(
        _ result: AddonRuntime.ResourceSampleResult
    ) -> AddonRuntime.ResourceOwnerObservation? {
        guard case .sampled(let values) = result else { return nil }
        return values.first
    }

    private struct ConsumerAdmissionFixture {
        let runtime: AddonRuntime
        let governor: ResourceGovernor
        let resources: ProviderAdmissionGate
        let adapter: RecordingRuntimeAdapter
        let clock: MutableRuntimeClock
        let consumer: RuntimeConnection
        let providerID: AddonID
        let permissionID: UUID

        init() async throws {
            let consumerAddon = try installedFixture("consumer", publisher: "TEST-ONLY.shared")
            let providerAddon = try installedFixture("focus", publisher: "TEST-ONLY.shared")
            providerID = providerAddon.manifest.id
            governor = ResourceGovernor()
            resources = ProviderAdmissionGate(target: governor)
            adapter = RecordingRuntimeAdapter()
            clock = MutableRuntimeClock(instant: RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000),
                monotonic: .zero
            ))
            let binding = ProcessMetricBinding(
                pid               : 47,
                birthAbsoluteTicks: 100,
                executableUUID    : UUID(),
                token             : UUID(),
                clockDomain       : UUID()
            )
            let reader = ConsumerMetricReadSource(binding: binding)
            runtime = try await AddonRuntime.make(
                catalog    : [consumerAddon, providerAddon],
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [consumerAddon.manifest.id: [], providerAddon.manifest.id: []],
                    explicitBindings: []
                ),
                governor              : governor,
                resourceAccess        : resources,
                serviceDecisionFactory: { $0 },
                adapter               : adapter,
                clock                 : clock,
                metricRead            : reader.read
            )
            let offer = try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
            let launch = try await runtime.requestLaunch(owner: consumerAddon.manifest.id)
            consumer = try await runtime.attach(launchID: launch, offer: offer)
            _ = try await runtime.registerProcessMetrics(
                incarnation: consumer.incarnation,
                binding    : binding
            )
            permissionID = try await runtime.authorizeService(
                connection           : consumer,
                requirementID        : "com.example.focus.sessions",
                scope                : ServiceScope(featureID: "summary", operation: "read"),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )
        }

        func instant(_ second: Int) -> RuntimeInstant {
            RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000 + Double(second)),
                monotonic: .seconds(second)
            )
        }
    }
}
