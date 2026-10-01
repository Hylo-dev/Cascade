//
//  RuntimeServiceDelivery.swift
//  CascadeKit
//

import Foundation

struct RuntimeServiceDelivery: Equatable, Sendable {

    let receipt: RuntimeServiceReceipt
    let payload: Data
}
