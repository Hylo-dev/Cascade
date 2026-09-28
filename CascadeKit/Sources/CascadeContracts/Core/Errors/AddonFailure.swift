//
//  AddonFailure.swift
//  CascadeKit
//

import Foundation

/// AddonFailure carries a machine-readable failure and a bounded remedy for people.
public struct AddonFailure: Error, Codable, Equatable, Sendable {
    public enum Code: String, Codable, Sendable {
        case missingRequirement, versionConflict, permissionDenied, dependencyUnavailable
        case resolutionTooComplex, resourceDenied, rateLimited, deadlineExceeded
        case sessionRevoked, invalidPayload, outcomeUnknown
    }
    public let code: Code
    public let reason: String
    /// AddonFailure preserves complete graphemes within the wire's UTF-8 byte budget.
    /// Empty input, or an initial grapheme larger than the budget, receives a readable fallback.
    public init(code: Code, reason: String) {
        self.code = code
        var boundedReason = ""
        var byteCount = 0
        for character in reason {
            let characterBytes = String(character).utf8.count
            guard characterBytes <= 4096 - byteCount else { break }
            boundedReason.append(character)
            byteCount += characterBytes
        }
        self.reason = boundedReason.isEmpty ? "Failure reason unavailable." : boundedReason
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        code = try values.decode(Code.self, forKey: .code)
        reason = try values.decode(String.self, forKey: .reason)
        try validate()
    }
    /// validate applies the same invariant at decoding and nested envelope admission.
    public func validate() throws {
        try ContractValidation.require(!reason.isEmpty && reason.utf8.count <= 4096, "Invalid failure reason")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case code, reason }
}
