//
//  AddonRuntimeAdapter.swift
//  CascadeKit
//

import CascadeContracts

/// AddonRuntimeAdapter is a synchronous host transport boundary with no production conformer yet.
/// Implementations must not run addon code, wait for IPC or invoke AddonRuntime recursively.
/// rejectedBeforeHandoff guarantees the delivery was neither exposed nor retained.
/// Accepted data occupies one bounded incarnation slot until receipt, stop or exit.
/// Runtime keeps an exact work credit until its matching synchronous receipt. An action
/// acknowledgment releases that payload but does not terminate the provider job.
protocol AddonRuntimeAdapter: Sendable {

    func takeIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    ) -> ProviderOutput?

    /// rejectIngress removes only a staged value; it cannot revoke another caller's transfer.
    func rejectIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    )

    /// cancelIngress is available only to the invocation that successfully took the transfer.
    func cancelIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    )

    /// finishIngress disposes only the successful taker's transfer. Runtime retains its exact
    /// invocation claim through this call, including when deferred cleanup owns that claim.
    func finishIngress(
        _ handle   : RuntimeIngressHandle,
        incarnation: RuntimeIncarnation
    )

    func tryHandoff(
        incarnation: RuntimeIncarnation,
        delivery   : RuntimeAdapterDelivery
    ) -> RuntimeHandoffResult

    func requestStop(
        incarnation: RuntimeIncarnation,
        reason     : RuntimeStopReason
    )

    /// deliveryWasReceived is called only after runtime matches the exact current work credit.
    /// It must dispose the occupied payload synchronously without recursively entering runtime.
    func deliveryWasReceived(incarnation: RuntimeIncarnation)

    func processDidExit(incarnation: RuntimeIncarnation)
}
