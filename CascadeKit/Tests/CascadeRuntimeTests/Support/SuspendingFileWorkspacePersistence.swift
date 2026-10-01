//
//  SuspendingFileWorkspacePersistence.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

actor SuspendingFileWorkspacePersistence: FileWorkspacePersisting {
    let base: FoundationFileWorkspacePersistence
    private var shouldSuspend = false
    private var suspended = false
    private var waiter   : CheckedContinuation<Void, Never>?
    private var resume   : CheckedContinuation<Void, Never>?

    init(base: FoundationFileWorkspacePersistence) { self.base = base }

    func suspendNextSave() { shouldSuspend = true }
    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resumeSave() { resume?.resume(); resume = nil; suspended = false }
    func load() async throws -> Data? { try await base.load() }
    func save(_ data: Data) async throws {
        if shouldSuspend {
            shouldSuspend = false
            suspended = true
            waiter?.resume()
            waiter = nil
            await withCheckedContinuation { resume = $0 }
        }
        try await base.save(data)
    }
}
