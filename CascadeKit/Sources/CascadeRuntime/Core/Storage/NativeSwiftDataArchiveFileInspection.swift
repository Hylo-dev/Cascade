//
//  NativeSwiftDataArchiveFileInspection.swift
//  CascadeKit
//

import Darwin
import Foundation

/// NativeSwiftDataArchiveFileInspection measures regular files without a quota-truncated inventory.
struct NativeSwiftDataArchiveFileInspection: SwiftDataArchiveFileInspecting {

    func openFile(
        _ descriptor: Int32,
        name        : String
    ) throws -> (Int32, KeyedStorageDirectory.FileIdentity)? {
        try KeyedStorageDirectory.file(
            descriptor,
            name   : name,
            maximum: Int.max
        )
    }
}
