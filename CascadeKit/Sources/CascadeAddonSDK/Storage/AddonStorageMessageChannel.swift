//
//  AddonStorageMessageChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// A trusted request observation, not proof that the public SDK can independently authenticate.
public enum AddonStorageMessageExchangeResult: Sendable {
    /// Bounded bytes for the exact request. The channel has consumed the host's exact receipt.
    case response(Data)
    /// This request never reached host processing/backend execution; staging is disposed.
    /// Rejected response delivery, cancellation and generic errors never establish this result.
    case rejectedBeforeHandoff
}

/// Injected bytes for one already authenticated connection, not an OS bootstrap or allocator.
///
/// The embedding must preadmit caller source allocations, SDK encoding/decoding workspace and
/// returned-value lifetimes before request construction/encoding. Data.count does not bound a
/// view's backing allocation. Logical SDK admission and this protocol do not enforce that budget.
/// Implementations must admit and bound raw allocations before staging/parsing, retain no history,
/// and correlate the physical generation, increasing sequence, request UUID and operation.
/// Before returning response bytes they consume the host's exact response receipt and dispose
/// transport-owned staging; returned Data remains caller-owned in its continuing paid scope.
/// Neither receipt nor physical generation/sequence is carried in the public response Data.
/// Ordinary throws guarantee staging disposal, but never prove request rejection or rollback.
/// Cancellation must not abandon outstanding physical work. No production OS conformer ships.
public protocol AddonStorageMessageChannel: Sendable {
    /// Immutable, nonblocking physical-handshake description; it authenticates no peer itself.
    var generation: ConnectionGeneration { get }
    /// Storage schema-1 syntax under canonical negotiated 1.1 or cumulative 1.2; nil if unavailable.
    var profile: StorageFrameProfile? { get }
    func exchange(_ frame: Data, sequence: UInt64) async throws -> AddonStorageMessageExchangeResult
    /// Idempotently revoke physical admission and drain outstanding exchange/staging/receipts.
    /// This does not observe OS process exit or release caller-owned buffers/embedding scopes.
    func close() async
}
