//
//  AddonServiceInvocationMessageExchangeResult.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonServiceInvocationMessageExchangeResult certifies non-exposure only through
/// explicit request-side rejection. Ordinary throws and rejected reply delivery
/// imply unknown effects, even for operations named read.
internal enum AddonServiceInvocationMessageExchangeResult: Sendable {

    case response(Data)
    case rejectedBeforeHandoff
}
