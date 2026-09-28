//
//  ProtocolNegotiator.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// NegotiatedProtocol records the library-supported intersection. It is immutable,
/// not decodable, and carries no connection authority on its own.
public struct NegotiatedProtocol: Equatable, Sendable {
    public let major         : Int
    public let minor         : Int
    public let contentSchemas: [Int]

    /// storageFrameProfile exposes implemented frame syntax, not connection authority.
    public var storageFrameProfile: StorageFrameProfile? { minor >= 1 ? .v1_1 : nil }

    /// assetFrameProfile exposes the dedicated asset frame profile for cumulative 1.2.
    public var assetFrameProfile: AssetTransferFrameProfile? { minor >= 2 ? .v1 : nil }

    public var serviceInvocationFrameProfile: ServiceInvocationFrameProfile? { minor >= 3 ? .v1_3 : nil }

    public var serviceSubscriptionFrameProfile: ServiceSubscriptionFrameProfile? { minor >= 4 ? .v1_4 : nil }

    fileprivate init(
        minor         : Int,
        contentSchemas: [Int]
    ) {
        major               = 1
        self.minor          = minor
        self.contentSchemas = contentSchemas
    }
}

/// ProtocolNegotiator selects the host's implemented version from untrusted
/// capabilities and a separately verified manifest requirement.
public enum ProtocolNegotiator {
    /// negotiate defaults to protocol 1.0. Only a host implementing keyed-storage
    /// dispatch may opt into 1.1; 1.2 additionally requires an asset-capable runtime
    /// adapter. An untrusted offer cannot enable either host capability.
    public static func negotiate(
        offer                       : ProtocolOffer,
        manifestProtocol            : ProtocolVersion,
        contentSchemas              : [Int] = [1, 2],
        supportsKeyedStorageFrames  : Bool = false,
        supportsAssetFrames         : Bool = false,
        supportsFileWorkspaceContent: Bool = false
    ) throws -> NegotiatedProtocol {
        try negotiate(
            offer                       : offer,
            manifestProtocol            : manifestProtocol,
            contentSchemas              : contentSchemas,
            supportsKeyedStorageFrames  : supportsKeyedStorageFrames,
            supportsAssetFrames         : supportsAssetFrames,
            supportsFileWorkspaceContent: supportsFileWorkspaceContent,
            serviceHost                 : false
        )
    }

    /// negotiate accepts serviceHost only from the complete runtime assembly; offers/profiles
    /// confer no authority.
    static func negotiate(
        offer                       : ProtocolOffer,
        manifestProtocol            : ProtocolVersion,
        contentSchemas              : [Int] = [1, 2],
        supportsKeyedStorageFrames  : Bool,
        supportsAssetFrames         : Bool,
        supportsFileWorkspaceContent: Bool = false,
        serviceHost                 : Bool,
        subscriptionHost            : Bool = false
    ) throws -> NegotiatedProtocol {
        try offer.validate()
        try manifestProtocol.validate()
        guard !contentSchemas.isEmpty,
            contentSchemas.count <= 3,
            Set(contentSchemas).count == contentSchemas.count,
            Set(contentSchemas).isSubset(of: [1, 2, 3]),
            supportsFileWorkspaceContent || !contentSchemas.contains(3)
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Invalid host content schema policy."
            )
        }
        guard offer.major == 1, manifestProtocol.major == 1 else {
            throw AddonFailure(
                code  : .versionConflict,
                reason: "Provider and manifest require an unsupported protocol major."
            )
        }
        let lower = max(
            offer.minimumMinor,
            manifestProtocol.minimumMinor
        )
        let upper = min(
            offer.maximumMinor,
            supportsKeyedStorageFrames ? (supportsAssetFrames ? (serviceHost ? (subscriptionHost ? 4 : 3) : 2) : 1) : 0
        )
        guard lower <= upper else {
            throw AddonFailure(
                code  : .versionConflict,
                reason: "No implemented protocol minor satisfies both requirements."
            )
        }
        let commonSchemas = Set(contentSchemas).intersection(offer.contentSchemas).sorted()
        guard !commonSchemas.isEmpty else {
            throw AddonFailure(
                code  : .versionConflict,
                reason: "No supported content schema is common to this connection."
            )
        }
        return NegotiatedProtocol(
            minor         : upper,
            contentSchemas: commonSchemas
        )
    }
}
