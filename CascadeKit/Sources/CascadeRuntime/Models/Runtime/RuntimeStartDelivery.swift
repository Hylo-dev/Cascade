//
//  RuntimeStartDelivery.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeStartDelivery carries bounded host authority for one cold-start request.
struct RuntimeStartDelivery: Equatable, Sendable {
    let launchID                  : RuntimeLaunchID
    let incarnation               : RuntimeIncarnation
    let identity                  : VerifiedAddonIdentity
    let digest                    : String
    let maximumIngressBytes       : Int
    let maximumStorageIngressBytes: Int
    let maximumServiceIngressBytes: Int
    let maximumAssetIngressBytes  : Int
    let maximumDeliveryBytes      : Int

    init(
        launchID                  : RuntimeLaunchID,
        incarnation               : RuntimeIncarnation,
        identity                  : VerifiedAddonIdentity,
        digest                    : String,
        maximumIngressBytes       : Int,
        maximumStorageIngressBytes: Int = 0,
        maximumAssetIngressBytes  : Int = 0,
        maximumServiceIngressBytes: Int = 0,
        maximumDeliveryBytes      : Int = 80 * 1_024
    ) {
        self.launchID = launchID
        self.incarnation = incarnation
        self.identity = identity
        self.digest = digest
        self.maximumIngressBytes = maximumIngressBytes
        self.maximumStorageIngressBytes = maximumStorageIngressBytes
        self.maximumAssetIngressBytes = maximumAssetIngressBytes
        self.maximumServiceIngressBytes = maximumServiceIngressBytes
        self.maximumDeliveryBytes = maximumDeliveryBytes
    }
}
