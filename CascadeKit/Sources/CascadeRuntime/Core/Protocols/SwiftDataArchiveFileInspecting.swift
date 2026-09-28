//
//  SwiftDataArchiveFileInspecting.swift
//  CascadeKit
//

import Darwin
import Foundation

/// SwiftDataArchiveFileInspecting confines deterministic scan races to a checked real file open.
/// Returned descriptors and identities must come from the existing safe filesystem helper.
protocol SwiftDataArchiveFileInspecting: Sendable {
    func openFile(
        _ descriptor: Int32,
        name        : String
    ) throws -> (Int32, KeyedStorageDirectory.FileIdentity)?
}
