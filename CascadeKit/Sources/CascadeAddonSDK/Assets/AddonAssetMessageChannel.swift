//
//  AddonAssetMessageChannel.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// AddonAssetMessageChannel is the injected, connection-bound byte interface used by
/// `MessageAddonAssetClient` to move one asset frame at a time.
///
/// It is **not** an authenticated bootstrap: the host must inject an instance only for an
/// already-authenticated connection, and the physical transport remains host-owned.
///
/// Implementations must:
/// - bound raw request/reply allocations before Foundation parses them;
/// - correlate the physical generation and the strictly increasing sequence;
/// - consume the host's exact response receipt before `exchange` returns, and hand the bounded
///   reply `Data` to the caller, who owns those bytes only within its bounded scope and never
///   sees or manipulates the receipt itself;
/// - dispose any transport-owned request/reply staging before `exchange` returns or throws.
///
/// `close` revokes the connection and drains outstanding exchange. Cancellation alone never
/// proves that a physical request was rejected or that transport staging was disposed, so
/// callers must not infer a completed or refused mutation merely from a cancelled call. A held
/// exchange is drained explicitly rather than abandoned on cancellation.
/// No production OS channel ships in this package; the runtime test bridge fulfills this
/// contract against the real host. The protocol makes no claim that any native transport is
/// installed or qualified.
public protocol AddonAssetMessageChannel: Sendable {
    /// generation identifies the physical handshake that issued this channel.
    var generation: ConnectionGeneration { get }
    /// profile is the asset syntax this channel can carry, or nil when unsupported.
    var profile: AssetTransferFrameProfile? { get }
    /// exchange sends exactly one authenticated frame and returns its exact encoded reply.
    /// The channel consumes the matching host receipt and disposes its request/reply staging
    /// before returning; the caller owns the returned bytes only within its bounded scope and
    /// never receives or manipulates the receipt itself.
    func exchange(_ frame: Data, sequence: UInt64) async throws -> Data
    /// close idempotently revokes this connection and drains any outstanding exchange.
    func close() async
}
