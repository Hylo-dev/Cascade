//
//  AddonContext.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

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
