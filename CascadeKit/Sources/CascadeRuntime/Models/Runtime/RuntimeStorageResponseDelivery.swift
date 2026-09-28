//
//  RuntimeStorageResponseDelivery.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeStorageResponseDelivery retains encoded bytes only in prepaid adapter payload capacity.
struct RuntimeStorageResponseDelivery: Equatable, Sendable {
    let receipt: RuntimeStorageReceipt
    let payload: Data
}
