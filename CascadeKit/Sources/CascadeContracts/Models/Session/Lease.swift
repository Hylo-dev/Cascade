//
//  Lease.swift
//  CascadeKit
//

import Foundation

/// Lease is a validated value in the version 1 addon protocol.
public struct Lease: Codable, Equatable, Sendable {

    public let id                          : UUID
    public let grant                       : Grant
    public let monotonicDeadlineNanoseconds: UInt64

    public init(
        id                          : UUID,
        grant                       : Grant,
        monotonicDeadlineNanoseconds: UInt64
    ) throws {
        self.id                           = id
        self.grant                        = grant
        self.monotonicDeadlineNanoseconds = monotonicDeadlineNanoseconds

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container                = try decoder.container(keyedBy: CodingKeys.self)
        id                           = try container.decode(UUID.self, forKey: .id)
        grant                        = try container.decode(Grant.self, forKey: .grant)
        monotonicDeadlineNanoseconds = try container.decode(
            UInt64.self,
            forKey: .monotonicDeadlineNanoseconds
        )

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            monotonicDeadlineNanoseconds > 0,
            "Lease requires a monotonic deadline"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case grant
        case monotonicDeadlineNanoseconds
    }
}
