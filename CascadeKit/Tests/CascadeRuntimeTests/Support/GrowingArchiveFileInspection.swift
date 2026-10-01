//
//  GrowingArchiveFileInspection.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import SwiftData
import Testing
@testable import CascadeRuntime

/// GrowingArchiveFileInspection changes one real file between the two real stat operations.
struct GrowingArchiveFileInspection: SwiftDataArchiveFileInspecting {

    func openFile(
        _ descriptor: Int32,
        name        : String
    ) throws -> (Int32, KeyedStorageDirectory.FileIdentity)? {
        let file = openat(
            descriptor,
            name,
            O_WRONLY | O_NOFOLLOW | O_CLOEXEC
        )

        guard file >= 0 else { throw SwiftDataArchiveFailure.unsafePath }

        defer { close(file) }

        guard ftruncate(file, 101) == 0 else { throw SwiftDataArchiveFailure.unsafePath }

        return try NativeSwiftDataArchiveFileInspection().openFile(descriptor, name: name)
    }
}
