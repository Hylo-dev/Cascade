//
//  NativeSwiftDataArchiveCommitCheck.swift
//  CascadeKit
//

import Darwin
import Foundation

/// NativeSwiftDataArchiveCommitCheck rejects root replacement before committing changed models.
struct NativeSwiftDataArchiveCommitCheck: SwiftDataArchiveCommitChecking {

    func validateCommit(
        root      : URL,
        descriptor: Int32
    ) throws {
        try SwiftDataArchiveDirectory.validateHeldRoot(
            root      : root,
            descriptor: descriptor
        )
    }
}
