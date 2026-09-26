import Foundation

public struct SemanticVersion: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let major: Int; public let minor: Int; public let patch: Int
    public let prerelease: String?; public let buildMetadata: String?
    public init(_ major: Int, _ minor: Int, _ patch: Int, prerelease: String? = nil, buildMetadata: String? = nil) { self.major = major; self.minor = minor; self.patch = patch; self.prerelease = prerelease; self.buildMetadata = buildMetadata }
    public init?(_ text: String) {
        let parts = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts.contains(where: \.isEmpty) else { return nil }
        let release = parts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard !release.contains(where: \.isEmpty) else { return nil }
        let core = release[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3, core.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && ($0 == "0" || !$0.hasPrefix("0")) }), let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]) else { return nil }
        let prerelease = release.count == 2 ? String(release[1]) : nil, build = parts.count == 2 ? String(parts[1]) : nil
        func valid(_ value: String, numericRule: Bool) -> Bool { !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } && (!numericRule || !value.allSatisfy(\.isNumber) || value == "0" || !value.hasPrefix("0")) }
        guard prerelease?.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ valid(String($0), numericRule: true) }) ?? true, build?.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ valid(String($0), numericRule: false) }) ?? true else { return nil }
        self.init(major, minor, patch, prerelease: prerelease, buildMetadata: build)
    }
    public var description: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") + (buildMetadata.map { "+\($0)" } ?? "") }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let l = (lhs.major, lhs.minor, lhs.patch), r = (rhs.major, rhs.minor, rhs.patch); if l != r { return l < r }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false; case (nil, _): return false; case (_, nil): return true
        case let (a?, b?):
            let x = a.split(separator: "."), y = b.split(separator: ".")
            for i in 0..<min(x.count, y.count) where x[i] != y[i] { let xn = x[i].allSatisfy(\.isNumber), yn = y[i].allSatisfy(\.isNumber); if xn && yn { return x[i].count == y[i].count ? x[i] < y[i] : x[i].count < y[i].count }; if xn { return true }; if yn { return false }; return x[i] < y[i] }
            return x.count < y.count
        }
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease }
    public func hash(into hasher: inout Hasher) { hasher.combine(major); hasher.combine(minor); hasher.combine(patch); hasher.combine(prerelease) }
}

public struct SemanticVersionRange: Hashable, Sendable {
    private let predicates: [Predicate]
    public init?(_ text: String) {
        var parsed: [Predicate] = []; let tokens = text.split(separator: " ").map(String.init); guard !tokens.isEmpty else { return nil }
        for token in tokens { let op = [">=", "<=", ">", "<", "="].first(where: { token.hasPrefix($0) }) ?? "="; let raw = op == "=" && !token.hasPrefix("=") ? token : String(token.dropFirst(op.count)); guard let version = SemanticVersion(raw) else { return nil }; parsed.append(.init(operation: op, version: version)) }
        predicates = parsed
    }
    public func contains(_ version: SemanticVersion) -> Bool { (version.prerelease == nil || predicates.contains { $0.version.prerelease != nil }) && predicates.allSatisfy { $0.matches(version) } }
    private struct Predicate: Hashable, Sendable { let operation: String; let version: SemanticVersion; func matches(_ value: SemanticVersion) -> Bool { switch operation { case ">=": value >= version; case "<=": value <= version; case ">": value > version; case "<": value < version; default: value == version } } }
}
