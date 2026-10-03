//
//  AddonOptionsRequest.swift
//  CascadeKit
//

import Foundation

/// AddonOptionsRequest describes detail content in response to an accepted action.
/// The identifiers are correlations, never display, feature or navigation authority.
public struct AddonOptionsRequest: Codable, Equatable, Sendable {

    public static let capability = "notch.options.v1"
    public let publicationID   : PublicationID
    public let observedRevision: UInt64
    public let actionRequestID : UUID
    public let leaseID         : UUID
    public let document        : ContentDocument

    public init(
        publicationID   : PublicationID,
        observedRevision: UInt64,
        actionRequestID : UUID,
        leaseID         : UUID,
        document        : ContentDocument
    ) throws {
        self.publicationID    = publicationID
        self.observedRevision = observedRevision
        self.actionRequestID  = actionRequestID
        self.leaseID          = leaseID
        self.document         = document
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)),
            "Invalid options fields"
        )
        let container    = try decoder.container(keyedBy: CodingKeys.self)
        publicationID    = try container.decode(PublicationID.self, forKey: .publicationID)
        observedRevision = try container.decode(UInt64.self, forKey: .observedRevision)
        actionRequestID  = try container.decode(UUID.self, forKey: .actionRequestID)
        leaseID          = try container.decode(UUID.self, forKey: .leaseID)
        document         = try container.decode(ContentDocument.self, forKey: .document)
        try validate()
    }

    /// validate applies the existing document bounds before runtime retention.
    public func validate() throws { try document.validate() }

    public static func decode(_ data: Data) throws -> Self {
        try ContractValidation.require(
            data.count <= 69_632,
            "Options request exceeds its bounded envelope"
        )
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case publicationID, observedRevision, actionRequestID, leaseID, document
    }
}
