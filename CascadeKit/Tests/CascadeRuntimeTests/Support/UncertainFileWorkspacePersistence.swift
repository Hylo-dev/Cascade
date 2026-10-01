//
//  UncertainFileWorkspacePersistence.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

actor UncertainFileWorkspacePersistence: FileWorkspacePersisting {

    let base: FoundationFileWorkspacePersistence

    private var uncertain = false

    init(base: FoundationFileWorkspacePersistence) { self.base = base }

    func makeNextSaveUncertain() { uncertain = true }

    func load() async throws -> Data? { try await base.load() }

    func save(_ data: Data) async throws {
        try await base.save(data)

        if uncertain {
            uncertain = false
            throw FileWorkspacePersistenceFailure.commitUncertain
        }
    }
}
