//
//  FailingStorage.swift
//  StandaloneClock
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneClockProvider
import Testing

struct FailingStorage: AddonStorageClient {

    func read(key: String) async throws -> Data? { throw UnexpectedCapability.call }

    func write(
        _ data: Data,
        key   : String
    ) async throws {
        throw UnexpectedCapability.call
    }

    func remove(key: String) async throws { throw UnexpectedCapability.call }
}
