import CascadeContracts
import Foundation

public enum AddonServiceMessageKind: Sendable { case invocation, control }
public enum AddonServiceMessageExchangeResult: Sendable {
    /// Terminal correlated bytes only; exact physical receipt has already been consumed.
    case response(Data)
    case rejectedBeforeHandoff
}

/// One authenticated, immutable physical connection. The embedding prepays codec,
/// raw, returned-value and callback lifetimes, including one latest event per alias
/// (at most 64), and a running handler. This protocol is not a native transport.
/// An unresolved unsubscribe retains that alias's same paid latest-event scope
/// until no-effect restoration or terminal discard; it adds no second payload.
/// Acquisition admission receipts are checked against the actual request, consumed
/// internally, and never returned as terminal responses. Receipt precedes event
/// reception; neither bind nor synchronous handoff may execute a receiver/handler.
/// close drains physical staging, independently of running user handlers.
public protocol AddonServiceMessageChannel: Sendable {
    var generation: ConnectionGeneration { get }
    var invocationProfile: ServiceInvocationFrameProfile? { get }
    var subscriptionProfile: ServiceSubscriptionFrameProfile? { get }
    func exchange(_ frame: Data, kind: AddonServiceMessageKind, sequence: UInt64) async throws -> AddonServiceMessageExchangeResult
    func bindServiceEvents(_ receiver: @escaping @Sendable (Data) async throws -> Void) throws
    func close() async
}
