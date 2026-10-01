//
//  FailingAssets.swift
//  StandaloneClock
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneClockProvider
import Testing

struct FailingAssets: AddonAssetClient {

    func importAsset(
        _ data       : Data,
        publicationID: PublicationID
    ) async throws -> AssetHandle {
        throw UnexpectedCapability.call
    }

    func shareAsset(
        _ asset         : AssetHandle,
        to publicationID: PublicationID
    ) async throws -> AssetHandle {
        throw UnexpectedCapability.call
    }

    func releaseAsset(_ asset: AssetHandle) async throws { throw UnexpectedCapability.call }
}
