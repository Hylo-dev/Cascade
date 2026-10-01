//
//  AssetImageDecoding.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AssetImageDecoding imports bounded encoded images for trusted host callers.
/// Accounting attribution does not authorize an addon to publish or read an asset.
protocol AssetImageDecoding: Sendable {

    var assetGovernor: ResourceGovernor { get }

    func decode(
        encoded: Data,
        owner  : AddonID
    ) async throws -> AssetRasterBacking

    func close()
}
