//
//  AssetReservationAccess.swift
//  CascadeKit
//

import CascadeContracts

/// AssetReservationAccess is the narrow reservation seam: a host adapter may delay forwarding, but
/// must name and use this exact canonical governor. There is no default success or independent
/// accounting.
protocol AssetReservationAccess: Sendable {

    var assetGovernor: ResourceGovernor { get }

    func reserveRaster(
        bytes: Int,
        owner: AddonID
    ) async throws -> RetainedAssetToken

    func disposeRaster(_ token: RetainedAssetToken) async throws
}
