//
//  RuntimeServiceSubscriptionReceipt.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct RuntimeServiceSubscriptionReceipt: Equatable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    let sequence: UInt64
    let kind: RuntimeServiceSubscriptionReceiptKind
}
