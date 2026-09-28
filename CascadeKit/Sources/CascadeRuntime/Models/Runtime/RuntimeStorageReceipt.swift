//
//  RuntimeStorageReceipt.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeStorageReceipt binds one accepted reply to its host nonce and canonical connection.
struct RuntimeStorageReceipt: Equatable, Sendable {
    let token          : UUID
    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let sequence       : UInt64
    let requestID      : UUID
    let operation      : StorageOperation
}
