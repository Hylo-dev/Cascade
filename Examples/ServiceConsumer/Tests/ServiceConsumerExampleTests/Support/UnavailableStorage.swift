//
//  UnavailableStorage.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

struct UnavailableStorage: AddonStorageClient {

    func read(key: String) async throws -> Data? {
        Issue.record("Unexpected storage read")
        throw CancellationError()
    }

    func write(
        _ data: Data,
        key   : String
    ) async throws {
        Issue.record("Unexpected storage write")
        throw CancellationError()
    }

    func remove(key: String) async throws {
        Issue.record("Unexpected storage remove")
        throw CancellationError()
    }
}
