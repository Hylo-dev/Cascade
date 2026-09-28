//
//  AddonStorageMessageExchangeResult.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonStorageMessageExchangeResult is a trusted request observation, not proof that the
/// public SDK can independently authenticate.
public enum AddonStorageMessageExchangeResult: Sendable {
    /// Bounded bytes for the exact request. The channel has consumed the host's exact receipt.
    case response(Data)
    /// This request never reached host processing/backend execution; staging is disposed.
    /// Rejected response delivery, cancellation and generic errors never establish this result.
    case rejectedBeforeHandoff
}
