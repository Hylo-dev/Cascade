//
//  FailingArchiveCommitCheck.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import SwiftData
import Testing
@testable import CascadeRuntime

/// FailingArchiveCommitCheck injects failure only after forwarding real root validation.
final class FailingArchiveCommitCheck: SwiftDataArchiveCommitChecking, @unchecked Sendable {

    enum Failure: Error { case injected }

    private let lock       = NSLock()
    private var shouldFail = false

    func failNextCommit() { lock.withLock { shouldFail = true } }

    func validateCommit(
        root      : URL,
        descriptor: Int32
    ) throws {
        try NativeSwiftDataArchiveCommitCheck().validateCommit(root: root, descriptor: descriptor)

        let fail = lock.withLock {
            let fail   = shouldFail
            shouldFail = false
            return fail
        }
        if fail { throw Failure.injected }
    }
}
