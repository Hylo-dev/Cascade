//
//  AddonServiceMessageExchangeResult.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

public enum AddonServiceMessageExchangeResult: Sendable {
    /// Terminal correlated bytes only; exact physical receipt has already been consumed.
    case response(Data)
    case rejectedBeforeHandoff
}
