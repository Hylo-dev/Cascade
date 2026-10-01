//
//  RuntimeIngressHandle.swift
//  CascadeKit
//

import Foundation

/// RuntimeIngressHandle identifies one adapter-owned, bounded provider-output slot.
struct RuntimeIngressHandle: Hashable, Sendable {

    let token           : UUID
    let incarnation     : RuntimeIncarnation
    let encodedBytes    : Int
    let isCompletionOnly: Bool
}
