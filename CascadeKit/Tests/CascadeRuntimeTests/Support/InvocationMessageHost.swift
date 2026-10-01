//
//  InvocationMessageHost.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

struct InvocationMessageHost: Sendable {

    let runtime      : AddonRuntime
    let governor     : ResourceGovernor
    let resources    : GatedRuntimeResourceAccess
    let adapter      : InvocationMessageAdapter
    let clock        : InvocationMessageClock
    let storage      : AddonStorageCoordinator
    let root         : URL
    let consumer     : RuntimeConnection
    let publicationID: PublicationID
    let provider     : RuntimeConnection

    struct Acquisition: Sendable {

        let grant   : Grant
        let sourceID: UUID
    }

    let acquisition   : Acquisition
    let permissionID  : UUID
    let sourceStart   : ServiceSourceStartFrame?
    let leaf          : AddonID
    let leafConnection: RuntimeConnection?
    let contractID    : String
    let operation     : String

    var owner: AddonID { consumer.identity.addonID }

    static func offer(_ minor: Int) throws -> ProtocolOffer {
        try ProtocolOffer(
            major         : 1,
            minimumMinor  : 0,
            maximumMinor  : minor,
            contentSchemas: [1]
        )
    }

    static func make(
        governor            : ResourceGovernor,
        minor               : Int,
        maximumEnvelopeBytes: Int,
        providerMinor       : Int? = nil,
        dependency          : Bool = false,
        maximumMetadata     : Bool = false,
        secondConsumer      : Bool = false,
        metricRead          : @escaping ProcessMetricsCoordinator.Read = { ProcessMetricsReader().read($0) }
    ) async throws -> Self {
        let contractID = maximumMetadata ? "com." + String(repeating: "a", count: 124) : "com.example.focus.sessions"
        let operation  = maximumMetadata ? String(repeating: "a", count: 128) : "read"
        let consumer   = try replacing(
            installedFixture("consumer", publisher: "TEST-ONLY.shared"),
            requires   : [requirement(contractID, ">=1.0.0 <2.0.0")],
            permissions: [AddonPermission(id: .storageOwn, scope: .addon)]
        )

        let baseProvider = try replacing(
            installedFixture("focus", publisher: "TEST-ONLY.shared"),
            provides   : [ProvidedService(kind: .service, id: contractID, version: "1.0.0")],
            permissions: [AddonPermission(id: .storageOwn, scope: .addon)]
        )

        let provider = dependency ? try replacing(
            baseProvider,
            requires: [requirement("com.example.runtime.leaf", ">=1.0.0 <2.0.0")]
        ) : baseProvider

        let baseLeaf = try ActionFixture().context().installed
        let leaf     = secondConsumer ? try replacing(consumer, id: baseLeaf.manifest.id.rawValue) : (
            dependency ? try replacing(
                baseProvider,
                id         : baseLeaf.manifest.id.rawValue,
                requires   : [],
                provides   : [ProvidedService(kind: .service, id: "com.example.runtime.leaf", version: "1.0.0")],
                permissions: [AddonPermission(id: .storageOwn, scope: .addon)],
                features   : baseLeaf.manifest.features
            ) : baseLeaf
        )

        let root        = URL(fileURLWithPath: "/private/tmp/cascade-service-host-\(UUID())")
        let directories = ["checkpoint", "keyed", "archive"].map { root.appendingPathComponent($0) }
        try FileManager.default.createDirectory(
            at                         : root,
            withIntermediateDirectories: false,
            attributes                 : [.posixPermissions: 0o700]
        )

        var rollbackStorage: AddonStorageCoordinator?
        var rollbackRuntime: AddonRuntime?
        let adapter = InvocationMessageAdapter()
        do {
            for directory in directories {
                try FileManager.default.createDirectory(
                    at                         : directory,
                    withIntermediateDirectories: false,
                    attributes                 : [.posixPermissions: 0o700]
                )
            }

            let storage = try await AddonStorageCoordinator.make(
                checkpointRoot: directories[0],
                keyedRoot     : directories[1],
                archiveRoot   : directories[2],
                registrations : [consumer, provider, leaf].map {
                    StateRegistration(identity: $0.verifiedIdentity, maximumSchemaVersion: 1)
                },
                governor      : governor
            )

            rollbackStorage = storage
            try await storage.start()
            let resources = GatedRuntimeResourceAccess(target: governor)
            let clock     = InvocationMessageClock()
            let runtime   = try await AddonRuntime.make(
                catalog               : [consumer, provider, leaf],
                environment           : HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [
                        consumer.manifest.id: ["storage.own"],
                        provider.manifest.id: ["storage.own"],
                        leaf.manifest.id: dependency || secondConsumer ? ["storage.own"] : []
                    ],
                    explicitBindings: [],
                    protocolVersion : (1, minor)
                ),
                governor              : governor,
                resourceAccess        : resources,
                serviceDecisionFactory: { $0 },
                adapter               : adapter,
                clock                 : clock,
                metricRead            : metricRead,
                maximumEnvelopeBytes  : maximumEnvelopeBytes,
                storageCoordinator    : storage
            )

            rollbackRuntime   = runtime
            let publicationID = try await runtime.assignPublication(
                owner     : consumer.manifest.id,
                featureID : "summary",
                instanceID: UUID()
            )

            let launch     = try await runtime.requestLaunch(owner: consumer.manifest.id)
            let connection = try await runtime.attach(launchID: launch, offer: offer(minor))
            let permission = try await runtime.authorizeService(
                connection           : connection,
                requirementID        : contractID,
                scope                : ServiceScope(featureID: "summary", operation: operation),
                partition            : "TEST-ONLY.account",
                crossPublisherConsent: true
            )

            let providerConnection: RuntimeConnection
            var sourceStart       : ServiceSourceStartFrame?
            let acquisition       : Acquisition
            var leafConnection    : RuntimeConnection?
            if minor >= 4 && (providerMinor ?? minor) >= 4 && maximumEnvelopeBytes >= 196_608 {
                let request = try ServiceControlRequest(
                    requestID: UUID(),
                    action   : .acquire(.requestService(
                        requirementID: contractID,
                        scope        : ServiceScope(featureID: "summary", operation: operation)
                    ))
                )

                let ingress = try #require(adapter.stage(
                    ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4),
                    connection: connection,
                    sequence  : 1,
                    kind      : .control
                ))

                guard case .admitted = await runtime.receiveServiceControl(ingress, connection: connection),
                      case .serviceControl(let admission) = adapter.payload(connection.incarnation)
                else {
                    throw AddonFailure(code: .invalidPayload, reason: "Missing acquisition admission")
                }

                #expect(try ServiceSubscriptionFrameCodec.decodeControlReply(
                    admission.payload,
                    profile: .v1_4
                ).result == .accepted)

                if dependency {
                    let leafStart  = try #require(adapter.starts.first { $0.identity.addonID == leaf.manifest.id })
                    leafConnection = try await runtime.attach(
                        launchID: leafStart.launchID,
                        offer   : offer(minor)
                    )
                }

                let start          = try #require(adapter.starts.first { $0.identity.addonID == provider.manifest.id })
                providerConnection = try await runtime.attach(
                    launchID: start.launchID,
                    offer   : offer(providerMinor ?? minor)
                )

                guard case .serviceSourceStart(let delivery) = adapter.payload(providerConnection.incarnation) else {
                    throw AddonFailure(code: .invalidPayload, reason: "Missing actual source start")
                }

                let frame = try ServiceSubscriptionFrameCodec.decodeSourceStart(
                    delivery.payload,
                    profile: .v1_4
                )

                sourceStart = frame
                #expect(await runtime.receiveServiceSubscriptionReceipt(
                    delivery.receipt,
                    connection: providerConnection
                ))

                let completed = try ServiceSourceOutputFrame(
                    sourceID  : frame.sourceID,
                    startNonce: frame.startNonce,
                    output    : .startupCompleted
                )

                let output = try #require(adapter.stage(
                    ServiceSubscriptionFrameCodec.encode(completed, profile: .v1_4),
                    connection: providerConnection,
                    sequence  : 1,
                    kind      : .sourceOutput
                ))

                #expect(await runtime.receiveServiceSourceOutput(output, connection: providerConnection) == .accepted)

                // Ready may be scalar, but admission still occupies the ONLY payload slot.
                #expect(adapter.payload(connection.incarnation) == .serviceControl(admission))
                #expect(await runtime.receiveServiceSubscriptionReceipt(admission.receipt, connection: connection))

                guard case .serviceControl(let terminal) = adapter.payload(connection.incarnation) else {
                    throw AddonFailure(code: .invalidPayload, reason: "Missing acquired terminal")
                }

                let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(
                    terminal.payload,
                    profile: .v1_4
                )

                try reply.validate(matching: request)
                guard case .acquired(let grant) = reply.result else {
                    throw AddonFailure(code: .invalidPayload, reason: "Not ready")
                }

                #expect(
                    await runtime.receiveServiceSubscriptionReceipt(admission.receipt, connection: connection) == false
                )
                #expect(await runtime.receiveServiceSubscriptionReceipt(terminal.receipt, connection: connection))

                acquisition = Acquisition(grant: grant, sourceID: frame.sourceID)
            } else {
                do {
                    _ = try await runtime.acquireService(
                        connection  : connection,
                        permissionID: permission,
                        lifetime    : .seconds(30)
                    )

                    Issue.record("Expected missing-provider cold start")
                } catch { #expect((error as? AddonFailure)?.code == .dependencyUnavailable) }

                if dependency {
                    let start      = try #require(adapter.starts.first { $0.identity.addonID == leaf.manifest.id })
                    leafConnection = try await runtime.attach(
                        launchID: start.launchID,
                        offer   : offer(minor)
                    )
                }

                let start          = try #require(adapter.starts.first { $0.identity.addonID == provider.manifest.id })
                providerConnection = try await runtime.attach(
                    launchID: start.launchID,
                    offer   : offer(providerMinor ?? minor)
                )

                let acquired = try await runtime.acquireService(
                    connection  : connection,
                    permissionID: permission,
                    lifetime    : .seconds(30)
                )

                #expect(
                    try await runtime.receiveSourceStartupCompletion(acquired.sourceID, connection: providerConnection)
                )

                acquisition = Acquisition(grant: acquired.grant, sourceID: acquired.sourceID)
            }

            return Self(
                runtime       : runtime,
                governor      : governor,
                resources     : resources,
                adapter       : adapter,
                clock         : clock,
                storage       : storage,
                root          : root,
                consumer      : connection,
                publicationID : publicationID,
                provider      : providerConnection,
                acquisition   : acquisition,
                permissionID  : permission,
                sourceStart   : sourceStart,
                leaf          : leaf.manifest.id,
                leafConnection: leafConnection,
                contractID    : contractID,
                operation     : operation
            )
        } catch {
            await rollbackRuntime?.stop()
            for start in adapter.starts { await rollbackRuntime?.observeExit(start.incarnation) }
            _ = try? await rollbackStorage?.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func invocation(
        bytes    : Int = 1,
        requestID: UUID = UUID()
    ) throws -> ServiceInvocation {
        try ServiceInvocation(
            schemaVersion: 1,
            requestID    : requestID,
            contractID   : contractID,
            operation    : operation,
            payload      : Data(repeating: 255, count: bytes),
            deadline     : clock.now().wall.addingTimeInterval(20)
        )
    }

    func response(bytes: Int = 1) throws -> ServiceResponse {
        try ServiceResponse(
            schemaVersion: 1,
            contractID   : contractID,
            operation    : operation,
            payload      : Data(repeating: 255, count: bytes)
        )
    }

    var providerDelivery: RuntimeServiceDelivery? {
        if case .serviceInvocation(let delivery) = adapter.payload(provider.incarnation) { return delivery }

        return nil
    }

    var replyDelivery: RuntimeServiceDelivery? {
        if case .serviceReply(let delivery) = adapter.payload(consumer.incarnation) { return delivery }

        return nil
    }

    func completionBytes(
        requestID: UUID,
        bytes    : Int = 1,
        padding  : Int = 0
    ) throws -> Data {
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : .service(requestID: requestID, response: response(bytes: bytes)),
            checkpoint   : nil
        )

        var raw = try JSONEncoder().encode(output)
        raw.append(Data(repeating: 32, count: padding))

        return raw
    }

    @discardableResult
    func begin(
        sequence : UInt64 = 1,
        requestID: UUID = UUID()
    ) async throws -> UUID {
        let invocation = try invocation(requestID: requestID)
        let raw        = try ServiceFrameCodec.encode(
            ServiceInvocationRequest(grantID: acquisition.grant.id, invocation: invocation),
            profile: .v1_3
        )

        let handle = try #require(adapter.stage(
            raw,
            connection: consumer,
            sequence  : sequence,
            kind      : .invocation
        ))

        guard case .admitted = await runtime.receiveServiceRequest(handle, connection: consumer) else {
            throw AddonFailure(code: .invalidPayload, reason: "Expected admitted route")
        }

        return requestID
    }

    func complete(
        _ requestID: UUID,
        bytes      : Int = 1,
        sequence   : UInt64 = 1
    ) async throws {
        let handle = try #require(adapter.stage(
            try completionBytes(requestID: requestID, bytes: bytes),
            connection: provider,
            sequence  : sequence,
            kind      : .completion
        ))

        _ = try await runtime.receiveServiceCompletionOutput(handle, connection: provider)
    }

    func withHeldAdmission(
        expectRevoked: Bool = false,
        _ body       : () async throws -> Void
    ) async throws {
        await resources.armResize()
        let runtime = runtime, resources = resources, leaf = leaf
        let held    = Task {
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
            await resources.waitForArrival()
            try await body()
        } catch {
            await resources.releaseGate()
            _ = try? await held.value
            throw error
        }

        await resources.releaseGate()
        if expectRevoked {
            do {
                _ = try await held.value
                Issue.record("Expected revoked held admission")
            } catch { #expect((error as? AddonFailure)?.code == .sessionRevoked) }
        } else { _ = try await held.value }
    }

    func asset(
        _ request: AssetTransferRequest,
        sequence : UInt64
    ) async throws -> AssetTransferResponse {
        let handle = try #require(adapter.stageAsset(
            try AssetTransferFrameCodec.encode(request, profile: .v1),
            connection: consumer,
            sequence  : sequence
        ))

        _ = await runtime.receiveAssetRequest(handle, connection: consumer)
        guard case .assetResponse(let delivery) = adapter.payload(consumer.incarnation) else {
            throw AddonFailure(code: .invalidPayload, reason: "No asset reply")
        }

        let value = try AssetTransferFrameCodec.decodeResponse(delivery.payload, profile: .v1)

        #expect(await runtime.receiveAssetReceipt(delivery.receipt, connection: consumer))

        return value
    }

    func cleanup() async {
        await runtime.stop()
        for start in adapter.starts { await runtime.observeExit(start.incarnation) }
        _ = try? await storage.close()
        try? FileManager.default.removeItem(at: root)
    }
}
