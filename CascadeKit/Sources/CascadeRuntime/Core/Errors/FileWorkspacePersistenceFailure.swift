//
//  FileWorkspacePersistenceFailure.swift
//  CascadeKit
//

import Darwin
import Foundation

/// FileWorkspacePersistenceFailure distinguishes a rejected write from an uncertain durable commit.
enum FileWorkspacePersistenceFailure: Error {
    case notCommitted
    case commitUncertain
}
