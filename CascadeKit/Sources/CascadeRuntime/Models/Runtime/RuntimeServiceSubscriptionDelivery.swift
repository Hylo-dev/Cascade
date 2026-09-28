//
//  RuntimeServiceSubscriptionDelivery.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct RuntimeServiceSubscriptionDelivery: Equatable, Sendable {
    let receipt: RuntimeServiceSubscriptionReceipt
    let payload: Data
}
