//
//  ProcessMetricTimebase.swift
//  CascadeKit
//

import Foundation

struct ProcessMetricTimebase: Equatable, Sendable {
    let numer: UInt32
    let denom: UInt32

    var isValid: Bool { numer > 0 && denom > 0 }
}
