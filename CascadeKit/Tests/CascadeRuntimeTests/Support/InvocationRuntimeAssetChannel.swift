//
//  InvocationRuntimeAssetChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

final class InvocationRuntimeAssetChannel: AddonAssetMessageChannel, @unchecked Sendable {
    let host: InvocationMessageHost
    let connection: RuntimeConnection
    var generation: ConnectionGeneration { connection.publicationConnection.generation }
    var profile: AssetTransferFrameProfile? { connection.publicationConnection.negotiatedProtocol.assetFrameProfile }
    init(host: InvocationMessageHost, connection: RuntimeConnection? = nil) { self.host = host; self.connection = connection ?? host.consumer }
    func exchange(_ frame: Data, sequence: UInt64) async throws -> Data {
        guard let h = host.adapter.stageAsset(frame, connection: connection, sequence: sequence) else { throw AddonFailure(code: .resourceDenied, reason: "No asset ingress") }
        _ = await host.runtime.receiveAssetRequest(h, connection: connection)
        guard case .assetResponse(let d) = host.adapter.payload(connection.incarnation) else { throw AddonFailure(code: .outcomeUnknown, reason: "No asset reply") }
        let bytes = d.payload.withUnsafeBytes { Data($0) }
        guard await host.runtime.receiveAssetReceipt(d.receipt, connection: connection) else { throw AddonFailure(code: .outcomeUnknown, reason: "Asset receipt rejected") }
        return bytes
    }
    func close() async { await host.runtime.closeConnection(connection) }
}
