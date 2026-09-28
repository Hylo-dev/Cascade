//
//  RuntimeServiceIngressHandle.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct RuntimeServiceIngressHandle: Hashable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let encodedBytes: Int
    let sequence: UInt64
    let kind: RuntimeServiceIngressKind
}
