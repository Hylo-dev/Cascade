//
//  SourceApplication.swift
//  CascadeKit
//

import Foundation

/// SourceApplication is a validated value in the version 1 addon protocol.
public struct SourceApplication: Codable, Equatable, Sendable {

    public let bundleID: AddonID
    public let required: Bool

    public init(
        bundleID: AddonID,
        required: Bool
    ) throws {
        self.bundleID = bundleID
        self.required = required

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID      = try container.decode(AddonID.self, forKey: .bundleID)
        required      = try container.decode(Bool.self, forKey: .required)

        try validate()
    }

    public func validate() throws {}

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case bundleID
        case required
    }
}
