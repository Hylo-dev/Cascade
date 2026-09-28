//
//  FileWorkspacePreparedEntry.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import UniformTypeIdentifiers

/// FileWorkspacePreparedEntry captures one exact store lifetime without retaining a delivery pin.
struct FileWorkspacePreparedEntry: Equatable, Sendable {
    let writerID      : UUID
    let id            : UUID
    let name          : String
    let typeIdentifier: String
    let ownership     : FileOwnership
    let identity      : FileReferenceIdentity
    let managedName   : String?
    let generation    : UUID?
}
