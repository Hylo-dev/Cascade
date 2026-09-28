//
//  SwiftDataArchiveGeneration.swift
//  CascadeKit
//

import Foundation

/// SwiftDataArchiveGeneration carries one bounded immutable owner generation.
struct SwiftDataArchiveGeneration: Equatable, Sendable {
    let schemaVersion : Int
    let revision      : UInt64
    let verifiedDigest: String
    let payload       : Data
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
