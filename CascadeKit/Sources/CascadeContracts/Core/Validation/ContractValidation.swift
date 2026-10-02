//
//  ContractValidation.swift
//  CascadeKit
//

import Foundation

/// ContractValidation centralizes deterministic wire bounds, without UI or runtime dependencies.
enum ContractValidation {

    static func require(
        _ condition: Bool,
        _ reason   : String
    ) throws {
        guard condition else { throw AddonFailure(code: .invalidPayload, reason: reason) }
    }

    static func identifier(_ value: String) -> Bool {
        value.utf8.count <= 128
            && value.range(of: "^[A-Za-z][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }

    static func semver(_ value: String) -> Bool {
        value.utf8.count <= 128
            && value.range(
                of     : "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?(\\+[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$",
                options: .regularExpression
            ) != nil
            && !(value.split(separator: "+")[0]
                .split(separator: "-", maxSplits: 1)
                .dropFirst()
                .first?
                .split(separator: ".")
                .contains(where: { $0.allSatisfy(\.isNumber) && $0.count > 1 && $0.first == "0" }) ?? false)
    }

    static func range(_ value: String) -> Bool {
        let parts = value.split(separator: " ", omittingEmptySubsequences: false)

        return !parts.isEmpty && parts.count <= 8
            && parts.allSatisfy { part in
                var version = String(part)
                if version.hasPrefix(">=") || version.hasPrefix("<=") {
                    version.removeFirst(2)
                } else if version.hasPrefix(">") || version.hasPrefix("<") || version.hasPrefix("=") {
                    version.removeFirst()
                }

                return semver(version)
            }
    }

    static func unique(
        _ values: [String],
        _ reason: String
    ) throws {
        try require(values.count <= 64 && Set(values).count == values.count, reason)
    }

    static func bytes<T: Encodable>(
        _ value: T,
        maximum: Int
    ) throws {
        try require(
            try JSONEncoder().encode(value).count <= maximum,
            "Encoded value exceeds byte limit"
        )
    }

    static func finite(_ date: Date) throws {
        try require(date.timeIntervalSince1970.isFinite, "Date must be finite")
    }

    /// knownFields rejects any wire field the type does not declare, so a misspelt manifest
    /// key fails instead of being ignored.
    static func knownFields<Keys: CodingKey & CaseIterable>(
        in decoder: any Decoder,
        _ keys    : Keys.Type
    ) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(keys.allCases.map(\.stringValue))),
            "Unknown wire field"
        )
    }
}
