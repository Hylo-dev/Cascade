//
//  FailingFileWorkspacePersistence.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

actor FailingFileWorkspacePersistence: FileWorkspacePersisting {
    let base: FoundationFileWorkspacePersistence
    private var shouldFail = false

    init(base: FoundationFileWorkspacePersistence) { self.base = base }

    func failNextSave() { shouldFail = true }
    func load() async throws -> Data? { try await base.load() }
    func save(_ data: Data) async throws {
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
        try await base.save(data)
    }
}
