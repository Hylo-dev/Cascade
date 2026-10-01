//
//  RuntimeServiceSubscriptionDelivery.swift
//  CascadeKit
//

import Foundation

struct RuntimeServiceSubscriptionDelivery: Equatable, Sendable {

    let receipt: RuntimeServiceSubscriptionReceipt
    let payload: Data
}
