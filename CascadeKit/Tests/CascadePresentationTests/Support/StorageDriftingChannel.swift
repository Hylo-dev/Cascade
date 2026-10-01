//
//  StorageDriftingChannel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

/// StorageDriftingChannel is a contract-violating dependency; it checks that cached syntax
/// cannot authorize shifted bytes.
final class StorageDriftingChannel: AddonStorageMessageChannel, @unchecked Sendable {

    let inner = StorageScriptChannel()

    private let lock         = NSLock()
    private let original     = ConnectionGeneration()
    private let replacement  = ConnectionGeneration()
    private let profileDrift: Bool
    private var shifted      = false

    var generation: ConnectionGeneration {
        lock.withLock { shifted && !profileDrift ? replacement : original }
    }

    var profile: StorageFrameProfile? { lock.withLock { shifted && profileDrift ? nil : .v1_1 } }

    init(profileDrift: Bool) { self.profileDrift = profileDrift }

    func shift() { lock.withLock { shifted = true } }

    func exchange(
        _ frame : Data,
        sequence: UInt64
    ) async throws -> AddonStorageMessageExchangeResult {
        try await inner.exchange(frame, sequence: sequence)
    }

    func close() async { await inner.close() }
}
