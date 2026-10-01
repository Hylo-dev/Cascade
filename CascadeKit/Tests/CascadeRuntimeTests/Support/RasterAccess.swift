//
//  RasterAccess.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

actor RasterAccess: AssetReservationAccess {
    nonisolated let assetGovernor: ResourceGovernor
    var admissionGate: RasterGate?
    var refundGate: RasterGate?
    var failRefund = false
    private(set) var lastToken: RetainedAssetToken?
    private(set) var admissions = 0
    private(set) var refunds = 0
    init(_ governor: ResourceGovernor, admission: RasterGate? = nil,
         refund: RasterGate? = nil, failRefund: Bool = false) {
        assetGovernor = governor
        admissionGate = admission
        refundGate = refund
        self.failRefund = failRefund
    }
    func reserveRaster(bytes: Int, owner: AddonID) async throws -> RetainedAssetToken {
        let result = try await assetGovernor.admitRetainedAsset(bytes: bytes, owner: owner)
        lastToken = result
        admissions += 1
        if let gate = admissionGate { admissionGate = nil; await gate.pause() }
        return result
    }
    func disposeRaster(_ token: RetainedAssetToken) async throws {
        refunds += 1
        if let gate = refundGate { refundGate = nil; await gate.pause() }
        if failRefund { throw AddonFailure(code: .resourceDenied, reason: "Injected before the real refund.") }
        try await assetGovernor.completeRetainedAsset(token, owner: token.reservation.owner)
    }
}
