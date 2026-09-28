//
//  SemanticVersionRange.swift
//  CascadeKit
//

import Foundation

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
