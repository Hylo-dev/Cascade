//
//  InvocationRuntimeByteChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// InvocationRuntimeByteChannel carries one admitted exchange at a time, whose single
/// terminal event is adapter-owned and physically settled on reply rejection/suppression
/// too. Returned buffers remain protected by withInvocationHost until actual caller
/// disposal and joined task cleanup.
final class InvocationRuntimeByteChannel: AddonServiceInvocationMessageChannel, @unchecked Sendable {

    let runtime   : AddonRuntime
    let adapter   : InvocationMessageAdapter
    let connection: RuntimeConnection

    private let lock      = NSLock()
    private var active   : InvocationByteEvent?
    private var drainTask: Task<Void, Never>?

    let closeStarted    = InvocationByteEvent()
    let requestReturned = InvocationByteEvent()

    var hasPhysicalExchange: Bool { lock.withLock { active != nil } }

    var generation: ConnectionGeneration { connection.publicationConnection.generation }

    var profile: ServiceInvocationFrameProfile? {
        connection.publicationConnection.negotiatedProtocol.serviceInvocationFrameProfile
    }

    init(host: InvocationMessageHost) {
        runtime    = host.runtime
        adapter    = host.adapter
        connection = host.consumer
    }

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> AddonServiceInvocationMessageExchangeResult {
        let finished = try lock.withLock {
            guard drainTask == nil else { throw AddonFailure(code: .sessionRevoked, reason: "Closed channel") }
            guard active == nil else { throw AddonFailure(code: .resourceDenied, reason: "Occupied channel") }

            let event = InvocationByteEvent()
            active = event

            return event
        }

        defer {
            lock.withLock { active = nil }
            finished.signal()
        }

        guard let handle = adapter.stage(
            frame,
            connection: connection,
            sequence  : sequence,
            kind      : .invocation
        ) else {
            return .rejectedBeforeHandoff
        }

        let result = await runtime.receiveServiceRequest(handle, connection: connection)
        requestReturned.signal()
        guard case .admitted = result else {
            throw AddonFailure(code: .outcomeUnknown, reason: "Host processing refused")
        }

        await adapter.consumerEvent.wait()
        guard case .serviceReply(let delivery) = adapter.payload(connection.incarnation) else {
            throw AddonFailure(code: .outcomeUnknown, reason: "Physical exchange was suppressed")
        }

        let bytes = delivery.payload.withUnsafeBytes { Data($0) }
        guard await runtime.receiveServiceReceipt(delivery.receipt, connection: connection) else {
            throw AddonFailure(code: .outcomeUnknown, reason: "Reply authority was lost")
        }

        return .response(bytes)
    }

    func close() async {
        let task = lock.withLock {
            if let drainTask { return drainTask }
            let runtime = runtime, connection = connection, finished = active, started = closeStarted
            let task = Task {
                await runtime.closeConnection(connection)
                started.signal()
                if let finished { await finished.wait() }
            }

            drainTask = task

            return task
        }

        await task.value
    }
}
