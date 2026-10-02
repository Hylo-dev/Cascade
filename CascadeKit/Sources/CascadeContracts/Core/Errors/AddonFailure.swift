//
//  AddonFailure.swift
//  CascadeKit
//

import Foundation

/// AddonFailure carries a machine-readable failure and a bounded remedy for people.
///
/// The name outlived the addon platform: the plugin contracts, the plugin kernel, the manifest
/// tool and the file shelf's resource governor all throw it, so only the codes they raise
/// remain.
public struct AddonFailure: Error, Equatable, Sendable {

    public enum Code: String, Sendable {

        case permissionDenied, resourceDenied, invalidPayload
    }

    public let code  : Code
    public let reason: String

    /// AddonFailure preserves complete graphemes within a 4 KiB UTF-8 byte budget.
    /// Empty input, or an initial grapheme larger than the budget, receives a readable fallback.
    public init(
        code  : Code,
        reason: String
    ) {
        self.code = code

        var boundedReason = ""
        var byteCount     = 0
        for character in reason {
            let characterBytes = String(character).utf8.count
            guard characterBytes <= 4096 - byteCount else { break }

            boundedReason.append(character)
            byteCount += characterBytes
        }

        self.reason = boundedReason.isEmpty ? "Failure reason unavailable." : boundedReason
    }
}
