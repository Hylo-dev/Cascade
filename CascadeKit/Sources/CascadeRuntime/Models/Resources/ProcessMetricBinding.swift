//
//  ProcessMetricBinding.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricBinding is an explicitly supplied observational expectation, scoped to one host
/// binding and clock domain. Birth ticks and executable UUID do not authenticate a publisher,
/// identify every exec generation, or grant any process-control authority.
struct ProcessMetricBinding: Equatable, Sendable {

    let pid               : Int32
    let birthAbsoluteTicks: UInt64
    let executableUUID    : UUID
    let token             : UUID
    let clockDomain       : UUID

    var isValid: Bool {
        pid > 0 && birthAbsoluteTicks > 0 && executableUUID != Self.zeroUUID
    }

    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
