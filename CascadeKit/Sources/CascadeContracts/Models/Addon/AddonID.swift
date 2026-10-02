//
//  AddonID.swift
//  CascadeKit
//

import Foundation

/// AddonID names a resource owner in reverse-DNS form. The name outlived the addon platform:
/// the resource governor keys its ledgers by it, and the file shelf is today its only owner.
public struct AddonID: RawRepresentable, Hashable, Sendable {

    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count <= 255,
              rawValue.range(of: "^[a-zA-Z][a-zA-Z0-9-]*(\\.[a-zA-Z][a-zA-Z0-9-]*)+$", options: .regularExpression) != nil
        else { return nil }

        self.rawValue = rawValue
    }
}
