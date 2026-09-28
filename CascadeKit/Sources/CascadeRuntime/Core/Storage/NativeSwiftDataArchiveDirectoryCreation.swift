//
//  NativeSwiftDataArchiveDirectoryCreation.swift
//  CascadeKit
//

import Darwin
import Foundation

/// NativeSwiftDataArchiveDirectoryCreation forwards strict provisioning to the existing secure helper.
struct NativeSwiftDataArchiveDirectoryCreation: SwiftDataArchiveDirectoryCreating {
    func createDirectory(
        parentDescriptor: Int32,
        name            : String
    ) throws {
        try KeyedStorageDirectory.createDirectory(
            parentDescriptor,
            name: name
        )
    }
}
