//
//  AddonRuntimeCPUAdmissionTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonRuntimeCPUAdmissionTests {
    @Test func freshActionsPauseWithoutRetentionAndPositiveCreditReopens() async throws {
        let fixture = try await CPUAdmissionFixture()
        let queued = try fixture.request()
        #expect(try await fixture.runtime.submitAction(queued) == .admitted)
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)

        fixture.clock.set(fixture.instant(1))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let denied = try fixture.request()
        let before = await fixture.governor.usage(.retainedStateBytes, owner: fixture.action.owner)
        do {
            _ = try await fixture.runtime.submitAction(denied)
            Issue.record("Fresh action should be denied while CPU credit is exhausted.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(await fixture.runtime.actionState(denied.requestID, owner: fixture.action.owner) == nil)
        #expect(await fixture.governor.usage(.retainedStateBytes, owner: fixture.action.owner) == before)
        #expect(try await fixture.runtime.submitAction(queued) == .duplicate(.queued))
        #expect(try await fixture.runtime.pumpReady())

        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let stillDenied = try fixture.request()
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.submitAction(stillDenied)
        }
        fixture.clock.set(fixture.instant(11))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.submitAction(denied)
        }
        fixture.clock.set(fixture.instant(12))
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.submitAction(denied)
        }
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let delivery = try #require(fixture.adapter.lastAction)
        #expect(try await fixture.runtime.receiveActionCompletion(
            delivery,
            connection: fixture.connection,
            outcome   : .completed(payload: Data([9]))
        ))
        #expect(try await fixture.runtime.submitAction(denied) == .admitted)
    }

    @Test func unavailableMeasurementCannotReopenPausedOwner() async throws {
        let fixture = try await CPUAdmissionFixture(userTicks: [0, 150_000_000, nil, 150_000_000])
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(12))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let denied = try fixture.request()
        do {
            _ = try await fixture.runtime.submitAction(denied)
            Issue.record("Unknown CPU accounting reopened admission.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.submitAction(denied)
        }
    }

    @Test func quarantinedVersionCannotReopenFromLaterCredit() async throws {
        let fixture = try await CPUAdmissionFixture(userTicks: [
            0, 150_000_000, 160_000_000, 170_000_000, 170_000_000
        ])
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        for second in 1...3 {
            fixture.clock.set(fixture.instant(second))
            _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        }
        let version = try AddonVersionIdentity(
            verifiedIdentity: fixture.connection.identity,
            version         : SemanticVersion(1, 0, 0)
        )
        #expect(await fixture.runtime.resourceHealthSnapshot(for: version)?.isQuarantined == true)
        fixture.clock.set(fixture.instant(15))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        let denied = try fixture.request()
        do {
            _ = try await fixture.runtime.submitAction(denied)
            Issue.record("Quarantined owner admitted new work after time elapsed.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
    }

    @Test func pausedProviderRejectsNewInvocationButReusesStartedSource() async throws {
        let fixture = try await CPUAdmissionServiceFixture()
        let oldWork = try await fixture.runtime.beginServiceInvocation(
            connection: fixture.consumer,
            grantID   : fixture.acquisition.grant.id,
            invocation: fixture.invocation()
        )
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        #expect(try await fixture.runtime.pumpServiceInvocation(oldWork.id))
        let oldResult = try await fixture.runtime.receiveServiceCompletion(
            oldWork.id,
            connection: fixture.provider,
            response  : ServiceResponse(
                schemaVersion: 1,
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([2])
            )
        )
        guard case .accepted = oldResult else {
            Issue.record("Previously admitted service work did not complete after CPU pause.")
            return
        }
        let consumer = fixture.consumer.identity.addonID
        let provider = fixture.provider.identity.addonID
        let commandsBefore = await fixture.governor.usage(.commands, owner: consumer)
        let jobsBefore = await fixture.governor.usage(.jobs, owner: provider)
        do {
            _ = try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumer,
                grantID   : fixture.acquisition.grant.id,
                invocation: fixture.invocation()
            )
            Issue.record("Paused provider accepted a fresh invocation.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(await fixture.governor.usage(.commands, owner: consumer) == commandsBefore)
        #expect(await fixture.governor.usage(.jobs, owner: provider) == jobsBefore)

        let reused = try await fixture.runtime.acquireService(
            connection  : fixture.consumer,
            permissionID: fixture.permissionID,
            lifetime    : .seconds(30)
        )
        #expect(reused.sourceID == fixture.acquisition.sourceID)
        #expect(reused.decisions.isEmpty)
    }

    @Test func providerRestartKeepsPauseAndRefusesFreshSourceStart() async throws {
        let fixture = try await CPUAdmissionServiceFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        fixture.clock.set(fixture.instant(1))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await fixture.runtime.observeExit(fixture.provider.incarnation)
        let launch = try await fixture.runtime.requestLaunch(owner: fixture.provider.identity.addonID)
        _ = try await fixture.runtime.attach(
            launchID: launch,
            offer   : ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
        )
        let jobsBefore = await fixture.governor.usage(.jobs, owner: fixture.provider.identity.addonID)
        do {
            _ = try await fixture.runtime.acquireService(
                connection  : fixture.consumer,
                permissionID: fixture.permissionID,
                lifetime    : .seconds(30)
            )
            Issue.record("Paused provider accepted a source restart.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(await fixture.governor.usage(.jobs, owner: fixture.provider.identity.addonID) == jobsBefore)
    }

    @Test func incidentDuringActionGrowthRefundsReservationBeforeCommit() async throws {
        let fixture = try await CPUAdmissionFixture()
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await fixture.access.armResize()
        let request = try fixture.request()
        let submitting = Task { try await fixture.runtime.submitAction(request) }
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(5))
                Issue.record("The action growth gate did not arrive within five seconds.")
                await fixture.access.releaseGate()
            } catch {
                // Cancellation follows the observed gate and is not a timeout.
            }
        }
        defer {
            watchdog.cancel()
            submitting.cancel()
            Task { await fixture.access.releaseGate() }
        }
        await fixture.access.waitForArrival()
        fixture.clock.set(fixture.instant(1))
        _ = try await fixture.runtime.sampleResources(reason: .jobBoundary)
        await fixture.access.releaseGate()
        do {
            _ = try await submitting.value
            Issue.record("Admission committed after a CPU incident during growth.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(await fixture.runtime.actionState(request.requestID, owner: fixture.action.owner) == nil)
        #expect(await fixture.governor.usage(.commands, owner: fixture.action.owner) == 0)
    }

    @Test func framedNewSourceIsRefusedBeforeBrokerCommit() async throws {
        let binding = ProcessMetricBinding(
            pid               : 54,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
        let source = CPUAdmissionReadSource(binding: binding)
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
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            host.clock.advance(1)
            _ = try await host.runtime.sampleResources(reason: .jobBoundary)
            let scope = try ServiceScope(featureID: "summary", operation: "write")
            _ = try await host.runtime.authorizeService(
                connection         : host.consumer,
                requirementID      : host.contractID,
                scope              : scope,
                partition          : "TEST-ONLY.other-account",
                crossPublisherConsent: true
            )
            let request = try ServiceControlRequest(
                requestID: UUID(),
                action   : .acquire(.requestService(
                    requirementID: host.contractID,
                    scope        : scope
                ))
            )
            let encoded = try ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4)
            let ingress = try #require(host.adapter.stage(
                encoded,
                connection: host.consumer,
                sequence  : 2,
                kind      : .control
            ))
            let startsBefore = host.adapter.starts.count
            let jobsBefore = await host.governor.usage(.jobs, owner: host.provider.identity.addonID)
            guard case .admitted = await host.runtime.receiveServiceControl(ingress, connection: host.consumer),
                  case .serviceControl(let delivery) = host.adapter.payload(host.consumer.incarnation) else {
                Issue.record("No canonical refusal receipt for the paused provider.")
                await host.cleanup()
                return
            }
            let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(delivery.payload, profile: .v1_4)
            guard case .refused(let code, _) = reply.result else {
                Issue.record("The paused provider did not refuse the new source before commit.")
                await host.cleanup()
                return
            }
            #expect(code == .resourceDenied)
            #expect(host.adapter.starts.count == startsBefore)
            #expect(host.adapter.payload(host.provider.incarnation) == nil)
            #expect(await host.governor.usage(.jobs, owner: host.provider.identity.addonID) == jobsBefore)
            #expect(await host.runtime.receiveServiceSubscriptionReceipt(
                delivery.receipt,
                connection: host.consumer
            ))
            host.clock.advance(1)
            _ = try await host.runtime.serviceDeadlines()
            #expect(host.adapter.payload(host.provider.incarnation) == nil)
            await host.cleanup()
        } catch {
            await host.cleanup()
            throw error
        }
    }

    @Test func oneOwnersCPUIncidentDoesNotCloseAnotherOwnersActionAdmission() async throws {
        let first = try ActionFixture()
        let second = try ActionFixture(ownerName: "com.example.otheractions")
        let installed = try [first.context().installed, second.context().installed]
        let governor = ResourceGovernor()
        let adapter = RecordingRuntimeAdapter()
        let clock = MutableRuntimeClock(instant: RuntimeInstant(wall: first.wall, monotonic: .zero))
        let binding = ProcessMetricBinding(
            pid               : 55,
            birthAbsoluteTicks: 100,
            executableUUID    : UUID(),
            token             : UUID(),
            clockDomain       : UUID()
        )
        let source = CPUAdmissionReadSource(binding: binding)
        let runtime = try await AddonRuntime.make(
            catalog    : installed,
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [first.owner: [], second.owner: []],
                explicitBindings: []
            ),
            governor  : governor,
            adapter   : adapter,
            clock     : clock,
            metricRead: source.read
        )
        func prepare(_ action: ActionFixture) async throws -> (PublicationID, RuntimeConnection) {
            let publicationID = try await runtime.assignPublication(
                owner     : action.owner,
                featureID : "controls",
                instanceID: UUID()
            )
            let launch = try await runtime.requestLaunch(owner: action.owner)
            let connection = try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : 0,
                    contentSchemas: [1]
                )
            )
            _ = try await receivePublicationOutput(
                runtime   : runtime,
                adapter   : adapter,
                output    : ProviderOutput(
                    schemaVersion: 1,
                    publications: [try Publication(
                        id         : publicationID,
                        revision   : 1,
                        kind       : .widget,
                        content    : action.presentation(),
                        timeline   : nil,
                        expiresAt  : action.wall.addingTimeInterval(100),
                        stalePolicy: .remove
                    )],
                    operations: [],
                    completion: nil,
                    checkpoint: nil
                ),
                connection: connection,
                sequence  : 1
            )
            return (publicationID, connection)
        }
        let (firstPublication, firstConnection) = try await prepare(first)
        let (secondPublication, _) = try await prepare(second)
        _ = try await runtime.registerProcessMetrics(
            incarnation: firstConnection.incarnation,
            binding    : binding
        )
        _ = try await runtime.sampleResources(reason: .jobBoundary)
        clock.set(RuntimeInstant(wall: first.wall.addingTimeInterval(1), monotonic: .seconds(1)))
        _ = try await runtime.sampleResources(reason: .jobBoundary)
        func request(_ publicationID: PublicationID) throws -> ActionRequest {
            try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : publicationID,
                actionID        : "pause",
                input           : Data([7]),
                deadline        : first.wall.addingTimeInterval(20),
                observedRevision: 1
            )
        }
        do {
            _ = try await runtime.submitAction(request(firstPublication))
            Issue.record("Overspending owner accepted new work.")
        } catch let error as AddonFailure {
            #expect(error.code == .resourceDenied)
        }
        #expect(try await runtime.submitAction(request(secondPublication)) == .admitted)
    }

    private struct CPUAdmissionFixture {
        let action: ActionFixture
        let runtime: AddonRuntime
        let governor: ResourceGovernor
        let access: GatedRuntimeResourceAccess
        let adapter: RecordingRuntimeAdapter
        let clock: MutableRuntimeClock
        let publicationID: PublicationID
        let connection: RuntimeConnection

        init(userTicks: [UInt64?] = [0, 150_000_000, 150_000_000, 150_000_000, 150_000_000]) async throws {
            action = try ActionFixture()
            let installed = try action.context().installed
            governor = ResourceGovernor()
            access = GatedRuntimeResourceAccess(target: governor)
            adapter = RecordingRuntimeAdapter()
            clock = MutableRuntimeClock(instant: RuntimeInstant(wall: action.wall, monotonic: .zero))
            let binding = ProcessMetricBinding(
                pid               : 42,
                birthAbsoluteTicks: 100,
                executableUUID    : UUID(),
                token             : UUID(),
                clockDomain       : UUID()
            )
            let source = CPUAdmissionReadSource(binding: binding, userTicks: userTicks)
            runtime = try await AddonRuntime.make(
                catalog    : [installed],
                environment: HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [action.owner: []],
                    explicitBindings: []
                ),
                governor              : governor,
                resourceAccess        : access,
                serviceDecisionFactory: { $0 },
                adapter               : adapter,
                clock                 : clock,
                metricRead            : source.read
            )
            publicationID = try await runtime.assignPublication(
                owner     : action.owner,
                featureID : "controls",
                instanceID: UUID()
            )
            let launch = try await runtime.requestLaunch(owner: action.owner)
            connection = try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : 0,
                    contentSchemas: [1]
                )
            )
            _ = try await receivePublicationOutput(
                runtime   : runtime,
                adapter   : adapter,
                output    : ProviderOutput(
                    schemaVersion: 1,
                    publications: [try Publication(
                        id         : publicationID,
                        revision   : 1,
                        kind       : .widget,
                        content    : action.presentation(),
                        timeline   : nil,
                        expiresAt  : action.wall.addingTimeInterval(100),
                        stalePolicy: .remove
                    )],
                    operations: [],
                    completion: nil,
                    checkpoint: nil
                ),
                connection: connection,
                sequence  : 1
            )
            _ = try await runtime.registerProcessMetrics(
                incarnation: connection.incarnation,
                binding    : binding
            )
        }

        func request() throws -> ActionRequest {
            try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : publicationID,
                actionID        : "pause",
                input           : Data([7]),
                deadline        : action.wall.addingTimeInterval(20),
                observedRevision: 1
            )
        }

        func instant(_ second: Int) -> RuntimeInstant {
            RuntimeInstant(
                wall     : action.wall.addingTimeInterval(Double(second)),
                monotonic: .seconds(second)
            )
        }
    }

    private struct CPUAdmissionServiceFixture {
        let runtime: AddonRuntime
        let governor: ResourceGovernor
        let adapter: RecordingRuntimeAdapter
        let clock: MutableRuntimeClock
        let consumer: RuntimeConnection
        let provider: RuntimeConnection
        let permissionID: UUID
        let acquisition: ServiceAcquisition

        init() async throws {
            let consumerAddon = try installedFixture("consumer", publisher: "TEST-ONLY.shared")
            let providerAddon = try installedFixture("focus", publisher: "TEST-ONLY.shared")
            governor = ResourceGovernor()
            adapter = RecordingRuntimeAdapter()
            clock = MutableRuntimeClock(instant: RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000),
                monotonic: .zero
            ))
            let binding = ProcessMetricBinding(
                pid               : 53,
                birthAbsoluteTicks: 100,
                executableUUID    : UUID(),
                token             : UUID(),
                clockDomain       : UUID()
            )
            let source = CPUAdmissionReadSource(binding: binding)
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
                resourceAccess        : governor,
                serviceDecisionFactory: { $0 },
                adapter               : adapter,
                clock                 : clock,
                metricRead            : source.read
            )
            let offer = try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : 0,
                contentSchemas: [1]
            )
            let launch = try await runtime.requestLaunch(owner: consumerAddon.manifest.id)
            consumer = try await runtime.attach(launchID: launch, offer: offer)
            permissionID = try await runtime.authorizeService(
                connection         : consumer,
                requirementID      : "com.example.focus.sessions",
                scope              : ServiceScope(featureID: "summary", operation: "read"),
                partition          : "TEST-ONLY.account",
                crossPublisherConsent: true
            )
            do {
                _ = try await runtime.acquireService(
                    connection  : consumer,
                    permissionID: permissionID,
                    lifetime    : .seconds(30)
                )
                Issue.record("Expected the canonical missing provider path to start.")
            } catch let error as AddonFailure {
                #expect(error.code == .dependencyUnavailable)
            }
            let providerStart = try #require(adapter.lastStart(owner: providerAddon.manifest.id))
            provider = try await runtime.attach(launchID: providerStart.launchID, offer: offer)
            acquisition = try await runtime.acquireService(
                connection  : consumer,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
            #expect(try await runtime.receiveSourceStartupCompletion(
                acquisition.sourceID,
                connection: provider
            ))
            _ = try await runtime.registerProcessMetrics(
                incarnation: provider.incarnation,
                binding    : binding
            )
        }

        func instant(_ second: Int) -> RuntimeInstant {
            RuntimeInstant(
                wall     : Date(timeIntervalSince1970: 2_000_000_000 + Double(second)),
                monotonic: .seconds(second)
            )
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
    }
}
