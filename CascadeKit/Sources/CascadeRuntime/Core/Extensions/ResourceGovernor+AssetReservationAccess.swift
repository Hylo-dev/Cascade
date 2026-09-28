//
//  ResourceGovernor+AssetReservationAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

extension ResourceGovernor: AssetReservationAccess {
    nonisolated var assetGovernor: ResourceGovernor { self }
    func reserveRaster(bytes: Int, owner: AddonID) throws -> RetainedAssetToken {
        try admitRetainedAsset(bytes: bytes, owner: owner)
    }
    func disposeRaster(_ token: RetainedAssetToken) throws {
        try completeRetainedAsset(token, owner: token.reservation.owner)
    }
}
