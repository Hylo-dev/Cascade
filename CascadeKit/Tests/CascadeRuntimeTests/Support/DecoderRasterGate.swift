//
//  DecoderRasterGate.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// DecoderRasterGate pauses real canonical admission to expose teardown races deterministically.
actor DecoderRasterGate: AssetReservationAccess {

    nonisolated let assetGovernor: ResourceGovernor

    private var entered = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    init(governor: ResourceGovernor) { assetGovernor = governor }

    func reserveRaster(
        bytes: Int,
        owner: AddonID
    ) async throws -> RetainedAssetToken {
        let token = try await assetGovernor.admitRetainedAsset(bytes: bytes, owner: owner)
        entered   = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { blocked = $0 }

        return token
    }

    func disposeRaster(_ token: RetainedAssetToken) async throws {
        try await assetGovernor.completeRetainedAsset(token, owner: token.reservation.owner)
    }

    func reached() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }

    func open() {
        blocked?.resume()
        blocked = nil
    }
}
