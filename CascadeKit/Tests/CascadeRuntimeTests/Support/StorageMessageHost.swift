//
//  StorageMessageHost.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

struct StorageMessageHost: Sendable {

    let root       : URL
    let keyedRoot  : URL
    let owner      : AddonID
    let identity   : VerifiedAddonIdentity
    let governor   : ResourceGovernor
    let storage    : AddonStorageCoordinator
    let files      : KeyedFileFaults
    let backendGate: KeyedResourceGate
    let runtime    : AddonRuntime
    let adapter    : StorageMessageAdapter
    let connection : RuntimeConnection
    let channel    : StorageRuntimeByteBridge

    static func make(
        action  : ActionFixture,
        governor: ResourceGovernor,
        minor   : Int,
        declared: Bool,
        granted : Bool,
        ready   : Bool
    ) async throws -> Self {
        let root            = URL(fileURLWithPath: "/private/tmp/cascade-storage-client-\(UUID())")
        let keyed           = root.appendingPathComponent("keyed")
        let checkpoint      = root.appendingPathComponent("checkpoint")
        let archive         = root.appendingPathComponent("archive")
        let adapter         = StorageMessageAdapter()
        var rollbackStorage: AddonStorageCoordinator?
        var rollbackRuntime: AddonRuntime?

        do {
            for directory in [root, keyed, checkpoint, archive] {
                try FileManager.default.createDirectory(
                    at                         : directory,
                    withIntermediateDirectories: false,
                    attributes                 : [.posixPermissions: 0o700]
                )
            }

            let installed = try replacing(
                action.context().installed,
                permissions: declared ? [AddonPermission(id: .storageOwn, scope: .addon)] : []
            )
            let files       = KeyedFileFaults()
            let backendGate = KeyedResourceGate(governor)
            let storage     = try await AddonStorageCoordinator.make(
                checkpointRoot     : checkpoint,
                keyedRoot          : keyed,
                archiveRoot        : archive,
                registrations      : [StateRegistration(identity: installed.verifiedIdentity, maximumSchemaVersion: 1)],
                governor           : governor,
                resourceAccess     : backendGate,
                keyedFileOperations: files
            )
            rollbackStorage = storage
            if ready { try await storage.start() }

            let runtime = try await AddonRuntime.make(
                catalog           : [installed],
                environment       : HostEnvironment(
                    osVersion       : SemanticVersion(14, 0, 0),
                    hostCapabilities: [:],
                    applications    : [:],
                    grants          : [action.owner: granted ? ["storage.own"] : []],
                    explicitBindings: [],
                    protocolVersion : (1, minor)
                ),
                governor          : governor,
                adapter           : adapter,
                clock             : FixedRuntimeClock(instant: RuntimeInstant(wall: action.wall, monotonic: .zero)),
                storageCoordinator: storage
            )
            rollbackRuntime = runtime

            _ = try await runtime.assignPublication(
                owner     : action.owner,
                featureID : "controls",
                instanceID: UUID()
            )
            let launch     = try await runtime.requestLaunch(owner: action.owner)
            let connection = try await runtime.attach(
                launchID: launch,
                offer   : ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: minor, contentSchemas: [1])
            )

            return Self(
                root       : root,
                keyedRoot  : keyed,
                owner      : action.owner,
                identity   : installed.verifiedIdentity,
                governor   : governor,
                storage    : storage,
                files      : files,
                backendGate: backendGate,
                runtime    : runtime,
                adapter    : adapter,
                connection : connection,
                channel    : StorageRuntimeByteBridge(runtime: runtime, adapter: adapter, connection: connection)
            )
        } catch {
            await rollbackRuntime?.stop()
            if let incarnation = adapter.incarnation {
                // Explicit modeled cleanup for a partially constructed test fixture.
                await rollbackRuntime?.observeExit(incarnation)
            }

            _ = try? await rollbackStorage?.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func withSDK(_ body: @Sendable (MessageAddonStorageClient) async throws -> Void) async throws {
        try await governor.withAssetDecodeReservation(bytes: 8 * 1_024 * 1_024, owner: owner) {
            let client = try MessageAddonStorageClient(channel: channel)

            do {
                try await body(client)
            } catch {
                await client.close()
                throw error
            }

            await client.close()
            // No Data, request/response DTO, client or physical-work task is returned from here.
        }
    }

    func diskValue(key: String = "key") throws -> Data? {
        let file = try AddonKeyedStorageTests.valueFile(
            keyedRoot,
            identity: identity,
            key     : key
        )
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        return try KeyedStorageRecord.decode(
            Data(contentsOf: file),
            key         : Data(key.utf8),
            namespace   : KeyedStorageRecord.namespaceDigest(identity),
            storageClass: .data
        ).value
    }

    func cleanup() async {
        await channel.close()
        await runtime.stop()
        // Explicitly modeled cleanup input; close itself never refunds an unobserved process.
        await runtime.observeExit(connection.incarnation)
        _ = try? await storage.close()
        try? FileManager.default.removeItem(at: root)
    }
}
