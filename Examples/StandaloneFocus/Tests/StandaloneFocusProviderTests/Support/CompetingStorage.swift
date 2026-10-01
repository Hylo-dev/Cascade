//
//  CompetingStorage.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneFocusProvider
import Testing

// A controlled pair of reads demonstrates the public storage API's lack of CAS.
actor CompetingStorage: AddonStorageClient {

    var data : Data
    var reads: [CheckedContinuation<Data?, any Error>] = []

    init(_ data: Data) { self.data = data }

    func read(key: String) async throws -> Data? {
        #expect(key == StandaloneFocusProvider.storageKey)

        return try await withCheckedThrowingContinuation { continuation in
            reads.append(continuation)
            if reads.count == 2 {
                let snapshot = data
                for waitingRead in reads { waitingRead.resume(returning: snapshot) }
                reads.removeAll()
            }
        }
    }

    func write(
        _ data: Data,
        key   : String
    ) async throws {
        #expect(data.count <= 16_384)

        self.data = data
    }

    func remove(key: String) async throws { Issue.record("Unexpected remove") }
}
