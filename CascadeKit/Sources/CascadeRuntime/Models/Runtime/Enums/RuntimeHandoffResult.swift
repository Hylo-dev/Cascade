//
//  RuntimeHandoffResult.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeHandoffResult linearizes whether a bounded delivery reached adapter ownership.
enum RuntimeHandoffResult: Equatable, Sendable {
    case accepted
    case rejectedBeforeHandoff
}
