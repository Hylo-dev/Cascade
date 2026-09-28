//
//  FileWorkspaceManagedRemovalConfirmation.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import UniformTypeIdentifiers

/// FileWorkspaceManagedRemovalConfirmation makes deletion of Cascade's only copy explicit.
enum FileWorkspaceManagedRemovalConfirmation: Equatable, Sendable {
    case deleteOnlyManagedCopy
}
