//
//  ActionRequest.swift
//  CascadeKit
//

import Foundation

/// ActionRequest is a validated value in the version 1 addon protocol.
public struct ActionRequest: Codable, Equatable, Sendable {

    public let schemaVersion   : Int
    public let requestID       : UUID
    public let publicationID   : PublicationID
    public let actionID        : String
    public let input           : Data
    public let deadline        : Date
    public let observedRevision: UInt64

    public init(
        schemaVersion   : Int,
        requestID       : UUID,
        publicationID   : PublicationID,
        actionID        : String,
        input           : Data,
        deadline        : Date,
        observedRevision: UInt64
    ) throws {
        self.schemaVersion    = schemaVersion
        self.requestID        = requestID
        self.publicationID    = publicationID
        self.actionID         = actionID
        self.input            = input
        self.deadline         = deadline
        self.observedRevision = observedRevision

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container    = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion    = try container.decode(Int.self, forKey: .schemaVersion)
        requestID        = try container.decode(UUID.self, forKey: .requestID)
        publicationID    = try container.decode(PublicationID.self, forKey: .publicationID)
        actionID         = try container.decode(String.self, forKey: .actionID)
        input            = try container.decode(Data.self, forKey: .input)
        deadline         = try container.decode(Date.self, forKey: .deadline)
        observedRevision = try container.decode(UInt64.self, forKey: .observedRevision)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1 && ContractValidation.identifier(actionID),
            "Invalid action request"
        )
        try ContractValidation.require(input.count <= 4096, "Action input exceeds 4 KiB")
        try ContractValidation.finite(deadline)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case schemaVersion
        case requestID
        case publicationID
        case actionID
        case input
        case deadline
        case observedRevision
    }
}
