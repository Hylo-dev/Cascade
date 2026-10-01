//
//  SwiftDataArchiveCommitChecking.swift
//  CascadeKit
//

import Foundation

/// SwiftDataArchiveCommitChecking revalidates the held root at the actual save boundary.
/// Failure-injection implementations must forward the real check before a deliberate failure.
protocol SwiftDataArchiveCommitChecking: Sendable {

    func validateCommit(
        root      : URL,
        descriptor: Int32
    ) throws
}
