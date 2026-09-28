//
//  AddonContextTests.swift
//  CascadeKit
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing

@Suite
struct AddonContextTests {
    private struct UnavailableServices: AddonServiceClient {
        func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse {
            throw AddonFailure(code: .invalidPayload, reason: "Test has no transport")
        }
        func subscribe(requirementID: String, grant: Grant) async throws -> UUID {
            throw AddonFailure(code: .invalidPayload, reason: "Test has no transport")
        }
        func unsubscribe(subscriptionID: UUID) async throws {}
    }

    private struct UnavailableStorage: AddonStorageClient {
        func read(key: String) async throws -> Data? { nil }
        func write(_ data: Data, key: String) async throws {}
        func remove(key: String) async throws {}
    }

    private func grant(generation: ConnectionGeneration) throws -> Grant {
        try Grant(
            id: UUID(),
            owner: #require(AddonID(rawValue: "com.example.test")),
            serviceID: "status",
            scope: ServiceScope(featureID: "focus", operation: "read"),
            expiresAt: Date.now.addingTimeInterval(60),
            generation: generation,
            cost: AddonResourceRequest(
                profile: .eventDriven,
                requestedMemoryMiB: 1,
                maximumConcurrentWork: 1,
                background: .none
            )
        )
    }

    @Test
    func rejectsStaleAndDuplicateGrantSnapshots() throws {
        let generation = ConnectionGeneration()
        let token = try grant(generation: generation)
        let context = try AddonContext(
            services: UnavailableServices(),
            storage: UnavailableStorage(),
            generation: generation,
            grants: [token]
        )
        #expect(context.grants == [token])
        #expect(throws: (any Error).self) {
            try AddonContext(
                services: UnavailableServices(),
                storage: UnavailableStorage(),
                generation: ConnectionGeneration(),
                grants: [token]
            )
        }
        #expect(throws: (any Error).self) {
            try AddonContext(
                services: UnavailableServices(),
                storage: UnavailableStorage(),
                generation: generation,
                grants: [token, token]
            )
        }
    }

    @Test
    func rejectsServiceEventOutsideGrantedOperation() throws {
        let token = try grant(generation: ConnectionGeneration())
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID: "status",
            operation: "write",
            payload: Data()
        )
        #expect(throws: (any Error).self) {
            try ServiceEvent(subscriptionID: UUID(), token: token, response: response)
        }
    }

    @Test
    func archivesServiceEventsWithCurrentToken() throws {
        let token = try grant(generation: ConnectionGeneration())
        let response = try ServiceResponse(
            schemaVersion: 1,
            contractID: "status",
            operation: "read",
            payload: Data([1])
        )
        let event = AddonEvent.serviceChanged(
            try ServiceEvent(subscriptionID: UUID(), token: token, response: response)
        )
        #expect(try AddonEvent.decode(JSONEncoder().encode(event)) == event)
    }
    private actor RecordingAssets: AddonAssetClient {
        enum Event: Equatable {
            case imported(Data, PublicationID)
            case shared(AssetHandle, PublicationID)
            case released(AssetHandle)
        }
        private(set) var events: [Event] = []
        let original: AssetHandle
        let shared: AssetHandle

        init(
            original: AssetHandle,
            shared  : AssetHandle
        ) {
            self.original = original
            self.shared = shared
        }

        func importAsset(
            _ data       : Data,
            publicationID: PublicationID
        ) async throws -> AssetHandle {
            events.append(.imported(data, publicationID))
            return original
        }

        func shareAsset(
            _ asset: AssetHandle,
            to     : PublicationID
        ) async throws -> AssetHandle {
            events.append(.shared(asset, to))
            return shared
        }

        func releaseAsset(_ asset: AssetHandle) async throws {
            events.append(.released(asset))
        }
    }

    private func asset(_ alias: String) throws -> AssetHandle {
        let owner = try #require(AddonID(rawValue: "com.example.test"))
        return try AssetHandle(
            assetID       : alias,
            owner         : owner,
            publicationID : PublicationID(
                addonID   : owner,
                instanceID: UUID(),
                sessionID : UUID()
            ),
            rasterRevision: 1,
            width         : 1,
            height        : 1,
            byteCount     : 4
        )
    }

    @Test func contextUsesInjectedAssetClientForImportShareAndRelease() async throws {
        let original = try asset("asset-original")
        let shared = try asset("asset-shared")
        let client = RecordingAssets(
            original: original,
            shared  : shared
        )
        let context = try AddonContext(
            services  : UnavailableServices(),
            storage   : UnavailableStorage(),
            assets    : client,
            generation: ConnectionGeneration(),
            grants    : []
        )
        let bytes = Data([1, 2, 3])
        let imported = try await context.assets.importAsset(
            bytes,
            publicationID: original.publicationID
        )
        let reused = try await context.assets.shareAsset(
            imported,
            to: shared.publicationID
        )
        try await context.assets.releaseAsset(imported)
        #expect(imported == original)
        #expect(reused == shared)
        #expect(await client.events == [
            .imported(bytes, original.publicationID),
            .shared(original, shared.publicationID),
            .released(original)
        ])
    }

    @Test func legacyContextExplicitlyRejectsUnavailableAssetOperations() async throws {
        let context = try AddonContext(
            services  : UnavailableServices(),
            storage   : UnavailableStorage(),
            generation: ConnectionGeneration(),
            grants    : []
        )
        let value = try asset("asset-unavailable")
        for operation in 0..<3 {
            do {
                switch operation {
                case 0:
                    _ = try await context.assets.importAsset(
                        Data(),
                        publicationID: value.publicationID
                    )
                case 1:
                    _ = try await context.assets.shareAsset(
                        value,
                        to: value.publicationID
                    )
                default:
                    try await context.assets.releaseAsset(value)
                }
                Issue.record("A context without transport accepted an asset operation")
            } catch let failure as AddonFailure {
                #expect(failure.code == .dependencyUnavailable)
            }
        }
    }

}
