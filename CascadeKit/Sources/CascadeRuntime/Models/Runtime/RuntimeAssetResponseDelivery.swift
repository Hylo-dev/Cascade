//
//  RuntimeAssetResponseDelivery.swift
//  CascadeKit
//

import Foundation

/// RuntimeAssetResponseDelivery retains encoded bytes only in prepaid adapter payload capacity.
struct RuntimeAssetResponseDelivery: Equatable, Sendable {

    let receipt: RuntimeAssetReceipt
    let payload: Data
}
