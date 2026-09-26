//
//  AddonRuntimeStorageRequestTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite
struct AddonRuntimeStorageRequestTests {
    /// Fixture assembles secure native storage and the real governor behind a bounded recording transport.
    private final class Fixture: @unchecked Sendable {
        let root         : URL
        let keyedRoot    : URL
        let action       : ActionFixture
        let installed    : InstalledAddon
        let governor     : ResourceGovernor
        let gate         : KeyedResourceGate
        let access       : GatedRuntimeResourceAccess
        let adapter      : RecordingRuntimeAdapter
        let runtime      : AddonRuntime
        let connection   : RuntimeConnection
        let publicationID: PublicationID
        let processGrowth: Int
        var coordinator  : AddonStorageCoordinator?

        init(
            hostMinor           : Int = 1,
            declared            : Bool = true,
            granted             : Bool = true,
            startStorage        : Bool = true,
            maximumEnvelopeBytes: Int = 512 * 1_024,
            registered          : Bool = true,
            peerMaximumMinor    : Int = 1
        ) async throws {
            root = URL(fileURLWithPath: "/private/tmp/cascade-runtime-storage-\(UUID())")
            keyedRoot = root.appendingPathComponent("keyed")
            let checkpoint = root.appendingPathComponent("checkpoint")
            let archive    = root.appendingPathComponent("archive")
            for directory in [root, keyedRoot, checkpoint, archive] {
                try FileManager.default.createDirectory(
                    at                         : directory,
                    withIntermediateDirectories: false,
                    attributes                 : [.posixPermissions: 0o700]
                )
            }
            action = try ActionFixture()
            installed = try replacing(
                action.context().installed,
                permissions: declared
                    ? [
                        AddonPermission(
                            id   : .storageOwn,
                            scope: .addon
                        )
                    ] : []
            )
            governor = ResourceGovernor()
            gate = KeyedResourceGate(governor)
            access = GatedRuntimeResourceAccess(target: governor)
            adapter = RecordingRuntimeAdapter()
            let storage = try await AddonStorageCoordinator.make(
                checkpointRoot: checkpoint,
                keyedRoot     : keyedRoot,
                archiveRoot   : archive,
                registrations : [
                    StateRegistration(
                        identity: registered
                            ? installed.verifiedIdentity
                            : VerifiedAddonIdentity(
                                publisher: "unregistered.publisher",
                                addonID  : installed.manifest.id
                            ),
                        maximumSchemaVersion: 1
                    )
                ],
                governor      : governor,
                resourceAccess: gate
            )
            coordinator = storage
            if startStorage { try await storage.start() }
            runtime = try await AddonRuntime.make(
                catalog    : [installed],
                environment: HostEnvironment(
                    osVersion: SemanticVersion(
                        14,
                        0,
                        0
                    ),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [installed.manifest.id: granted ? ["storage.own"] : []],
                    explicitBindings: [],
                    protocolVersion : (1, hostMinor)
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
                maximumEnvelopeBytes: maximumEnvelopeBytes,
                storageCoordinator  : storage
            )
            publicationID = try await runtime.assignPublication(
                owner     : installed.manifest.id,
                featureID : "controls",
                instanceID: UUID()
            )
            let beforeLaunch = try #require(await runtime.diagnostics(owner: installed.manifest.id))
                .reservedStateBytes
            let launch = try await runtime.requestLaunch(owner: installed.manifest.id)
            processGrowth =
                try #require(await runtime.diagnostics(owner: installed.manifest.id)).reservedStateBytes
                - beforeLaunch
            connection = try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(
                    major         : 1,
                    minimumMinor  : 0,
                    maximumMinor  : peerMaximumMinor,
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

        func request(
            _ operation: StorageOperation = .write,
            key        : String = "key",
            value      : Data? = Data([7]),
            id         : UUID = UUID()
        ) throws -> StorageRequest {
            try StorageRequest(
                requestID: id,
                operation: operation,
                key      : key,
                value    : operation == .write ? value : nil
            )
        }

        func stage(
            _ request: StorageRequest,
            sequence : UInt64 = 1
        ) throws -> RuntimeStorageIngressHandle {
            let bytes = try StorageFrameCodec.encode(
                request,
                profile: .v1_1
            )
            return try #require(
                adapter.stageStorageIngress(
                    bytes,
                    incarnation: connection.incarnation,
                    sequence   : sequence
                )
            )
        }

        func diskValue(key: String = "key") throws -> Data? {
            let file = try AddonKeyedStorageTests.valueFile(
                keyedRoot,
                identity: installed.verifiedIdentity,
                key     : key
            )
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try KeyedStorageRecord.decode(
                Data(contentsOf: file),
                key         : Data(key.utf8),
                namespace   : KeyedStorageRecord.namespaceDigest(installed.verifiedIdentity),
                storageClass: .data
            ).value
        }

        func reply() throws -> RuntimeStorageResponseDelivery {
            guard
                case .storageResponse(let response)? = adapter.currentDelivery(
                    incarnation: connection.incarnation
                )
            else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Expected retained reply"
                )
            }
            return response
        }

        func consume(
            _ request: StorageRequest,
            sequence : UInt64
        ) async throws -> StorageResponse {
            let ingress = try stage(
                request,
                sequence: sequence
            )
            let result = await runtime.receiveStorageRequest(
                ingress,
                connection: connection
            )
            guard
                case .completed(
                    _,
                    .handedOff
                ) = result
            else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "Expected handed-off request"
                )
            }
            let delivery = try reply()
            let response = try StorageFrameCodec.decodeResponse(
                delivery.payload,
                profile: .v1_1
            )
            try response.validate(matching: request)
            #expect(
                await runtime.receiveStorageReceipt(
                    delivery.receipt,
                    connection: connection
                )
            )
            return response
        }

        func close() async {
            await runtime.stop()
            await runtime.observeExit(connection.incarnation)
            _ = try? await coordinator?.close()
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test
    func canonicalProfileCannotBeElevatedByCallerNestedSession() async throws {
        let old     = try await Fixture(peerMaximumMinor: 0)
        let current = try await Fixture()
        let raw     = try StorageFrameCodec.encode(
            old.request(),
            profile: .v1_1
        )
        #expect(old.connection.publicationConnection.negotiatedProtocol.storageFrameProfile == nil)
        #expect(current.connection.publicationConnection.negotiatedProtocol.storageFrameProfile == .v1_1)
        let ingress = try #require(
            old.adapter.stageStorageIngress(
                raw,
                incarnation: old.connection.incarnation,
                sequence   : 1
            )
        )
        let takesBefore    = old.adapter.ingressTakeAttempts
        let deliveryBefore = old.adapter.currentDelivery(incarnation: old.connection.incarnation)
        let creditBefore   = try #require(await old.runtime.diagnostics(owner: old.action.owner))
            .hasOutstandingDelivery
        let copied = RuntimeConnection(
            token                : old.connection.token,
            incarnation          : old.connection.incarnation,
            identity             : old.connection.identity,
            digest               : old.connection.digest,
            publicationConnection: current.connection.publicationConnection,
            serviceSession       : current.connection.serviceSession,
            authorityRevision    : old.connection.authorityRevision
        )
        #expect(
            await old.runtime.receiveStorageRequest(
                ingress,
                connection: copied
            ) == .refused(.versionConflict)
        )
        #expect(old.adapter.ingressTakeAttempts == takesBefore)
        #expect(try old.diskValue() == nil)
        #expect(old.adapter.currentDelivery(incarnation: old.connection.incarnation) == deliveryBefore)
        #expect(
            try #require(await old.runtime.diagnostics(owner: old.action.owner)).hasOutstandingDelivery
                == creditBefore
        )
        await old.close()
        await current.close()
    }

    @Test
    func occupiedLegacyCreditPreventsMutationBeforeStorageTake() async throws {
        let fixture = try await Fixture()
        let action  = try ActionRequest(
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
        let ingress  = try fixture.stage(fixture.request())
        let attempts = fixture.adapter.ingressTakeAttempts
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            ) == .refused(.resourceDenied)
        )
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(try fixture.diskValue() == nil)
        #expect(fixture.adapter.lastAction == delivery)
        await fixture.close()
    }

    @Test
    func acceptedReplySurvivesOperationScopeAndValidOldActionCompletion() async throws {
        let fixture = try await Fixture()
        let action  = try ActionRequest(
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
                connection: fixture.connection
            )
        )
        let request = try fixture.request(
            value: Data(
                repeating: 255,
                count    : 65_536
            )
        )
        let ingress = try fixture.stage(request)
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
                == .completed(
                    .acknowledged,
                    .handedOff
                )
        )
        #expect(try fixture.diskValue() == request.value)
        guard
            case .storageResponse(let response)? = fixture.adapter.currentDelivery(
                incarnation: fixture.connection.incarnation
            )
        else {
            Issue.record("The accepted reply must outlive the operation scope in its prepaid adapter slot")
            await fixture.close()
            return
        }
        try StorageFrameCodec.decodeResponse(
            response.payload,
            profile: .v1_1
        ).validate(matching: request)
        #expect(
            try await fixture.runtime.receiveActionCompletion(
                delivery,
                connection: fixture.connection,
                outcome   : .completed(payload: Data())
            )
        )
        #expect(
            fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation)
                == .storageResponse(response)
        )
        #expect(
            await fixture.runtime.receiveStorageReceipt(
                response.receipt,
                connection: fixture.connection
            )
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        await fixture.close()
    }
    @Test
    func boundedRoundTripMissingEmptyAndIsolation() async throws {
        let first  = try await Fixture()
        let second = try await Fixture()
        let key    = String(
            repeating: "é",
            count    : 128
        )
        let bytes = Data(
            repeating: 255,
            count    : 65_536
        )
        #expect(
            try await first.consume(
                first.request(
                    .read,
                    key: key
                ),
                sequence: 1
            ).result == .missing
        )
        #expect(
            try await first.consume(
                first.request(
                    key  : key,
                    value: bytes
                ),
                sequence: 2
            ).result == .acknowledged
        )
        #expect(
            try await first.consume(
                first.request(
                    .read,
                    key: key
                ),
                sequence: 3
            ).value == bytes
        )
        #expect(
            try await second.consume(
                second.request(
                    .read,
                    key: key
                ),
                sequence: 1
            ).result == .missing
        )
        #expect(
            try await first.consume(
                first.request(
                    key  : key,
                    value: Data()
                ),
                sequence: 4
            ).result == .acknowledged
        )
        #expect(
            try await first.consume(
                first.request(
                    .read,
                    key: key
                ),
                sequence: 5
            ).value == Data()
        )
        #expect(
            try await first.consume(
                first.request(
                    .remove,
                    key: key
                ),
                sequence: 6
            ).result == .acknowledged
        )
        #expect(
            try await first.consume(
                first.request(
                    .remove,
                    key: key
                ),
                sequence: 7
            ).result == .acknowledged
        )
        #expect(
            try await first.consume(
                first.request(
                    .read,
                    key: key
                ),
                sequence: 8
            ).result == .missing
        )
        await first.close()
        await second.close()
    }

    @Test(arguments: [0, 1, 2, 3])
    func unavailableAuthorityRefusesBeforeTake(_ reason: Int) async throws {
        let fixture = try await Fixture(
            declared    : reason != 0,
            startStorage: reason != 1,
            registered  : reason != 3
        )
        if reason == 2 { fixture.coordinator = nil }
        let attempts = fixture.adapter.ingressTakeAttempts
        let ingress  = try fixture.stage(fixture.request())
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            ) == .refused(reason == 0 ? .permissionDenied : .dependencyUnavailable)
        )
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(try fixture.diskValue() == nil)
        await fixture.close()
    }

    @Test
    func malformedAndAdvertisedSizeMismatchDoNotConsumeSequenceOrReceipt() async throws {
        let fixture  = try await Fixture()
        let receipts = fixture.adapter.deliveryReceiptCount
        let invalid  = try #require(
            fixture.adapter.stageStorageIngress(
                Data("{}".utf8),
                incarnation: fixture.connection.incarnation,
                sequence   : 1
            )
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                invalid,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        let request = try fixture.request()
        let raw     = try StorageFrameCodec.encode(
            request,
            profile: .v1_1
        )
        let mismatch = try #require(
            fixture.adapter.stageStorageIngress(
                raw,
                incarnation    : fixture.connection.incarnation,
                sequence       : 1,
                advertisedBytes: raw.count + 1
            )
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                mismatch,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        #expect(fixture.adapter.deliveryReceiptCount == receipts)
        #expect(try fixture.diskValue() == nil)
        #expect(
            try await fixture.consume(
                request,
                sequence: 1
            ).result == .acknowledged
        )
        let stale = try fixture.stage(
            request,
            sequence: 1
        )
        let takes = fixture.adapter.ingressTakeAttempts
        #expect(
            await fixture.runtime.receiveStorageRequest(
                stale,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        #expect(fixture.adapter.ingressTakeAttempts == takes)
        #expect(
            try await fixture.consume(
                request,
                sequence: UInt64.max
            ).result == .acknowledged
        )
        let exhausted = try fixture.stage(
            request,
            sequence: UInt64.max
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                exhausted,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        await fixture.close()
    }

    @Test
    func rejectedHandoffPreservesKnownMutationAndNeverAcknowledgesReservedCredit() async throws {
        let fixture = try await Fixture()
        fixture.adapter.rejectStorageReplies = true
        let receipts = fixture.adapter.deliveryReceiptCount
        let ingress  = try fixture.stage(fixture.request())
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
                == .completed(
                    .acknowledged,
                    .rejectedBeforeHandoff
                )
        )
        #expect(try fixture.diskValue() == Data([7]))
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        #expect(fixture.adapter.deliveryReceiptCount == receipts)
        fixture.adapter.rejectStorageReplies = false
        #expect(
            try await fixture.consume(
                fixture.request(.read),
                sequence: 2
            ).value == Data([7])
        )
        await fixture.close()
    }

    @Test
    func wrongAndDuplicateReceiptsCannotReleaseNewReplyOrItsProcessCapacity() async throws {
        let fixture = try await Fixture()
        let ingress = try fixture.stage(fixture.request())
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
                == .completed(
                    .acknowledged,
                    .handedOff
                )
        )
        let first  = try fixture.reply()
        let before = try #require(await fixture.runtime.diagnostics(owner: fixture.action.owner))
            .reservedStateBytes
        let wrong = RuntimeStorageReceipt(
            token          : UUID(),
            incarnation    : first.receipt.incarnation,
            connectionToken: first.receipt.connectionToken,
            sequence       : first.receipt.sequence,
            requestID      : first.receipt.requestID,
            operation      : first.receipt.operation
        )
        #expect(
            await fixture.runtime.receiveStorageReceipt(
                wrong,
                connection: fixture.connection
            ) == false
        )
        #expect(try fixture.reply() == first)
        #expect(
            await fixture.runtime.receiveStorageReceipt(
                first.receipt,
                connection: fixture.connection
            )
        )
        let next = try fixture.stage(
            fixture.request(.read),
            sequence: 2
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                next,
                connection: fixture.connection
            )
                == .completed(
                    .value,
                    .handedOff
                )
        )
        let second = try fixture.reply()
        #expect(
            await fixture.runtime.receiveStorageReceipt(
                first.receipt,
                connection: fixture.connection
            ) == false
        )
        #expect(try fixture.reply() == second)
        #expect(
            try #require(await fixture.runtime.diagnostics(owner: fixture.action.owner)).reservedStateBytes
                == before
        )
        #expect(
            await fixture.runtime.receiveStorageReceipt(
                second.receipt,
                connection: fixture.connection
            )
        )
        await fixture.close()
    }

    @Test(arguments: [false, true])
    func acceptedMutationGatePreservesOutcomeAcrossCancellation(_ committed: Bool) async throws {
        let fixture = try await Fixture()
        // Seed both existing disk-pool rows before measuring or arming post-mutation release.
        _ = try await fixture.consume(
            fixture.request(value: Data([1])),
            sequence: 1
        )
        await fixture.gate.arm(
            committed ? .release : .temporary,
            skipping: committed ? 1 : 0
        )
        let ingress = try fixture.stage(
            fixture.request(value: Data([9])),
            sequence: 2
        )
        let task = Task {
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
        }
        await fixture.gate.wait()
        let observed: Data?
        do { observed = try fixture.diskValue() } catch {
            await fixture.gate.resume()
            _ = await task.value
            await fixture.close()
            throw error
        }
        #expect(observed == Data([committed ? 9 : 1]))
        #expect(fixture.adapter.storageIngressIsTransferred(ingress))
        task.cancel()
        await fixture.gate.resume()
        #expect(
            await task.value
                == .completed(
                    committed ? .acknowledged : .outcomeUnknown,
                    .suppressed
                )
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        await fixture.close()
    }

    @Test(arguments: [false, true])
    func protectedScopeAndStrongAcceptedCoordinatorSurviveHostDropAndObservedExit(
        _ releaseOrdinaryReservations: Bool
    ) async throws {
        let fixture = try await Fixture()
        _ = try await fixture.consume(
            fixture.request(value: Data([1])),
            sequence: 1
        )
        await fixture.gate.arm(.temporary)
        let ingress = try fixture.stage(
            fixture.request(
                value: Data(
                    repeating: 5,
                    count    : 65_536
                )
            ),
            sequence: 2
        )
        let task = Task {
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
        }
        await fixture.gate.wait()
        weak var weakCoordinator = fixture.coordinator
        fixture.coordinator = nil
        #expect(weakCoordinator != nil)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) >= 8 * 1_024 * 1_024 + 267_776)
        await fixture.runtime.observeExit(fixture.connection.incarnation)
        if releaseOrdinaryReservations { await fixture.governor.releaseAll(owner: fixture.action.owner) }
        #expect(await fixture.governor.usage(.admittedMemoryBytes) >= 8 * 1_024 * 1_024)
        await fixture.gate.resume()
        #expect(
            await task.value
                == .completed(
                    releaseOrdinaryReservations ? .outcomeUnknown : .acknowledged,
                    .suppressed
                )
        )
        #expect(weakCoordinator == nil)
        #expect(await fixture.governor.usage(.admittedMemoryBytes) < 8 * 1_024 * 1_024)
        await fixture.close()
    }

    @Test
    func configuredCapacityPreservesLegacyBuffersAndPrepaysEnabledDelivery() async throws {
        let legacy = try await Fixture(
            hostMinor           : 0,
            maximumEnvelopeBytes: 8_192
        )
        let enabled = try await Fixture(maximumEnvelopeBytes: 8_192)
        #expect(enabled.processGrowth - legacy.processGrowth == (256 - 80) * 1_024)
        #expect(legacy.processGrowth >= 16 * 1_024 + 8_192 + 32 * 1_024 + 80 * 1_024 + 512)
        let tooLarge = Data(
            repeating: 0,
            count    : 8_193
        )
        #expect(
            enabled.adapter.stageStorageIngress(
                tooLarge,
                incarnation: enabled.connection.incarnation,
                sequence   : 1
            ) == nil
        )
        #expect(
            legacy.adapter.stageStorageIngress(
                Data([1]),
                incarnation: legacy.connection.incarnation,
                sequence   : 1
            ) == nil
        )
        await legacy.close()
        await enabled.close()
    }
    private struct UnsupportedAdapter: AddonRuntimeAdapter {
        func takeIngress(
            _ handle   : RuntimeIngressHandle,
            incarnation: RuntimeIncarnation
        ) -> ProviderOutput? { nil }
        func rejectIngress(
            _ handle   : RuntimeIngressHandle,
            incarnation: RuntimeIncarnation
        ) {}
        func cancelIngress(
            _ handle   : RuntimeIngressHandle,
            incarnation: RuntimeIncarnation
        ) {}
        func finishIngress(
            _ handle   : RuntimeIngressHandle,
            incarnation: RuntimeIncarnation
        ) {}
        func tryHandoff(
            incarnation: RuntimeIncarnation,
            delivery   : RuntimeAdapterDelivery
        ) -> RuntimeHandoffResult { .rejectedBeforeHandoff }
        func requestStop(
            incarnation: RuntimeIncarnation,
            reason     : RuntimeStopReason
        ) {}
        func deliveryWasReceived(incarnation: RuntimeIncarnation) {}
        func processDidExit(incarnation: RuntimeIncarnation) {}
    }

    @Test
    func assemblyRejectsForeignGovernorAndMissingRefinementBeforeAdmission() async throws {
        let fixture  = try await Fixture()
        let foreign  = ResourceGovernor()
        let baseline = await fixture.governor.usage(.retainedStateBytes)
        await #expect(throws: AddonFailure.self) {
            try await AddonRuntime.make(
                catalog           : [],
                environment       : emptyEnvironment,
                governor          : foreign,
                adapter           : fixture.adapter,
                storageCoordinator: fixture.coordinator
            )
        }
        await #expect(throws: AddonFailure.self) {
            try await AddonRuntime.make(
                catalog           : [],
                environment       : emptyEnvironment,
                governor          : fixture.governor,
                adapter           : UnsupportedAdapter(),
                storageCoordinator: fixture.coordinator
            )
        }
        #expect(await foreign.usage(.retainedStateBytes) == 0)
        #expect(await fixture.governor.usage(.retainedStateBytes) == baseline)
        await fixture.close()
    }

    @Test
    func declaredPermissionNeedsGrantAndResolverCannotAdvertiseMissingImplementation() async throws {
        let fixture           = try await Fixture()
        let manifest          = fixture.installed.manifest
        let requiringMinorOne = try AddonManifest(
            manifestVersion: manifest.manifestVersion,
            id             : manifest.id,
            version        : manifest.version,
            compatibility  : AddonCompatibility(
                macOS          : manifest.compatibility.macOS,
                cascadeProtocol: ProtocolVersion(
                    major       : 1,
                    minimumMinor: 1
                )
            ),
            execution       : manifest.execution,
            sourceApp       : manifest.sourceApp,
            bundledLibraries: manifest.bundledLibraries,
            requires        : manifest.requires,
            provides        : manifest.provides,
            features        : manifest.features,
            permissions     : manifest.permissions,
            resources       : manifest.resources
        )
        let addon = try InstalledAddon(
            manifest        : requiringMinorOne,
            verifiedIdentity: fixture.installed.verifiedIdentity,
            digest          : fixture.installed.digest,
            enabled         : true
        )
        for grant in [false, true] {
            let governor = ResourceGovernor()
            let runtime  = try await AddonRuntime.make(
                catalog    : [addon],
                environment: HostEnvironment(
                    osVersion: SemanticVersion(
                        14,
                        0,
                        0
                    ),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [addon.manifest.id: grant ? ["storage.own"] : []],
                    explicitBindings: [],
                    protocolVersion : (1, 1)
                ),
                governor: governor,
                adapter : RecordingRuntimeAdapter()
            )
            await #expect(throws: AddonFailure.self) {
                try await runtime.assignPublication(
                    owner     : addon.manifest.id,
                    featureID : "controls",
                    instanceID: UUID()
                )
            }
            await runtime.stop()
        }
        let ungranted = try await AddonRuntime.make(
            catalog    : [fixture.installed],
            environment: HostEnvironment(
                osVersion: SemanticVersion(
                    14,
                    0,
                    0
                ),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [:],
                explicitBindings: [],
                protocolVersion : (1, 1)
            ),
            governor          : fixture.governor,
            adapter           : RecordingRuntimeAdapter(),
            storageCoordinator: fixture.coordinator
        )
        await #expect(throws: AddonFailure.self) {
            try await ungranted.assignPublication(
                owner     : fixture.action.owner,
                featureID : "controls",
                instanceID: UUID()
            )
        }
        await ungranted.stop()
        await fixture.close()
    }

    @Test
    func quotaRefusalPreservesSequenceAndRejectsOnlyStagedIngress() async throws {
        let fixture = try await Fixture()
        let owner   = fixture.action.owner
        let used    = await fixture.governor.usage(
            .admittedMemoryBytes,
            owner: owner
        )
        let filler = try await fixture.governor.admit(
            .temporaryMemory(bytes: 128 * 1_024 * 1_024 - used - 1_024),
            owner: owner
        )
        let ingress  = try fixture.stage(fixture.request())
        let attempts = fixture.adapter.ingressTakeAttempts
        let receipts = fixture.adapter.deliveryReceiptCount
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            ) == .refused(.resourceDenied)
        )
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(fixture.adapter.deliveryReceiptCount == receipts)
        #expect(!fixture.adapter.hasIngress(incarnation: fixture.connection.incarnation))
        try await fixture.governor.release(
            filler.id,
            owner: owner
        )
        #expect(
            try await fixture.consume(
                fixture.request(),
                sequence: 1
            ).result == .acknowledged
        )
        await fixture.close()
    }

    @Test
    func sharedIngressCannotStagePublicationAndStorageTogether() async throws {
        let fixture = try await Fixture()
        let ingress = try fixture.stage(fixture.request())
        let output  = try ProviderOutput(
            schemaVersion: 1,
            publications : [],
            operations   : [],
            completion   : nil,
            checkpoint   : nil
        )
        #expect(
            fixture.adapter.stageIngress(
                output,
                incarnation: fixture.connection.incarnation
            ) == nil
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
                == .completed(
                    .acknowledged,
                    .handedOff
                )
        )
        #expect(
            await fixture.runtime.receiveStorageReceipt(
                try fixture.reply().receipt,
                connection: fixture.connection
            )
        )
        await fixture.close()
    }

    @Test
    func cacheNamespaceDoesNotBecomeProviderData() async throws {
        let fixture     = try await Fixture()
        let coordinator = try #require(fixture.coordinator)
        let owner       = try await coordinator.owner(for: fixture.installed.verifiedIdentity)
        try await coordinator.write(
            Data([8]),
            key         : "key",
            owner       : owner,
            storageClass: .cache
        )
        #expect(
            try await fixture.consume(
                fixture.request(.read),
                sequence: 1
            ).result == .missing
        )
        _ = try await fixture.consume(
            fixture.request(value: Data([9])),
            sequence: 2
        )
        #expect(
            try await coordinator.read(
                key         : "key",
                owner       : owner,
                storageClass: .cache
            ) == Data([8])
        )
        await fixture.close()
    }

    @Test
    func terminalShutdownContextDoesNotCreateRuntimeCoordinatorCycle() async throws {
        var fixture: Fixture? = try await Fixture()
        weak let weakRuntime = fixture?.runtime
        weak let weakCoordinator = fixture?.coordinator
        if let current = fixture, let coordinator = current.coordinator {
            _ = try await coordinator.beginArchiveShutdown(
                runtime: current.runtime,
                until  : .seconds(10)
            )
            _ = await coordinator.finishArchiveShutdown()
            _ = try await coordinator.close()
            await current.runtime.observeExit(current.connection.incarnation)
            try FileManager.default.removeItem(at: current.root)
        }
        fixture = nil
        #expect(weakCoordinator == nil)
        #expect(weakRuntime == nil)
    }

    @Test(arguments: [false, true])
    func closeDuringRealReadOrRemoveSuppressesReplyWithoutRelabelingMutation(_ remove: Bool) async throws {
        let fixture = try await Fixture()
        _ = try await fixture.consume(
            fixture.request(),
            sequence: 1
        )
        let ingress = try fixture.stage(
            fixture.request(remove ? .remove : .read),
            sequence: 2
        )
        await fixture.gate.arm(remove ? .diskResize : .temporary)
        let task = Task {
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
        }
        await fixture.gate.wait()
        if remove {
            do { #expect(try fixture.diskValue() == nil) } catch {
                await fixture.gate.resume()
                _ = await task.value
                await fixture.close()
                throw error
            }
        }
        do { #expect(try await fixture.coordinator?.close() == .draining) } catch {
            await fixture.gate.resume()
            _ = await task.value
            await fixture.close()
            throw error
        }
        _ = await fixture.runtime.requestStop()
        await fixture.gate.resume()
        #expect(
            await task.value
                == .completed(
                    remove ? .acknowledged : .failure(.dependencyUnavailable),
                    .suppressed
                )
        )
        #expect(fixture.adapter.currentDelivery(incarnation: fixture.connection.incarnation) == nil)
        await fixture.close()
    }
    @Test(arguments: [false, true])
    func sourceAndServiceCreditBlocksStorageAndStaleCompletionCannotFreeReply(_ service: Bool) async throws {
        let root    = URL(fileURLWithPath: "/private/tmp/cascade-storage-service-\(UUID())")
        let fixture = try await AddonRuntimeSlotOwnershipTests.ServiceFixture(storageRoot: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let acquisition = try await fixture.acquire()
        let work: ServiceWork?
        if service {
            #expect(
                try await fixture.runtime.receiveSourceStartupCompletion(
                    acquisition.sourceID,
                    connection: fixture.providerConnection
                )
            )
            let invocation = try await fixture.runtime.beginServiceInvocation(
                connection: fixture.consumerConnection,
                grantID   : acquisition.grant.id,
                invocation: fixture.invocation()
            )
            #expect(try await fixture.runtime.pumpServiceInvocation(invocation.id))
            work = invocation
        } else {
            work = nil
        }
        let request = try StorageRequest(
            requestID: UUID(),
            operation: .write,
            key      : "key",
            value    : Data([6])
        )
        let raw = try StorageFrameCodec.encode(
            request,
            profile: .v1_1
        )
        let busyIngress = try #require(
            fixture.adapter.stageStorageIngress(
                raw,
                incarnation: fixture.providerConnection.incarnation,
                sequence   : 1
            )
        )
        let attempts = fixture.adapter.ingressTakeAttempts
        #expect(
            await fixture.runtime.receiveStorageRequest(
                busyIngress,
                connection: fixture.providerConnection
            ) == .refused(.resourceDenied)
        )
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        if let work {
            _ = try await fixture.runtime.receiveServiceCompletion(
                work.id,
                connection: fixture.providerConnection,
                response  : fixture.response()
            )
        } else {
            #expect(
                try await fixture.runtime.receiveSourceStartupCompletion(
                    acquisition.sourceID,
                    connection: fixture.providerConnection
                )
            )
        }
        let ingress = try #require(
            fixture.adapter.stageStorageIngress(
                raw,
                incarnation: fixture.providerConnection.incarnation,
                sequence   : 1
            )
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.providerConnection
            )
                == .completed(
                    .acknowledged,
                    .handedOff
                )
        )
        let delivery = try #require(
            fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation)
        )
        if let work {
            await #expect(throws: AddonFailure.self) {
                try await fixture.runtime.receiveServiceCompletion(
                    work.id,
                    connection: fixture.providerConnection,
                    response  : fixture.response()
                )
            }
        } else {
            #expect(
                try await fixture.runtime.receiveSourceStartupCompletion(
                    acquisition.sourceID,
                    connection: fixture.providerConnection
                ) == false
            )
        }
        #expect(
            fixture.adapter.currentDelivery(incarnation: fixture.providerConnection.incarnation) == delivery
        )
        #expect(fixture.indirectProcessGrowth == 16 * 1_024 + 8_192 + 32 * 1_024 + 256 * 1_024 + 640)
        // Both identities share one complete registry and governor; provider bytes remain private.
        let read = try StorageRequest(
            requestID: UUID(),
            operation: .read,
            key      : "key"
        )
        let consumerIngress = try #require(
            fixture.adapter.stageStorageIngress(
                StorageFrameCodec.encode(
                    read,
                    profile: .v1_1
                ),
                incarnation: fixture.consumerConnection.incarnation,
                sequence   : 1
            )
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                consumerIngress,
                connection: fixture.consumerConnection
            )
                == .completed(
                    .missing,
                    .handedOff
                )
        )
        await fixture.stop()
    }

    @Test(arguments: [0, 1, 2])
    func revokedOrCancelledRequestNeverReachesBackend(_ mode: Int) async throws {
        let fixture  = try await Fixture()
        let ingress  = try fixture.stage(fixture.request())
        let attempts = fixture.adapter.ingressTakeAttempts
        if mode == 0 { await fixture.runtime.disable(owner: fixture.action.owner) }
        if mode == 1 {
            _ = try await fixture.coordinator?.beginArchiveShutdown(
                runtime: fixture.runtime,
                until  : .seconds(10)
            )
        }
        let result: AddonRuntime.RuntimeStorageRequestResult
        if mode == 2 {
            result = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await fixture.runtime.receiveStorageRequest(
                    ingress,
                    connection: fixture.connection
                )
            }.value
        } else {
            result = await fixture.runtime.receiveStorageRequest(
                ingress,
                connection: fixture.connection
            )
        }
        #expect(result == .refused(.sessionRevoked))
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(try fixture.diskValue() == nil)
        await fixture.close()
    }
    @Test
    func acceptedReadFailureConsumesSequenceAndNeverReplaysUUID() async throws {
        let fixture = try await Fixture()
        _ = try await fixture.consume(
            fixture.request(),
            sequence: 1
        )
        let file = try AddonKeyedStorageTests.valueFile(
            fixture.keyedRoot,
            identity: fixture.installed.verifiedIdentity,
            key     : "key"
        )
        try Data([0]).write(to: file)
        let request  = try fixture.request(.read)
        let response = try await fixture.consume(
            request,
            sequence: 2
        )
        #expect(response.result == .failure)
        #expect(response.failureCode == .dependencyUnavailable)
        let replay = try fixture.stage(
            request,
            sequence: 2
        )
        #expect(
            await fixture.runtime.receiveStorageRequest(
                replay,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        #expect(
            try await fixture.consume(
                request,
                sequence: 3
            ).result == .failure
        )
        await fixture.close()
    }

    @Test(arguments: ["{}", "{\"schemaVersion\":null}", "[]"])
    func malformedRawFramesHaveNoBackendOrReceipt(_ text: String) async throws {
        let fixture = try await Fixture()
        let handle  = try #require(
            fixture.adapter.stageStorageIngress(
                Data(text.utf8),
                incarnation: fixture.connection.incarnation,
                sequence   : 1
            )
        )
        let receipts = fixture.adapter.deliveryReceiptCount
        #expect(
            await fixture.runtime.receiveStorageRequest(
                handle,
                connection: fixture.connection
            ) == .refused(.invalidPayload)
        )
        #expect(try fixture.diskValue() == nil)
        #expect(fixture.adapter.deliveryReceiptCount == receipts)
        await fixture.close()
    }

    @Test
    func wrongIncarnationZeroSequenceAndOversizeAreRefusedWithoutTransfer() async throws {
        let fixture  = try await Fixture()
        let attempts = fixture.adapter.ingressTakeAttempts
        for handle in [
            RuntimeStorageIngressHandle(
                token       : UUID(),
                incarnation : RuntimeIncarnation(),
                encodedBytes: 1,
                sequence    : 1
            ),
            RuntimeStorageIngressHandle(
                token       : UUID(),
                incarnation : fixture.connection.incarnation,
                encodedBytes: 1,
                sequence    : 0
            ),
            RuntimeStorageIngressHandle(
                token       : UUID(),
                incarnation : fixture.connection.incarnation,
                encodedBytes: 192 * 1_024 + 1,
                sequence    : 1
            ),
        ] {
            #expect(
                await fixture.runtime.receiveStorageRequest(
                    handle,
                    connection: fixture.connection
                ) == .refused(.invalidPayload)
            )
        }
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(try fixture.diskValue() == nil)
        #expect(
            try await fixture.consume(
                fixture.request(),
                sequence: 1
            ).result == .acknowledged
        )
        await fixture.close()
    }

    @Test
    func unsafeUnopenedStorageCannotAcquireRequestAuthority() async throws {
        let fixture = try await Fixture(startStorage: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o777],
            ofItemAtPath: fixture.keyedRoot.path
        )
        let coordinator = try #require(fixture.coordinator)
        await #expect(throws: (any Error).self) { try await coordinator.start() }
        let handle   = try fixture.stage(fixture.request())
        let attempts = fixture.adapter.ingressTakeAttempts
        #expect(
            await fixture.runtime.receiveStorageRequest(
                handle,
                connection: fixture.connection
            ) == .refused(.dependencyUnavailable)
        )
        #expect(fixture.adapter.ingressTakeAttempts == attempts)
        #expect(try fixture.diskValue() == nil)
        await fixture.close()
    }
    @Test
    func busyAdmissionRefusesBeforeStorageTakeAndPreservesSequence() async throws {
        let fixture = try await Fixture()
        let action  = try ActionRequest(
            schemaVersion   : 1,
            requestID       : UUID(),
            publicationID   : fixture.publicationID,
            actionID        : "pause",
            input           : Data([7]),
            deadline        : fixture.action.wall.addingTimeInterval(20),
            observedRevision: 1
        )
        await fixture.access.armResize()
        let submitting = Task { try await fixture.runtime.submitAction(action) }
        await fixture.access.waitForArrival()
        do {
            let ingress  = try fixture.stage(fixture.request())
            let attempts = fixture.adapter.ingressTakeAttempts
            #expect(
                await fixture.runtime.receiveStorageRequest(
                    ingress,
                    connection: fixture.connection
                ) == .refused(.resourceDenied)
            )
            #expect(fixture.adapter.ingressTakeAttempts == attempts)
            #expect(try fixture.diskValue() == nil)
        } catch {
            await fixture.access.releaseGate()
            _ = await submitting.result
            await fixture.close()
            throw error
        }
        submitting.cancel()
        await fixture.access.releaseGate()
        _ = await submitting.result
        #expect(
            try await fixture.consume(
                fixture.request(),
                sequence: 1
            ).result == .acknowledged
        )
        await fixture.close()
    }
}
