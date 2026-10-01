//
//  RuntimeAssetChannelBridge.swift
//  CascadeKit
//

import CascadeAddonSDK
import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// RuntimeAssetChannelBridge is a test-only `AddonAssetMessageChannel` over the real runtime.
///
/// It owns exactly one bounded physical exchange slot. Each exchange stages one raw frame in the
/// adapter's typed ingress slot, invokes the real host receive path, correlates the exact host
/// reply receipt against its own connection and sequence, consumes that receipt, and only then
/// hands the bounded reply `Data` to the caller. A duplicate or regressing sequence, an
/// out-of-bound frame and a second concurrent exchange are refused before any new staging, so the
/// bridge never retains an open-ended queue or per-frame history.
///
/// `close` revokes the exact authenticated connection through the runtime's existing lifecycle
/// path and then awaits the in-flight exchange; it never fabricates an observed native process
/// exit. Repeated and concurrent close callers all await that one drain rather than a closed flag.
///
/// The bridge is deliberately test-only: it authenticates nothing and implements no OS transport.
/// Its hold and fault points exist only so the tests can drive a physically in-flight exchange
/// deterministically, without sleeps or polling.
final class RuntimeAssetChannelBridge: AddonAssetMessageChannel, @unchecked Sendable {

    /// ExchangeHoldPoint names the one deterministic suspension a test can arm.
    enum ExchangeHoldPoint: Sendable {

        case beforeReceive
        case afterHandoff
    }

    /// Fault injects one bounded physical reply fault after the host has handed off its reply.
    enum Fault: Sendable {

        case mismatchedReceipt
        case transportError
    }

    let generation: ConnectionGeneration
    let profile   : AssetTransferFrameProfile?

    private let runtime     : AddonRuntime
    private let adapter     : RecordingRuntimeAdapter
    private let connection  : RuntimeConnection
    private let stateLock    = NSLock()
    private let exchangeGate = BridgeExchangeGate()
    private var lastSequence: UInt64 = 0
    private var inFlight    : Task<Data, any Error>?
    private var closeTask   : Task<Void, Never>?
    private var isRevoked    = false
    private var holdPoint   : ExchangeHoldPoint?
    private var armedFault  : Fault?

    private var drainedInFlightExchange = false

    init(
        runtime   : AddonRuntime,
        adapter   : RecordingRuntimeAdapter,
        connection: RuntimeConnection
    ) {
        self.runtime    = runtime
        self.adapter    = adapter
        self.connection = connection
        self.generation = connection.publicationConnection.generation
        self.profile    = connection.publicationConnection.negotiatedProtocol.assetFrameProfile
    }

    // MARK: Test-only deterministic points

    /// didDrainInFlightExchange is true once close has awaited a real in-flight exchange.
    var didDrainInFlightExchange: Bool { stateLock.withLock { drainedInFlightExchange } }

    /// armHold suspends exactly the next exchange at one deterministic physical point.
    func armHold(at point: ExchangeHoldPoint) async {
        stateLock.withLock { holdPoint = point }
        await exchangeGate.arm()
    }

    /// waitForHoldArrival blocks until the armed exchange has reached its held point.
    func waitForHoldArrival() async {
        await exchangeGate.waitForArrival()
    }

    /// armFault injects exactly one bounded physical fault on the next handed-off reply.
    func armFault(_ fault: Fault) {
        stateLock.withLock { armedFault = fault }
    }

    // MARK: AddonAssetMessageChannel

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> Data {
        let work = try claimExchangeSlot(frame, sequence: sequence)
        let reply: Data
        do {
            reply = try await work.value
        } catch {
            releaseExchangeSlot()
            throw error
        }

        releaseExchangeSlot()

        return reply
    }

    func close() async {
        let work: Task<Void, Never> = stateLock.withLock {
            if let existing = closeTask { return existing }
            isRevoked = true
            let created = Task { await self.performClose() }
            closeTask = created

            return created
        }

        await work.value
    }

    // MARK: Bounded physical exchange slot

    /// claimExchangeSlot takes the single bounded slot synchronously before any await.
    private func claimExchangeSlot(
        _ frame : Data,
        sequence: UInt64
    ) throws -> Task<Data, any Error> {
        try stateLock.withLock {
            guard !isRevoked else {
                throw AddonFailure(
                    code  : .sessionRevoked,
                    reason: "The bridge connection is revoked."
                )
            }

            guard inFlight == nil else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The bridge carries one physical exchange at a time."
                )
            }

            guard sequence > lastSequence else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "The bridge requires a strictly increasing physical sequence."
                )
            }

            guard frame.count > 0, frame.count <= AssetTransferFrameCodec.maximumEncodedBytes else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "The bridge refuses an out-of-bound encoded frame."
                )
            }

            lastSequence = sequence
            let created = Task { try await self.performExchange(frame, sequence: sequence) }
            inFlight = created

            return created
        }
    }

    private func releaseExchangeSlot() {
        stateLock.withLock { inFlight = nil }
    }

    /// performExchange stages, sends, correlates and consumes exactly one real host reply.
    private func performExchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> Data {
        let holdPoint = stateLock.withLock { self.holdPoint }
        guard
            let handle = adapter.stageAssetIngress(
                frame,
                incarnation: connection.incarnation,
                sequence   : sequence
            )
        else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The bridge could not stage the bounded asset frame."
            )
        }

        var ingressTaken = false
        defer {
            if !ingressTaken {
                adapter.rejectAssetIngress(handle, incarnation: connection.incarnation)
            }
        }

        if holdPoint == .beforeReceive {
            await exchangeGate.arrivalPoint()
            try checkRevoked()
        }

        let result = await runtime.receiveAssetRequest(handle, connection: connection)
        // The runtime always disposes its ingress claim before this call returns.
        ingressTaken = true
        switch result {
            case .refused(let code):
                throw AddonFailure(code: code, reason: "The host refused the asset frame.")

            case .completed(_, let disposition):
                guard disposition == .handedOff else {
                    throw AddonFailure(
                        code  : .resourceDenied,
                        reason: "The host did not hand off an asset reply."
                    )
                }
        }

        guard case .assetResponse(let delivery)? = adapter.currentDelivery(incarnation: connection.incarnation) else {
            throw AddonFailure(
                code  : .dependencyUnavailable,
                reason: "The bridge did not observe an asset reply."
            )
        }

        var receiptConsumed = false
        defer {
            if !receiptConsumed {
                // Drop only this incarnation's raw reply staging; the exact connection is
                // revoked before it can carry another frame, so the stale work credit is inert.
                adapter.deliveryWasReceived(incarnation: connection.incarnation)
            }
        }

        if holdPoint == .afterHandoff {
            await exchangeGate.arrivalPoint()
            try checkRevoked()
        }

        let receipt = try correlatedReceipt(delivery: delivery, sequence: sequence)
        guard await runtime.receiveAssetReceipt(
            receipt,
            connection: connection
        ) else {
            refuseReuseAfterFault()
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The bridge could not consume the exact asset receipt."
            )
        }

        receiptConsumed = true

        return delivery.payload
    }

    /// correlatedReceipt applies the one armed test-only fault and then verifies the physical
    /// correlation the bridge itself staged. The receipt never leaves the bridge.
    private func correlatedReceipt(
        delivery: RuntimeAssetResponseDelivery,
        sequence: UInt64
    ) throws -> RuntimeAssetReceipt {
        let fault = stateLock.withLock { () -> Fault? in
            let armed = armedFault
            armedFault = nil

            return armed
        }

        let receipt: RuntimeAssetReceipt
        switch fault {
            case .mismatchedReceipt:
                receipt = RuntimeAssetReceipt(
                    token          : delivery.receipt.token,
                    incarnation    : delivery.receipt.incarnation,
                    connectionToken: delivery.receipt.connectionToken,
                    sequence       : delivery.receipt.sequence &+ 1,
                    requestID      : delivery.receipt.requestID,
                    operation      : delivery.receipt.operation
                )

            case .transportError:
                refuseReuseAfterFault()
                throw AddonFailure(
                    code  : .dependencyUnavailable,
                    reason: "The bridge observed a physical transport error after handoff."
                )

            case .none:
                receipt = delivery.receipt
        }

        guard receipt.incarnation == connection.incarnation,
              receipt.connectionToken == connection.token,
              receipt.sequence == sequence
        else {
            refuseReuseAfterFault()
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The bridge observed a mismatched physical reply receipt."
            )
        }

        return receipt
    }

    /// checkRevoked revalidates the scalar closure after any suspension before send or consume.
    private func checkRevoked() throws {
        guard !stateLock.withLock({ isRevoked }) else {
            throw AddonFailure(code: .sessionRevoked, reason: "The bridge connection is revoked.")
        }
    }

    /// refuseReuseAfterFault stops new frames after an uncertain physical reply without waiting.
    private func refuseReuseAfterFault() {
        stateLock.withLock { isRevoked = true }
    }

    // MARK: Close and drain

    /// performClose revokes the exact authenticated connection and drains the in-flight exchange.
    ///
    /// The runtime validates and revokes the exact connection before disposing staging. The
    /// held exchange is then released explicitly and awaited to completion before close returns.
    private func performClose() async {
        await runtime.closeConnection(connection)
        await exchangeGate.release()
        guard let inFlightWork = stateLock.withLock({ inFlight }) else { return }

        _ = try? await inFlightWork.value
        stateLock.withLock { drainedInFlightExchange = true }
    }
}
