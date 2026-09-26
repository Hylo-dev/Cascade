//
//  SwiftDataArchiveValues.swift
//  Cascade
//

import Foundation

/// SwiftDataArchiveGeneration carries one bounded immutable owner generation.
struct SwiftDataArchiveGeneration: Equatable, Sendable {
    let schemaVersion : Int
    let revision      : UInt64
    let verifiedDigest: String
    let payload       : Data
}

/// SwiftDataArchiveFailure distinguishes rejected operations from committed save outcomes.
enum SwiftDataArchiveFailure: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidGeneration
    case unavailable
    case busy
    case unsafePath
    case staleRevision
    case corrupt
    case futureFormat
    case accounting
    case cancelled
}

/// SwiftDataArchiveStatus describes logical availability, never physical database closure.
struct SwiftDataArchiveStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case unavailable
        case ready
        case overbudget
        case suspended
        case faulted
    }
    let state             : State
    let measuredBytes     : Int
    let ownerOverageBytes : Int
    let globalOverageBytes: Int
    let isBusy            : Bool
}

/// SwiftDataArchiveSaveOutcome preserves a known commit even when later observation fails.
struct SwiftDataArchiveSaveOutcome: Equatable, Sendable {
    let revision: UInt64
    let status  : SwiftDataArchiveStatus
}

extension SwiftDataArchiveGeneration {
    static let maximumPayloadBytes = 8 * 1_024 * 1_024

    /// validate rejects unsupported or oversized input before the backend retains a controlled copy.
    func validate() throws {
        guard schemaVersion <= 1 else { throw SwiftDataArchiveFailure.futureFormat }
        guard schemaVersion == 1,
              revision > 0,
              !verifiedDigest.isEmpty,
              verifiedDigest.utf8.count <= 512,
              payload.count <= Self.maximumPayloadBytes else {
            throw SwiftDataArchiveFailure.invalidGeneration
        }
    }

    /// ownedCopy severs caller excess capacity only after protected workspace admission.
    func ownedCopy() -> SwiftDataArchiveGeneration {
        SwiftDataArchiveGeneration(
            schemaVersion : schemaVersion,
            revision      : revision,
            verifiedDigest: String(
                decoding: verifiedDigest.utf8,
                as      : UTF8.self
            ),
            payload: payload.withUnsafeBytes { Data($0) }
        )
    }
}

/// SwiftDataArchiveInventoryStatus separates reconciled directory inventory from model validity.
enum SwiftDataArchiveInventoryStatus: Equatable, Sendable {
    case unobserved
    case absent
    case complete
    case blocked
}
