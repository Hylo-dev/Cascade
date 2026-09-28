//
//  RuntimeServiceDelivery.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct RuntimeServiceDelivery: Equatable, Sendable {
    let receipt: RuntimeServiceReceipt
    let payload: Data
}
