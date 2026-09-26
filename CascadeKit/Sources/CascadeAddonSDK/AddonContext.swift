//
//  AddonContext.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// AddonServiceClient exposes broker requests with explicit grants and validated wire values.
/// P2 supplies the transport and authenticates, correlates and bounds each response.
public protocol AddonServiceClient: Sendable {
    func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse
    func subscribe(requirementID: String, grant: Grant) async throws -> UUID
    func unsubscribe(subscriptionID: UUID) async throws
}

/// AddonStorageClient limits storage to the authenticated addon's namespace.
/// Implementations enforce quotas, key validation and permissions at the broker boundary.
public protocol AddonStorageClient: Sendable {
    func read(key: String) async throws -> Data?
    func write(_ data: Data, key: String) async throws
    func remove(key: String) async throws
}

/// AddonContext injects capabilities for one connection generation, without host engine access.
/// Grants are a snapshot, not proof of authorization: the broker must recheck every operation.
public struct AddonContext: Sendable {
    public let services  : any AddonServiceClient
    public let storage   : any AddonStorageClient
    public let assets    : any AddonAssetClient
    public let generation: ConnectionGeneration
    public let grants    : [Grant]

    /// init preserves the existing services/storage context with an unavailable asset capability.
    public init(
        services  : any AddonServiceClient,
        storage   : any AddonStorageClient,
        generation: ConnectionGeneration,
        grants    : [Grant]
    ) throws {
        try self.init(
            services  : services,
            storage   : storage,
            assets    : UnavailableAddonAssetClient(),
            generation: generation,
            grants    : grants
        )
    }

    /// init installs connection-bound clients while preserving canonical grant-snapshot checks.
    public init(
        services  : any AddonServiceClient,
        storage   : any AddonStorageClient,
        assets    : any AddonAssetClient,
        generation: ConnectionGeneration,
        grants    : [Grant]
    ) throws {
        guard grants.allSatisfy({ $0.generation == generation }),
            Set(grants.map(\.id)).count == grants.count,
            grants.count <= 64
        else {
            throw AddonFailure(code: .invalidPayload, reason: "Invalid context grant snapshot")
        }
        self.services   = services
        self.storage    = storage
        self.assets     = assets
        self.generation = generation
        self.grants     = grants
    }
}
