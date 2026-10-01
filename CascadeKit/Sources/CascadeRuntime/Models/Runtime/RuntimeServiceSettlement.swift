//
//  RuntimeServiceSettlement.swift
//  CascadeKit
//

import Foundation

/// RuntimeServiceSettlement is one scalar settlement that withdraws an admitted consumer route
/// without disclosing history.
struct RuntimeServiceSettlement: Equatable, Sendable {

    let routeID        : UUID
    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let sequence       : UInt64
}
