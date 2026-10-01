//
//  RuntimeAssetReceipt.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeAssetReceipt binds one accepted asset reply to its host nonce and canonical connection.
struct RuntimeAssetReceipt: Equatable, Sendable {

    let token          : UUID
    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let sequence       : UInt64
    let requestID      : UUID
    let operation      : AssetTransferOperation
}
