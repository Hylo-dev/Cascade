//
//  UnavailableAddonAssetClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// UnavailableAddonAssetClient preserves old contexts without inventing transport authority.
struct UnavailableAddonAssetClient: AddonAssetClient {

    func importAsset(
        _ data       : Data,
        publicationID: PublicationID
    ) async throws -> AssetHandle {
        throw unavailable()
    }

    func shareAsset(
        _ asset: AssetHandle,
        to     : PublicationID
    ) async throws -> AssetHandle {
        throw unavailable()
    }

    func releaseAsset(_ asset: AssetHandle) async throws { throw unavailable() }

    private func unavailable() -> AddonFailure {
        AddonFailure(
            code  : .dependencyUnavailable,
            reason: "This context has no asset transport."
        )
    }
}
