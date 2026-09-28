//
//  AddonRuntimeSlotOwnershipTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite
struct AddonRuntimeSlotOwnershipTests {
    /// Fixture uses real action dispatch, governor admission and bounded adapter storage.
    private struct Fixture {
        let action             : ActionFixture
        let governor           : ResourceGovernor
        let access             : GatedRuntimeResourceAccess
        let adapter            : RecordingRuntimeAdapter
        let runtime            : AddonRuntime
        let publicationID      : PublicationID
        let connection         : RuntimeConnection
        let directProcessGrowth: Int

        init() async throws {
            action = try ActionFixture()
            governor = ResourceGovernor()
            access = GatedRuntimeResourceAccess(target: governor)
            adapter = RecordingRuntimeAdapter()
            runtime = try await AddonRuntime.make(
                catalog    : [action.context().installed],
                environment: HostEnvironment(
                    osVersion: SemanticVersion(
                        14,
                        0,
                        0
                    ),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [action.owner: []],
                    explicitBindings: []
                ),
                governor              : governor,
                resourceAccess        : access,
                serviceDecisionFactory: { $0 },
                adapter               : adapter,
                clock                 : FixedRuntimeClock(
                    instant: RuntimeInstant(
                        wall     : action.wall,
                        monotonic: .zero
                    )
                ),
                maximumEnvelopeBytes: 8_192
            )
            publicationID = try await runtime.assignPublication(
                owner     : action.owner,
                featureID : "controls",
                instanceID: UUID()
            )
            let beforeLaunch = try #require(await runtime.diagnostics(owner: action.owner)).reservedStateBytes
            let launch       = try await runtime.requestLaunch(owner: action.owner)
            directProcessGrowth =
                try #require(await runtime.diagnostics(owner: action.owner)).reservedStateBytes - beforeLaunch
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
                runtime: runtime,
                adapter: adapter,
                output : ProviderOutput(
                    schemaVersion: 1,
                    publications : [
                        Publication(
                            id         : publicationID,
                            revision   : 1,
                            kind       : .widget,
                            content    : action.presentation(),
                            timeline   : nil,
                            expiresAt  : action.wall.addingTimeInterval(100),
                            stalePolicy: .remove
                        )
                    ],
                    operations: [],
                    completion: nil,
                    checkpoint: nil
                ),
                connection: connection,
                sequence  : 1
            )
        }

        func request(revision: UInt64 = 1) throws -> ActionRequest {
            try ActionRequest(
                schemaVersion   : 1,
                requestID       : UUID(),
                publicationID   : publicationID,
                actionID        : "pause",
                input           : Data([7]),
                deadline        : action.wall.addingTimeInterval(20),
                observedRevision: revision
            )
        }
    }

    @Test
    func actualAcknowledgmentDropsPayloadWhileJobRemainsAndLateAIsHarmlessToB() async throws {
        let fixture = try await Fixture()
        let first   = try fixture.request()
        _ = try await fixture.runtime.submitAction(first)
        #expect(try await fixture.runtime.pumpReady())
        let deliveryA = try #require(fixture.adapter.lastAction)
        #expect(
            try await fixture.runtime.receiveAcknowledgment(
                deliveryA,
                connection: fixture.connection
            )
        )
        #expect(fixture.adapter.lastAction == nil)
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.action.owner
            ) == 1
        )
        #expect(
            await fixture.runtime.diagnostics(owner: fixture.action.owner)?.hasOutstandingDelivery == false
        )
        let second = try fixture.request()
        _ = try await fixture.runtime.submitAction(second)
        #expect(try await fixture.runtime.pumpReady() == false)
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.action.owner
            ) == 1
        )
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                deliveryA,
                connection: fixture.connection,
                outcome   : .completed(payload: Data([1]))
            )
        )
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.action.owner
            ) == 0
        )
        #expect(try await fixture.runtime.pumpReady())
        let deliveryB = try #require(fixture.adapter.lastAction)
        #expect(deliveryA.ticket.id != deliveryB.ticket.id)
        #expect(
            try await fixture.runtime.receiveAcknowledgment(
                deliveryA,
                connection: fixture.connection
            ) == false
        )
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                deliveryA,
                connection: fixture.connection,
                outcome   : .completed(payload: Data([1]))
            ) == false
        )
        #expect(fixture.adapter.lastAction == deliveryB)
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                deliveryB,
                connection: fixture.connection,
                outcome   : .completed(payload: Data([2]))
            )
        )
        #expect(fixture.adapter.lastAction == nil)
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.action.owner
            ) == 0
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }
    @Test(arguments: [false, true])
    func publicationCompletionRoutesReleaseOnlyTheirActionCredit(completionOnly: Bool) async throws {
        let fixture = try await Fixture()
        _ = try await fixture.runtime.submitAction(fixture.request())
        #expect(try await fixture.runtime.pumpReady())
        let delivery     = try #require(fixture.adapter.lastAction)
        let publications =
            completionOnly
            ? []
            : [
                try Publication(
                    id         : fixture.publicationID,
                    revision   : 2,
                    kind       : .widget,
                    content    : fixture.action.presentation(),
                    timeline   : nil,
                    expiresAt  : fixture.action.wall.addingTimeInterval(100),
                    stalePolicy: .remove
                )
            ]
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : publications,
            operations   : [],
            completion   : .action(
                requestID: delivery.ticket.request.requestID,
                outcome  : .completed(payload: Data([3]))
            ),
            checkpoint: nil
        )
        _ = try await receivePublicationOutput(
            runtime   : fixture.runtime,
            adapter   : fixture.adapter,
            output    : output,
            connection: fixture.connection,
            sequence  : 2
        )
        #expect(fixture.adapter.lastAction == nil)
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.action.owner
            ) == 0
        )
        #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        _ = try await fixture.runtime.submitAction(fixture.request(revision: completionOnly ? 1 : 2))
        #expect(try await fixture.runtime.pumpReady())
        let newer = try #require(fixture.adapter.lastAction)
        await #expect(throws: AddonFailure.self) {
            _ = try await receivePublicationOutput(
                runtime   : fixture.runtime,
                adapter   : fixture.adapter,
                output    : output,
                connection: fixture.connection,
                sequence  : 3
            )
        }
        #expect(fixture.adapter.lastAction == newer)
        #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        _ = try await fixture.runtime.receiveActionCompletion(
            newer,
            connection: fixture.connection,
            outcome   : .completed(payload: Data())
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test(arguments: [false, true])
    func ordinaryClaimProtectsBothStagedAndTransferredAdapterLifetime(refund: Bool) async throws {
        let fixture = try await Fixture()
        let output  = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : nil,
            checkpoint   : nil
        )
        let ingress = try #require(
            fixture.adapter.stageIngress(
                output,
                incarnation: fixture.connection.incarnation
            )
        )
        if refund { await fixture.access.armRelease() } else { await fixture.access.armTemporaryMemory() }
        let receiving = Task {
            try await fixture.runtime.receivePublicationOutput(
                ingress,
                connection: fixture.connection,
                sequence  : 2
            )
        }
        await fixture.access.waitForArrival()
        do {
            try #require(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
            #expect(fixture.adapter.ingressIsTransferred(ingress) == refund)
            let attempts = fixture.adapter.ingressTakeAttempts
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.receivePublicationOutput(
                    ingress,
                    connection: fixture.connection,
                    sequence  : 2
                )
            }
            #expect(fixture.adapter.ingressTakeAttempts == attempts)
            #expect(fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
            #expect(
                fixture.adapter.stageIngress(
                    output,
                    incarnation: fixture.connection.incarnation
                ) == nil
            )
        } catch {
            await fixture.access.releaseGate()
            _ = await receiving.result
            throw error
        }
        await fixture.access.releaseGate()
        guard case .committed = try await receiving.value else {
            Issue.record("Expected accepted output")
            return
        }
        #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        let next = try #require(
            fixture.adapter.stageIngress(
                output,
                incarnation: fixture.connection.incarnation
            )
        )
        _ = try await fixture.runtime.receivePublicationOutput(
            next,
            connection: fixture.connection,
            sequence  : 3
        )
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test
    func admissionRefusalRejectsOnlyStagedIngressAndWrongIncarnationCannotTake() async throws {
        let fixture = try await Fixture()
        let output  = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : nil,
            checkpoint   : nil
        )
        let request = try fixture.request()
        await fixture.access.armResize()
        let submitting = Task { try await fixture.runtime.submitAction(request) }
        await fixture.access.waitForArrival()
        do {
            let ingress = try #require(
                fixture.adapter.stageIngress(
                    output,
                    incarnation: fixture.connection.incarnation
                )
            )
            let attempts = fixture.adapter.ingressTakeAttempts
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.receivePublicationOutput(
                    ingress,
                    connection: fixture.connection,
                    sequence  : 2
                )
            }
            #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
            #expect(fixture.adapter.ingressTakeAttempts == attempts)
        } catch {
            await fixture.access.releaseGate()
            _ = await submitting.result
            throw error
        }
        await fixture.access.releaseGate()
        _ = try await submitting.value
        let forged = RuntimeIngressHandle(
            token           : UUID(),
            incarnation     : RuntimeIncarnation(),
            encodedBytes    : 1,
            isCompletionOnly: false
        )
        await #expect(throws: AddonFailure.self) {
            try await fixture.runtime.receivePublicationOutput(
                forged,
                connection: fixture.connection,
                sequence  : 2
            )
        }
        #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        await fixture.runtime.stop()
        await fixture.runtime.observeExit(fixture.connection.incarnation)
    }

    @Test(arguments: [false, true])
    func stopOrExitDuringTransferCannotFreeAnotherInvocationOrRefundProcessEarly(exit: Bool) async throws {
        let fixture = try await Fixture()
        let output  = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : nil,
            checkpoint   : nil
        )
        let ingress = try #require(
            fixture.adapter.stageIngress(
                output,
                incarnation: fixture.connection.incarnation
            )
        )
        await fixture.access.armRelease()
        let receiving = Task {
            try await fixture.runtime.receivePublicationOutput(
                ingress,
                connection: fixture.connection,
                sequence  : 2
            )
        }
        await fixture.access.waitForArrival()
        #expect(fixture.adapter.ingressIsTransferred(ingress))
        if exit {
            await fixture.runtime.observeExit(fixture.connection.incarnation)
        } else {
            _ = await fixture.runtime.requestStop()
        }
        #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        #expect(
            fixture.adapter.stageIngress(
                output,
                incarnation: fixture.connection.incarnation
            ) == nil
        )
        // Physical capacity survives even observed exit until the accepted cleanup drains.
        #expect(
            await fixture.governor.usage(
                .providers,
                owner: fixture.action.owner
            ) == 1
        )
        await fixture.access.releaseGate()
        _ = try await receiving.value
        if !exit {
            #expect(
                await fixture.governor.usage(
                    .providers,
                    owner: fixture.action.owner
                ) == 1
            )
            await fixture.runtime.observeExit(fixture.connection.incarnation)
        }
        await fixture.runtime.stop()
        #expect(
            await fixture.governor.usage(
                .providers,
                owner: fixture.action.owner
            ) == 0
        )
    }

    /// ServiceFixture preserves the real one-job ceiling while exercising source/service credits.
    struct ServiceFixture {
        let consumer             : InstalledAddon
        let provider             : InstalledAddon
        let action               : ActionFixture
        let runtime              : AddonRuntime
        let governor             : ResourceGovernor
        let access               : GatedRuntimeResourceAccess
        let decisions            : GatedRuntimeServiceDecisionAccess
        let adapter              : RecordingRuntimeAdapter
        let consumerConnection   : RuntimeConnection
        let providerConnection   : RuntimeConnection
        let publicationID        : PublicationID
        let permissionID         : UUID
        let indirectProcessGrowth: Int

        let storageCoordinator: AddonStorageCoordinator?

        init(storageRoot: URL? = nil) async throws {
            let baseConsumer = try installedFixture(
                "consumer",
                publisher: "shared.publisher"
            )
            consumer = try replacing(
                baseConsumer,
                permissions: storageRoot == nil
                    ? baseConsumer.manifest.permissions
                    : [
                        AddonPermission(
                            id   : .storageOwn,
                            scope: .addon
                        )
                    ]
            )
            let baseProvider = try installedFixture(
                "focus",
                publisher: "shared.publisher"
            )
            action = try ActionFixture(ownerName: baseProvider.manifest.id.rawValue)
            provider = try replacing(
                baseProvider,
                permissions: storageRoot == nil
                    ? baseProvider.manifest.permissions
                    : [
                        AddonPermission(
                            id   : .storageOwn,
                            scope: .addon
                        )
                    ],
                features: baseProvider.manifest.features + action.context().installed.manifest.features
            )
            governor = ResourceGovernor()
            if let storageRoot {
                let roots = [
                    storageRoot, storageRoot.appendingPathComponent("checkpoint"),
                    storageRoot.appendingPathComponent("keyed"),
                    storageRoot.appendingPathComponent("archive"),
                ]
                for root in roots {
                    try FileManager.default.createDirectory(
                        at                         : root,
                        withIntermediateDirectories: false,
                        attributes                 : [.posixPermissions: 0o700]
                    )
                }
                let coordinator = try await AddonStorageCoordinator.make(
                    checkpointRoot: roots[1],
                    keyedRoot     : roots[2],
                    archiveRoot   : roots[3],
                    registrations : [
                        StateRegistration(
                            identity            : consumer.verifiedIdentity,
                            maximumSchemaVersion: 1
                        ),
                        StateRegistration(
                            identity            : provider.verifiedIdentity,
                            maximumSchemaVersion: 1
                        ),
                    ],
                    governor: governor
                )
                try await coordinator.start()
                storageCoordinator = coordinator
            } else {
                storageCoordinator = nil
            }
            access = GatedRuntimeResourceAccess(target: governor)
            adapter = RecordingRuntimeAdapter()
            let box = RuntimeServiceDecisionAccessBox()
            runtime = try await AddonRuntime.make(
                catalog    : [consumer, provider],
                environment: HostEnvironment(
                    osVersion: SemanticVersion(
                        14,
                        0,
                        0
                    ),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [
                        consumer.manifest.id: storageRoot == nil ? [] : ["storage.own"],
                        provider.manifest.id: storageRoot == nil ? [] : ["storage.own"],
                    ],
                    explicitBindings: [],
                    protocolVersion : (1, storageRoot == nil ? 0 : 1)
                ),
                governor              : governor,
                resourceAccess        : access,
                serviceDecisionFactory: { broker in
                    let gate = GatedRuntimeServiceDecisionAccess(target: broker)
                    box.access = gate
                    return gate
                },
                adapter: adapter,
                clock  : FixedRuntimeClock(
                    instant: RuntimeInstant(
                        wall     : action.wall,
                        monotonic: .zero
                    )
                ),
                maximumEnvelopeBytes: 8_192,
                storageCoordinator  : storageCoordinator
            )
            decisions = try #require(box.access)
            publicationID = try await runtime.assignPublication(
                owner     : provider.manifest.id,
                featureID : "controls",
                instanceID: UUID()
            )
            let offer = try ProtocolOffer(
                major         : 1,
                minimumMinor  : 0,
                maximumMinor  : storageRoot == nil ? 0 : 1,
                contentSchemas: [1]
            )
            let launch = try await runtime.requestLaunch(owner: consumer.manifest.id)
            consumerConnection = try await runtime.attach(
                launchID: launch,
                offer   : offer
            )
            permissionID = try await runtime.authorizeService(
                connection   : consumerConnection,
                requirementID: "com.example.focus.sessions",
                scope        : ServiceScope(
                    featureID: "summary",
                    operation: "read"
                ),
                partition            : "account-a",
                crossPublisherConsent: true
            )
            let before = try #require(await runtime.diagnostics(owner: provider.manifest.id))
                .reservedStateBytes
            do {
                _ = try await runtime.acquireService(
                    connection  : consumerConnection,
                    permissionID: permissionID,
                    lifetime    : .seconds(30)
                )
                Issue.record("Expected pending provider launch")
            } catch is AddonFailure {}
            indirectProcessGrowth =
                try #require(await runtime.diagnostics(owner: provider.manifest.id)).reservedStateBytes
                - before
            let start = try #require(adapter.lastStart(owner: provider.manifest.id))
            providerConnection = try await runtime.attach(
                launchID: start.launchID,
                offer   : offer
            )
            _ = try await receivePublicationOutput(
                runtime: runtime,
                adapter: adapter,
                output : ProviderOutput(
                    schemaVersion: 1,
                    publications : [
                        Publication(
                            id         : publicationID,
                            revision   : 1,
                            kind       : .widget,
                            content    : action.presentation(),
                            timeline   : nil,
                            expiresAt  : action.wall.addingTimeInterval(100),
                            stalePolicy: .remove
                        )
                    ],
                    operations: [],
                    completion: nil,
                    checkpoint: nil
                ),
                connection: providerConnection,
                sequence  : 1
            )
        }

        func acquire() async throws -> ServiceAcquisition {
            try await runtime.acquireService(
                connection  : consumerConnection,
                permissionID: permissionID,
                lifetime    : .seconds(30)
            )
        }

        func invocation() throws -> ServiceInvocation {
            try ServiceInvocation(
                schemaVersion: 1,
                requestID    : UUID(),
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([1]),
                deadline     : action.wall.addingTimeInterval(20)
            )
        }

        func response() throws -> ServiceResponse {
            try ServiceResponse(
                schemaVersion: 1,
                contractID   : "com.example.focus.sessions",
                operation    : "read",
                payload      : Data([2])
            )
        }

        func stop() async {
            await runtime.stop()
            await runtime.observeExit(consumerConnection.incarnation)
            await runtime.observeExit(providerConnection.incarnation)
            _ = try? await storageCoordinator?.close()
        }
    }

    @Test(arguments: [false, true])
    func lateActionReceiptCannotReleaseNewSourceOrServiceCredit(service: Bool) async throws {
        let fixture = try await ServiceFixture()
        var acquisition: ServiceAcquisition?
        if service {
            acquisition = try await fixture.acquire()
            let value = try #require(acquisition)
            #expect(
                try await fixture.runtime.receiveSourceStartupCompletion(
                    value.sourceID,
                    connection: fixture.providerConnection
                )
            )
        }
        let action = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : fixture.publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.action.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        _ = try await fixture.runtime.submitAction(action)
        #expect(try await fixture.runtime.pumpReady())
        let delivery = try #require(fixture.adapter.lastAction)
        #expect(
            try await fixture.runtime.receiveAcknowledgment(
                delivery,
                connection: fixture.providerConnection
            )
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation) == nil)
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.provider.manifest.id
            ) == 1
        )
        if let acquisition {
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.beginServiceInvocation(
                    connection: fixture.consumerConnection,
                    grantID   : acquisition.grant.id,
                    invocation: fixture.invocation()
                )
            }
        } else {
            await #expect(throws: AddonFailure.self) { try await fixture.acquire() }
        }
        #expect(
            await fixture.governor.usage(
                .jobs,
                owner: fixture.provider.manifest.id
            ) == 1
        )
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                delivery,
                connection: fixture.providerConnection,
                outcome   : .completed(payload: Data())
            )
        )
        let work: ServiceWork?
        if let acquisition {
            work = try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumerConnection,
                grantID   : acquisition.grant.id,
                invocation: fixture.invocation()
            )
            #expect(try await fixture.runtime.pumpServiceInvocation(#require(work).id))
        } else {
            acquisition = try await fixture.acquire()
            work = nil
        }
        let current = try #require(
            fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation)
        )
        if service {
            guard case .service = current else {
                Issue.record("Expected real service handoff")
                return
            }
        } else {
            guard case .source = current else {
                Issue.record("Expected real source handoff")
                return
            }
        }
        #expect(
            try await fixture.runtime.receiveAcknowledgment(
                delivery,
                connection: fixture.providerConnection
            ) == false
        )
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                delivery,
                connection: fixture.providerConnection,
                outcome   : .completed(payload: Data())
            ) == false
        )
        #expect(
            fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation) == current
        )
        if let work {
            _ = try await fixture.runtime.receiveServiceCompletion(
                work.id,
                connection: fixture.providerConnection,
                response  : fixture.response()
            )
        } else {
            #expect(
                try await fixture.runtime.receiveSourceStartupCompletion(
                    #require(acquisition).sourceID,
                    connection: fixture.providerConnection
                )
            )
        }
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation) == nil)
        await fixture.stop()
    }

    @Test(arguments: ["normal", "stop", "exit"])
    func copiedDeferredCompletionOwnsIngressUntilActualDisposition(ending: String) async throws {
        let fixture     = try await ServiceFixture()
        let acquisition = try await fixture.acquire()
        #expect(
            try await fixture.runtime.receiveSourceStartupCompletion(
                acquisition.sourceID,
                connection: fixture.providerConnection
            )
        )
        let work = try await fixture.runtime.beginServiceInvocation(
            connection: fixture.consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: fixture.invocation()
        )
        #expect(try await fixture.runtime.pumpServiceInvocation(work.id))
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : .service(
                requestID: work.invocation.requestID,
                response : fixture.response()
            ),
            checkpoint: nil
        )
        let ingress = try #require(
            fixture.adapter.stageIngress(
                output,
                incarnation: fixture.providerConnection.incarnation
            )
        )
        await fixture.decisions.armCompletionPreparation()
        let receiving = Task {
            try await fixture.runtime.receivePublicationOutput(
                ingress,
                connection: fixture.providerConnection,
                sequence  : 2
            )
        }
        await fixture.decisions.waitForArrival()
        do {
            try #require(fixture.adapter.ingressIsTransferred(ingress))
            let attempts = fixture.adapter.ingressTakeAttempts
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.receivePublicationOutput(
                    ingress,
                    connection: fixture.providerConnection,
                    sequence  : 2
                )
            }
            #expect(fixture.adapter.ingressTakeAttempts == attempts)
            #expect(fixture.adapter.ingressIsTransferred(ingress))
            #expect(
                fixture.adapter.stageIngress(
                    output,
                    incarnation: fixture.providerConnection.incarnation
                ) == nil
            )
            if ending == "stop" { _ = await fixture.runtime.requestStop() }
            if ending == "exit" { await fixture.runtime.observeExit(fixture.providerConnection.incarnation) }
        } catch {
            await fixture.decisions.releaseGate()
            _ = await receiving.result
            throw error
        }
        await fixture.decisions.releaseGate()
        if ending == "normal" {
            guard case .committed = try await receiving.value else {
                Issue.record("Expected deferred commit")
                return
            }
            #expect(!fixture.adapter.hasIngress(incarnation: fixture.providerConnection.incarnation))
            let next = try #require(
                fixture.adapter.stageIngress(
                    ProviderOutput(
                        schemaVersion: 1,
                        publications : [],
                        operations   : [],
                        completion   : nil,
                        checkpoint   : nil
                    ),
                    incarnation: fixture.providerConnection.incarnation
                )
            )
            _ = try await fixture.runtime.receivePublicationOutput(
                next,
                connection: fixture.providerConnection,
                sequence  : 3
            )
        } else {
            await #expect(throws: AddonFailure.self) { try await receiving.value }
            #expect(!fixture.adapter.hasIngress(incarnation: fixture.providerConnection.incarnation))
        }
        await fixture.stop()
    }

    @Test(arguments: [false, true])
    func connectionCloseRetainsHandedOffActionChargesUntilActualExit(acknowledged: Bool) async throws {
        let fixture = try await Fixture()
        let request = try fixture.request()
        _ = try await fixture.runtime.submitAction(request)
        #expect(try await fixture.runtime.pumpReady())
        let delivery = try #require(fixture.adapter.lastAction)
        if acknowledged {
            #expect(try await fixture.runtime.receiveAcknowledgment(delivery, connection: fixture.connection))
        }
        await fixture.runtime.closeConnection(fixture.connection)
        await fixture.runtime.closeConnection(fixture.connection)
        #expect(fixture.adapter.stopCount(incarnation: fixture.connection.incarnation) == 1)
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(await fixture.governor.usage(.providers, owner: fixture.action.owner) == 1)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.action.owner) == 1)
        #expect(await fixture.governor.usage(.commands, owner: fixture.action.owner) == 1)
        #expect(await fixture.runtime.diagnostics(owner: fixture.action.owner)?.hasProcess == true)
        #expect(try await fixture.runtime.submitAction(request) == .duplicate(.finished(.outcomeUnknown)))
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.runtime.requestLaunch(owner: fixture.action.owner)
        }
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.runtime.receiveActionCompletion(
                delivery,
                connection: fixture.connection,
                outcome   : .completed(payload: Data())
            )
        }
        #expect(await fixture.governor.usage(.jobs, owner: fixture.action.owner) == 1)
        await fixture.runtime.observeExit(RuntimeIncarnation())
        #expect(await fixture.governor.usage(.providers, owner: fixture.action.owner) == 1)
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        #expect(await fixture.governor.usage(.providers, owner: fixture.action.owner) == 0)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.action.owner) == 0)
        #expect(await fixture.governor.usage(.commands, owner: fixture.action.owner) == 0)
        #expect(await fixture.runtime.snapshot(at: fixture.action.wall).publications.count == 1)
        await fixture.runtime.stop()
    }

    @Test
    func consumerConnectionCloseRevokesGrantsButRetainsUncertainServiceCharges() async throws {
        let fixture = try await ServiceFixture()
        let acquisition = try await fixture.acquire()
        #expect(try await fixture.runtime.receiveSourceStartupCompletion(
            acquisition.sourceID,
            connection: fixture.providerConnection
        ))
        let work = try await fixture.runtime.beginServiceInvocation(
            connection: fixture.consumerConnection,
            grantID   : acquisition.grant.id,
            invocation: fixture.invocation()
        )
        #expect(try await fixture.runtime.pumpServiceInvocation(work.id))
        await fixture.runtime.closeConnection(fixture.consumerConnection)
        #expect(fixture.adapter.stopCount(incarnation: fixture.consumerConnection.incarnation) == 1)
        #expect(fixture.adapter.stopCount(incarnation: fixture.providerConnection.incarnation) == 1)
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation) == nil)
        #expect(await fixture.governor.usage(.providers) == 2)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.provider.manifest.id) == 1)
        #expect(await fixture.governor.usage(.commands, owner: fixture.consumer.manifest.id) == 1)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumerConnection,
                grantID   : acquisition.grant.id,
                invocation: fixture.invocation()
            )
        }
        await fixture.runtime.observeExit(fixture.consumerConnection.incarnation)
        #expect(await fixture.governor.usage(.providers) == 1)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.provider.manifest.id) == 1)
        #expect(await fixture.governor.usage(.commands, owner: fixture.consumer.manifest.id) == 1)
        await fixture.runtime.observeExit(fixture.providerConnection.incarnation)
        #expect(await fixture.governor.usage(.providers) == 0)
        #expect(await fixture.governor.usage(.jobs) == 0)
        #expect(await fixture.governor.usage(.commands) == 0)
        await fixture.stop()
    }

    @Test
    func providerConnectionCloseRetainsUncertainSourceAndUnrelatedConsumerAuthority() async throws {
        let fixture = try await ServiceFixture()
        let acquisition = try await fixture.acquire()
        // Even forged component handles cannot redirect an authenticated close to the consumer.
        let current = fixture.providerConnection
        let supplied = RuntimeConnection(
            token                : current.token,
            incarnation          : current.incarnation,
            identity             : current.identity,
            digest               : current.digest,
            publicationConnection: fixture.consumerConnection.publicationConnection,
            serviceSession       : fixture.consumerConnection.serviceSession,
            authorityRevision    : current.authorityRevision
        )
        await fixture.runtime.closeConnection(supplied)
        #expect(fixture.adapter.stopCount(incarnation: current.incarnation) == 1)
        #expect(fixture.adapter.stopCount(incarnation: fixture.consumerConnection.incarnation) == 0)
        #expect(fixture.adapter.currentDelivery(incarnation: current.incarnation) == nil)
        #expect(await fixture.governor.usage(.providers) == 2)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.provider.manifest.id) == 1)
        await #expect(throws: AddonFailure.self) {
            _ = try await fixture.runtime.receiveSourceStartupCompletion(
                acquisition.sourceID,
                connection: current
            )
        }
        _ = try await receivePublicationOutput(
            runtime: fixture.runtime,
            adapter: fixture.adapter,
            output : ProviderOutput(
                schemaVersion: 1,
                publications : [],
                operations   : [],
                completion   : nil,
                checkpoint   : nil
            ),
            connection: fixture.consumerConnection,
            sequence  : 1
        )
        // Outcome lookup validates the consumer's real broker session and grant even though
        // this source has no invocation history yet.
        #expect(try await fixture.runtime.serviceOutcome(
            connection: fixture.consumerConnection,
            grantID   : acquisition.grant.id,
            requestID : UUID()
        ) == nil)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.provider.manifest.id) == 1)
        await fixture.runtime.observeExit(current.incarnation)
        #expect(await fixture.governor.usage(.providers) == 1)
        #expect(await fixture.governor.usage(.jobs, owner: fixture.provider.manifest.id) == 0)
        #expect(await fixture.runtime.snapshot(at: fixture.action.wall).publications.count == 1)
        await fixture.stop()
    }

    @Test
    func directAndIndirectLaunchPrepaySameCompleteControlQuote() async throws {
        let direct   = try await Fixture()
        let indirect = try await ServiceFixture()
        let expected = 16 * 1_024 + 8_192 + 32 * 1_024 + 80 * 1_024 + 640
        #expect(direct.directProcessGrowth == expected)
        #expect(indirect.indirectProcessGrowth == expected)
        #expect(
            await direct.governor.usage(
                .providers,
                owner: direct.action.owner
            ) == 1
        )
        _ = await direct.runtime.requestStop()
        #expect(
            await direct.governor.usage(
                .providers,
                owner: direct.action.owner
            ) == 1
        )
        await direct.runtime.stop()
        #expect(
            await direct.governor.usage(
                .providers,
                owner: direct.action.owner
            ) == 1
        )
        await direct.runtime.observeExit(direct.connection.incarnation)
        #expect(
            await direct.governor.usage(
                .providers,
                owner: direct.action.owner
            ) == 0
        )
        await indirect.stop()
    }
}
