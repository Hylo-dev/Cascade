//
//  RuntimeServiceReceipt.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct RuntimeServiceReceipt: Equatable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    let sequence: UInt64
    let requestID: UUID
    let kind: RuntimeServiceReceiptKind
}
