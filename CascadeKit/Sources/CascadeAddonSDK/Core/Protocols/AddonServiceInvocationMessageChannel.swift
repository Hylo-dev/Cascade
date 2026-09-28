//
//  AddonServiceInvocationMessageChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonServiceInvocationMessageChannel is the authenticated physical connection an embedding
/// supplies. It prepays caller input, SDK codec workspace and returned buffers before
/// allocation through disposal. Data.count is not a backing-allocation bound. The channel
/// owns one compact paid staging slot, consumes the exact host receipt before returning
/// bytes, and settles suppression as well as success. Cancellation must not abandon physical
/// work. No native conformer or full public AddonServiceClient is provided here.
internal protocol AddonServiceInvocationMessageChannel: Sendable {
    var generation: ConnectionGeneration { get }
    var profile: ServiceInvocationFrameProfile? { get }
    func exchange(_ frame: Data, sequence: UInt64) async throws -> AddonServiceInvocationMessageExchangeResult
    /// Idempotent physical withdrawal/drain; does not release caller buffers or observe exit.
    func close() async
}
