//
//  AddonAssetClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonAssetClient manages immutable images through one authenticated connection.
/// The host assigns privacy partitions and rechecks all handles. Sharing creates a
/// fresh alias for the destination publication while reusing the admitted raster.
public protocol AddonAssetClient: Sendable {
    /// importAsset accepts complete encoded PNG/JPEG data, never paths or provider URLs.
    /// The host profile caps input at 1 MiB and decoded images at 1,000,000 pixels.
    func importAsset(
        _ data       : Data,
        publicationID: PublicationID
    ) async throws -> AssetHandle

    /// shareAsset requires live source and destination assignments in compatible privacy scopes.
    /// The returned alias has independent publication ownership; pixels are not decoded again.
    func shareAsset(
        _ asset: AssetHandle,
        to     : PublicationID
    ) async throws -> AssetHandle

    /// releaseAsset drops this connection's alias without removing already published images.
    /// A released alias cannot authorize subsequent publication revisions or further sharing.
    func releaseAsset(_ asset: AssetHandle) async throws
}

/// UnavailableAddonAssetClient preserves old contexts without inventing transport authority.
struct UnavailableAddonAssetClient: AddonAssetClient {
    func importAsset(
        _ data       : Data,
        publicationID: PublicationID
    ) async throws -> AssetHandle { throw unavailable() }

    func shareAsset(
        _ asset: AssetHandle,
        to     : PublicationID
    ) async throws -> AssetHandle { throw unavailable() }

    func releaseAsset(_ asset: AssetHandle) async throws { throw unavailable() }

    private func unavailable() -> AddonFailure {
        AddonFailure(
            code  : .dependencyUnavailable,
            reason: "This context has no asset transport."
        )
    }
}
