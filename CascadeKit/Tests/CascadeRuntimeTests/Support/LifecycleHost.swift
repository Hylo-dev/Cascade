//
//  LifecycleHost.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeAddonSDK
@testable import CascadeRuntime

struct LifecycleHost: Sendable {

    let runtime     : AddonRuntime
    let governor    : ResourceGovernor
    let resources   : GatedRuntimeResourceAccess
    let adapter     : LifecycleAdapter
    let clock       : LifecycleClock
    let consumer    : RuntimeConnection
    let provider    : RuntimeConnection
    let acquisition : ServiceAcquisition
    let permissionID: UUID
    let leaf        : AddonID

    var owner: AddonID { consumer.identity.addonID }

    static func offer() throws -> ProtocolOffer {
        try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : 0,
            contentSchemas: [1]
        )
    }

    static func make(governor: ResourceGovernor) async throws -> LifecycleHost {
        let consumer  = try installedFixture("consumer", publisher: "TEST-ONLY.shared")
        let provider  = try installedFixture("focus", publisher: "TEST-ONLY.shared")
        let leaf      = try ActionFixture().context().installed
        let resources = GatedRuntimeResourceAccess(target: governor)
        let adapter   = LifecycleAdapter()
        let clock     = LifecycleClock()
        let runtime   = try await AddonRuntime.make(
            catalog               : [consumer, provider, leaf],
            environment           : HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [consumer.manifest.id: [], provider.manifest.id: [], leaf.manifest.id: []],
                explicitBindings: []
            ),
            governor              : governor,
            resourceAccess        : resources,
            serviceDecisionFactory: { $0 },
            adapter               : adapter,
            clock                 : clock
        )

        do {
            let launch     = try await runtime.requestLaunch(owner: consumer.manifest.id)
            let connection = try await runtime.attach(launchID: launch, offer: offer())
            let pair       = try await acquire(
                runtime : runtime,
                adapter : adapter,
                consumer: connection
            )

            return LifecycleHost(
                runtime     : runtime,
                governor    : governor,
                resources   : resources,
                adapter     : adapter,
                clock       : clock,
                consumer    : connection,
                provider    : pair.0,
                acquisition : pair.1,
                permissionID: pair.2,
                leaf        : leaf.manifest.id
            )
        } catch {
            // Only explicitly modeled fixture exits; adapter inventory is bounded and synchronized.
            await runtime.stop()
            for incarnation in adapter.incarnations { await runtime.observeExit(incarnation) }
            throw error
        }
    }

    private static func acquire(
        runtime     : AddonRuntime,
        adapter     : LifecycleAdapter,
        consumer    : RuntimeConnection,
        permissionID: UUID? = nil
    ) async throws -> (RuntimeConnection, ServiceAcquisition, UUID) {
        let permission: UUID
        if let permissionID {
            permission = permissionID
        } else {
            permission = try await runtime.authorizeService(
                connection           : consumer,
                requirementID        : "com.example.focus.sessions",
                scope                : ServiceScope(featureID: "summary", operation: "read"),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )
        }

        // First acquisition starts the canonical missing provider path; no grant is fabricated.
        await lifecycleIntegrationFailure(.dependencyUnavailable) {
            _ = try await runtime.acquireService(
                connection  : consumer,
                permissionID: permission,
                lifetime    : .seconds(30)
            )
        }

        let start       = try #require(adapter.providerStart)
        let provider    = try await runtime.attach(launchID: start.launchID, offer: offer())
        let acquisition = try await runtime.acquireService(
            connection  : consumer,
            permissionID: permission,
            lifetime    : .seconds(30)
        )
        #expect(try await runtime.receiveSourceStartupCompletion(acquisition.sourceID, connection: provider))

        return (provider, acquisition, permission)
    }

    func reconnect() async throws -> (consumer: RuntimeConnection, provider: RuntimeConnection, grant: Grant) {
        let launch   = try await runtime.requestLaunch(owner: owner)
        let consumer = try await runtime.attach(launchID: launch, offer: Self.offer())
        let pair     = try await Self.acquire(
            runtime     : runtime,
            adapter     : adapter,
            consumer    : consumer,
            permissionID: permissionID
        )

        return (consumer, pair.0, pair.1.grant)
    }

    func invocation(
        bytes    : Int = 1,
        contract : String = "com.example.focus.sessions",
        operation: String = "read",
        deadline : Date? = nil
    ) throws -> ServiceInvocation {
        try ServiceInvocation(
            schemaVersion: 1,
            requestID    : UUID(),
            contractID   : contract,
            operation    : operation,
            payload      : Data(repeating: 1, count: bytes),
            deadline     : deadline ?? clock.now().wall.addingTimeInterval(20)
        )
    }

    func response(bytes: Int = 1) throws -> ServiceResponse {
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : "com.example.focus.sessions",
            operation    : "read",
            payload      : Data(repeating: 2, count: bytes)
        )
    }

    func admit(_ invocation: ServiceInvocation) async throws -> ServiceWork {
        try await runtime.beginServiceInvocation(
            connection: consumer,
            grantID   : acquisition.grant.id,
            invocation: invocation
        )
    }

    func complete(
        requestID: UUID,
        response : ServiceResponse,
        sequence : UInt64 = 1
    ) async throws -> AddonRuntime.PublicationOutputResult {
        let ingress = try #require(
            try adapter.stage(
                .service(requestID: requestID, response: response),
                incarnation: provider.incarnation
            )
        )
        defer { adapter.rejectIngress(ingress, incarnation: provider.incarnation) }

        return try await runtime.receivePublicationOutput(
            ingress,
            connection: provider,
            sequence  : sequence
        )
    }

    /// knownCompletion is a trusted test relay that offers only the existing canonical completed
    /// history, never pending data.
    func knownCompletion(requestID: UUID) async throws -> InvocationCompletion {
        guard case .completed(let response) = try await runtime.serviceOutcome(
            connection: consumer,
            grantID   : acquisition.grant.id,
            requestID : requestID
        ) else {
            throw AddonFailure(code: .resourceDenied, reason: "Canonical completion is not known")
        }

        return .service(requestID: requestID, response: response)
    }

    func withHeldAdmission(
        expectRevoked: Bool = false,
        _ body       : () async throws -> Void
    ) async throws {
        await resources.armResize()

        let runtime   = runtime
        let leaf      = leaf
        let resources = resources
        let held      = Task {
            do {
                return try await runtime.assignPublication(
                    owner     : leaf,
                    featureID : "controls",
                    instanceID: UUID()
                )
            } catch {
                await resources.releaseGate()
                throw error
            }
        }

        do {
            try await withTaskCancellationHandler {
                await resources.waitForArrival()
                try Task.checkCancellation()
                try await body()
            } onCancel: {
                held.cancel()
            }
        } catch {
            await resources.releaseGate()
            _ = try? await held.value
            throw error
        }

        await resources.releaseGate()
        if expectRevoked {
            await lifecycleIntegrationFailure(.sessionRevoked) { _ = try await held.value }
        } else {
            _ = try await held.value
        }
    }

    func cleanup() async {
        await resources.releaseGate()
        await runtime.closeConnection(consumer)
        await runtime.closeConnection(provider)
        await runtime.stop()
        for incarnation in adapter.incarnations { await runtime.observeExit(incarnation) }
    }
}
