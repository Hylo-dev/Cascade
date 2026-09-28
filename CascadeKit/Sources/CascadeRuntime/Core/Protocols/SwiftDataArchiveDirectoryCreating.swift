//
//  SwiftDataArchiveDirectoryCreating.swift
//  CascadeKit
//

import Darwin
import Foundation

/// SwiftDataArchiveDirectoryCreating confines provisioning to the admitted synchronous mkdir boundary.
protocol SwiftDataArchiveDirectoryCreating: Sendable {
    func createDirectory(
        parentDescriptor: Int32,
        name            : String
    ) throws
}
