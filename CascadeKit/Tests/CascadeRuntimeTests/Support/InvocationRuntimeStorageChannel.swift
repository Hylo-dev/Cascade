//
//  InvocationRuntimeStorageChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// InvocationRuntimeStorageChannel wires the real SDK storage channel straight to canonical
/// host handlers. All allocations and returned values stay inside withInvocationHost's
/// prepaid scope; no OS channel is modeled.
final class InvocationRuntimeStorageChannel: AddonStorageMessageChannel, @unchecked Sendable {

    let host      : InvocationMessageHost
    let connection: RuntimeConnection

    var generation: ConnectionGeneration { connection.publicationConnection.generation }

    var profile: StorageFrameProfile? { connection.publicationConnection.negotiatedProtocol.storageFrameProfile }

    init(
        host      : InvocationMessageHost,
        connection: RuntimeConnection? = nil
    ) {
        self.host       = host
        self.connection = connection ?? host.consumer
    }

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> AddonStorageMessageExchangeResult {
        guard let handle = host.adapter.stageStorage(
            frame,
            connection: connection,
            sequence  : sequence
        ) else {
            return .rejectedBeforeHandoff
        }

        _ = await host.runtime.receiveStorageRequest(handle, connection: connection)

        guard case .storageResponse(let delivery) = host.adapter.payload(connection.incarnation) else {
            throw AddonFailure(code: .outcomeUnknown, reason: "No storage reply")
        }

        let bytes = delivery.payload.withUnsafeBytes { Data($0) }

        guard await host.runtime.receiveStorageReceipt(delivery.receipt, connection: connection) else {
            throw AddonFailure(code: .outcomeUnknown, reason: "Storage receipt rejected")
        }

        return .response(bytes)
    }

    func close() async { await host.runtime.closeConnection(connection) }
}
