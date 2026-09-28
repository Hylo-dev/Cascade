//
//  FileReferenceIdentity.swift
//  CascadeKit
//

import Darwin
import Foundation

/// FileReferenceIdentity binds a persistent reference to one filesystem object.
struct FileReferenceIdentity: Codable, Equatable, Hashable, Sendable {
    let device    : UInt64
    let inode     : UInt64
    let generation: UInt64
}
