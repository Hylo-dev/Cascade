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

private final class CPUIncidentObserved: @unchecked Sendable {
    private let lock = NSLock()
    private var observed = false

    func mark() { lock.withLock { observed = true } }
    var value: Bool { lock.withLock { observed } }
}

private final class ConsumerMetricReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private let binding: ProcessMetricBinding
    private var count = 0

    init(binding: ProcessMetricBinding) {
        self.binding = binding
    }

    func read(_ actual: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            guard actual == binding else { return .unavailable(.identityMismatch) }
            count += 1
            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : count == 1 ? 0 : 150_000_000,
                systemTicks   : 0,
                footprintBytes: 4_096,
                window        : ProcessMetricWindow(
                    startTicks: UInt64(count) * 100 + 100,
                    endTicks  : UInt64(count) * 100 + 101
                ),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}

/// ProviderAdmissionGate forwards the real provider reservation, then delays
/// only its return. This exposes the runtime's exact post-await CPU check.
private actor ProviderAdmissionGate: RuntimeResourceAccess {
    nonisolated let resourceGovernorTarget: ResourceGovernor
    private var shouldGateProvider = false
    private var hasArrived = false
    private var isReleased = false
    private var arrivalContinuation: CheckedContinuation<Bool, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(target: ResourceGovernor) {
        resourceGovernorTarget = target
    }

    func armProviderAdmission() {
        shouldGateProvider = true
        hasArrived = false
        isReleased = false
    }

    func waitForArrival() async -> Bool {
        if hasArrived || isReleased { return hasArrived }
        return await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func releaseGate() {
        isReleased = true
        arrivalContinuation?.resume(returning: hasArrived)
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let reservation = try await resourceGovernorTarget.admit(request, owner: owner)
        guard case .provider = request, shouldGateProvider else { return reservation }
        shouldGateProvider = false
        hasArrived = true
        arrivalContinuation?.resume(returning: true)
        arrivalContinuation = nil
        if !isReleased {
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return reservation
    }

    func release(
        _ reservationID: UUID,
        owner           : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(reservationID, owner: owner)
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        toBytes bytes   : Int
    ) async -> Bool {
        await resourceGovernorTarget.reduceStateReservation(reservationID, owner: owner, toBytes: bytes)
    }

    func resizeStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeStateReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }

    func resizeDiskReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }
}
