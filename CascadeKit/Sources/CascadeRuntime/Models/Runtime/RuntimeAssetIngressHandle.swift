//
//  RuntimeAssetIngressHandle.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeAssetIngressHandle identifies one raw asset frame in the shared typed ingress slot.
/// encodedBytes is checked before transfer and against the actual compact value after taking it.
/// sequence is strictly increasing per canonical connection; a request UUID grants no replay.
struct RuntimeAssetIngressHandle: Hashable, Sendable {
    let token       : UUID
    let incarnation : RuntimeIncarnation
    let encodedBytes: Int
    let sequence    : UInt64
}
