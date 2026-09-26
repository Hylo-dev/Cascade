//
//  ProviderMessage.swift
//  Cascade
//

import Foundation

/// ProviderOutput is a validated value in the version 1 addon protocol.
public struct ProviderOutput: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let publications: [Publication]
    public let operations: [OperationRequest]
    public let completion: InvocationCompletion?
    public let checkpoint: Data?

    public init(
        schemaVersion: Int,
        publications: [Publication],
        operations: [OperationRequest],
        completion: InvocationCompletion?,
        checkpoint: Data?
    ) throws {
        self.schemaVersion = schemaVersion
        self.publications = publications
        self.operations = operations
        self.completion = completion
        self.checkpoint = checkpoint
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        publications = try container.decode([Publication].self, forKey: .publications)
        operations = try container.decode([OperationRequest].self, forKey: .operations)
        completion = try container.decodeIfPresent(InvocationCompletion.self, forKey: .completion)
        checkpoint = try container.decodeIfPresent(Data.self, forKey: .checkpoint)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported envelope schema")
        try ContractValidation.require(
            publications.count <= 16 && operations.count <= 16,
            "Envelope list exceeds limit"
        )
        try ContractValidation.require(
            Set(publications.map(\.id)).count == publications.count,
            "Duplicate publication identity"
        )
        try ContractValidation.require((checkpoint?.count ?? 0) <= 65_536, "Checkpoint exceeds 64 KiB")
        for operation in operations { try operation.validate() }
        try completion?.validate()
        try ContractValidation.bytes(self, maximum: 524_288)
    }
    public static func decode(_ data: Data) throws -> ProviderOutput {
        try ContractValidation.require(data.count <= 524_288, "Envelope exceeds 512 KiB")
        return try JSONDecoder().decode(Self.self, from: data)
    }
    /// validateContext checks values against host-owned history and negotiated schemas.
    /// The conservative legacy default admits schema 1 only. Every representation,
    /// including future timeline content, is checked; these values never authenticate a peer.
    public func validateContext(
        authenticatedAddonID: AddonID,
        expectedCompletion: CompletionExpectation?,
        previousRevisions: [PublicationID: UInt64],
        contentSchemas: [Int] = [1]
    ) throws {
        try ContractValidation.require(
            !contentSchemas.isEmpty && contentSchemas.count <= 3
                && Set(contentSchemas).count == contentSchemas.count
                && Set(contentSchemas).isSubset(of: [1, 2, 3]),
            "Invalid negotiated content schema policy"
        )
        for publication in publications {
            try publication.id.validateOwner(authenticatedAddonID)
            try publication.validate()
            try publication.validateRevision(after: previousRevisions[publication.id])
            let presentations = [publication.content].compactMap { $0 }
                + (publication.timeline ?? []).map(\.content)
            for presentation in presentations {
                let documents = [
                    presentation.widget, presentation.compactLeading,
                    presentation.compactTrailing, presentation.minimal, presentation.expanded,
                ].compactMap { $0 }
                for document in documents {
                    try ContractValidation.require(
                        contentSchemas.contains(document.schemaVersion),
                        "Content schema was not negotiated for this connection"
                    )
                }
            }
        }
        for operation in operations {
            if case .endPublication(let id) = operation { try id.validateOwner(authenticatedAddonID) }
        }
        if let completion {
            try ContractValidation.require(expectedCompletion != nil, "Unsolicited invocation result")
            try completion.validateCorrelation(expectedCompletion)
        }
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case publications
        case operations
        case completion
        case checkpoint
    }
}
