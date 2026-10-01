//
//  SemanticVersion.swift
//  CascadeKit
//

import Foundation

public struct SemanticVersion: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {

    public let major: Int
    public let minor: Int
    public let patch: Int

    public let prerelease   : String?
    public let buildMetadata: String?

    public init(
        _ major      : Int,
        _ minor      : Int,
        _ patch      : Int,
        prerelease   : String? = nil,
        buildMetadata: String? = nil
    ) {
        self.major         = major
        self.minor         = minor
        self.patch         = patch
        self.prerelease    = prerelease
        self.buildMetadata = buildMetadata
    }

    public init?(_ text: String) {
        let parts = text.split(
            separator                : "+",
            maxSplits                : 1,
            omittingEmptySubsequences: false
        )
        guard parts.count <= 2, !parts.contains(where: \.isEmpty) else { return nil }

        let release = parts[0].split(
            separator                : "-",
            maxSplits                : 1,
            omittingEmptySubsequences: false
        )
        guard !release.contains(where: \.isEmpty) else { return nil }

        let core = release[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              core.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0 == "0" || !$0.hasPrefix("0")) }),
              let major = Int(core[0]),
              let minor = Int(core[1]),
              let patch = Int(core[2])
        else { return nil }

        let prerelease = release.count == 2 ? String(release[1]) : nil
        let build      = parts.count == 2 ? String(parts[1]) : nil

        func valid(
            _ value    : String,
            numericRule: Bool
        ) -> Bool {
            !value.isEmpty
                && value.utf8.allSatisfy {
                    (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
                }
                && (!numericRule || !value.allSatisfy(\.isNumber) || value == "0" || !value.hasPrefix("0"))
        }

        guard prerelease?.split(separator: ".", omittingEmptySubsequences: false)
                  .allSatisfy({ valid(String($0), numericRule: true) }) ?? true,
              build?.split(separator: ".", omittingEmptySubsequences: false)
                  .allSatisfy({ valid(String($0), numericRule: false) }) ?? true
        else { return nil }

        self.init(
            major,
            minor,
            patch,
            prerelease   : prerelease,
            buildMetadata: build
        )
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
            + (prerelease.map { "-\($0)" } ?? "")
            + (buildMetadata.map { "+\($0)" } ?? "")
    }

    public static func < (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        let lhsCore = (lhs.major, lhs.minor, lhs.patch)
        let rhsCore = (rhs.major, rhs.minor, rhs.patch)
        if lhsCore != rhsCore { return lhsCore < rhsCore }

        switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true

            case let (lhsPrerelease?, rhsPrerelease?):
                let lhsParts = lhsPrerelease.split(separator: ".")
                let rhsParts = rhsPrerelease.split(separator: ".")
                for index in 0..<min(lhsParts.count, rhsParts.count) where lhsParts[index] != rhsParts[index] {
                    let lhsNumeric = lhsParts[index].allSatisfy(\.isNumber)
                    let rhsNumeric = rhsParts[index].allSatisfy(\.isNumber)
                    if lhsNumeric && rhsNumeric {
                        return lhsParts[index].count == rhsParts[index].count
                            ? lhsParts[index] < rhsParts[index]
                            : lhsParts[index].count < rhsParts[index].count
                    }
                    if lhsNumeric { return true }
                    if rhsNumeric { return false }
                    return lhsParts[index] < rhsParts[index]
                }
                return lhsParts.count < rhsParts.count
        }
    }

    public static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.major == rhs.major
            && lhs.minor == rhs.minor
            && lhs.patch == rhs.patch
            && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }
}
