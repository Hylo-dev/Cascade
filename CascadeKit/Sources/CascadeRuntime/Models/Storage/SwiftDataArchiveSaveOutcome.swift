//
//  SwiftDataArchiveSaveOutcome.swift
//  CascadeKit
//

import Foundation

/// SwiftDataArchiveSaveOutcome preserves a known commit even when later observation fails.
struct SwiftDataArchiveSaveOutcome: Equatable, Sendable {
    let revision: UInt64
    let status  : SwiftDataArchiveStatus
}
