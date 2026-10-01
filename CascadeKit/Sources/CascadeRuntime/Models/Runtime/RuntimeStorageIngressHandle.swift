//
//  RuntimeStorageIngressHandle.swift
//  CascadeKit
//

import Foundation

/// RuntimeStorageIngressHandle identifies one raw frame in the shared typed ingress slot.
/// encodedBytes is checked before transfer and against the actual compact value after taking it.
/// sequence is strictly increasing per canonical connection; a request UUID grants no replay.
struct RuntimeStorageIngressHandle: Hashable, Sendable {

    let token       : UUID
    let incarnation : RuntimeIncarnation
    let encodedBytes: Int
    let sequence    : UInt64
}
