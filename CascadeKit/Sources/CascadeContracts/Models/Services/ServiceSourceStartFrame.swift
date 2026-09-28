//
//  ServiceSourceStartFrame.swift
//  CascadeKit
//

import Foundation

/// ServiceSourceStartFrame carries host-issued descriptor claims, not
/// consumer-selected authority. UUID correlation does not authenticate a provider
/// incarnation or establish source readiness.
public struct ServiceSourceStartFrame: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sourceID: UUID
    public let startNonce: UUID
    public let providerID: AddonID
    public let publisher: String
    public let digest: String
    public let contractVersion: String
    public let serviceID: String
    public let partition: String
    public let scope: ServiceScope

    public init(schemaVersion: Int = 1, sourceID: UUID, startNonce: UUID, providerID: AddonID,
                publisher: String, digest: String, contractVersion: String, serviceID: String,
                partition: String, scope: ServiceScope) throws {
        self.schemaVersion = schemaVersion
        self.sourceID = sourceID
        self.startNonce = startNonce
        self.providerID = providerID
        self.publisher = publisher
        self.digest = digest
        self.contractVersion = contractVersion
        self.serviceID = serviceID
        self.partition = partition
        self.scope = scope
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported source start schema")
        try ContractValidation.require(ContractValidation.identifier(serviceID) && ContractValidation.semver(contractVersion), "Invalid source service/version")
        try ContractValidation.require(!publisher.isEmpty && publisher.utf8.count <= 256, "Invalid source publisher")
        try ContractValidation.require(!digest.isEmpty && digest.utf8.count <= 512, "Invalid source digest")
        try ContractValidation.require(!partition.isEmpty && partition.utf8.count <= 256, "Invalid source partition")
        try scope.validate()
    }

    public init(from decoder: any Decoder) throws {
        try SubscriptionWireValidation.fields(decoder, exactly: ["schemaVersion", "kind", "sourceID", "startNonce", "providerID", "publisher", "digest", "contractVersion", "serviceID", "partition", "scope"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try ContractValidation.require(try values.decode(String.self, forKey: .kind) == "sourceStart", "Unknown source start kind")
        try self.init(schemaVersion: values.decode(Int.self, forKey: .schemaVersion),
                      sourceID: values.decode(UUID.self, forKey: .sourceID), startNonce: values.decode(UUID.self, forKey: .startNonce),
                      providerID: values.decode(AddonID.self, forKey: .providerID), publisher: values.decode(String.self, forKey: .publisher),
                      digest: values.decode(String.self, forKey: .digest), contractVersion: values.decode(String.self, forKey: .contractVersion),
                      serviceID: values.decode(String.self, forKey: .serviceID), partition: values.decode(String.self, forKey: .partition),
                      scope: values.decode(ServiceScope.self, forKey: .scope))
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode("sourceStart", forKey: .kind)
        try values.encode(sourceID, forKey: .sourceID)
        try values.encode(startNonce, forKey: .startNonce)
        try values.encode(providerID, forKey: .providerID)
        try values.encode(publisher, forKey: .publisher)
        try values.encode(digest, forKey: .digest)
        try values.encode(contractVersion, forKey: .contractVersion)
        try values.encode(serviceID, forKey: .serviceID)
        try values.encode(partition, forKey: .partition)
        try values.encode(scope, forKey: .scope)
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, kind, sourceID, startNonce, providerID, publisher, digest, contractVersion, serviceID, partition, scope }
}
