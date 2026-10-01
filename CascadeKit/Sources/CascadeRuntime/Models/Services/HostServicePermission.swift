//
//  HostServicePermission.swift
//  CascadeKit
//

import CascadeContracts

/// HostServicePermission is trusted host authority input. This is not a wire permission or process
/// authentication.
public struct HostServicePermission: Sendable {

    public let consumer             : VerifiedAddonIdentity
    public let binding              : ServiceBinding
    public let serviceID            : String
    public let partition            : String
    public let operation            : String
    public let crossPublisherConsent: Bool

    public init(
        consumer             : VerifiedAddonIdentity,
        binding              : ServiceBinding,
        serviceID            : String,
        partition            : String,
        operation            : String,
        crossPublisherConsent: Bool
    ) {
        self.consumer              = consumer
        self.binding               = binding
        self.serviceID             = serviceID
        self.partition             = partition
        self.operation             = operation
        self.crossPublisherConsent = crossPublisherConsent
    }

    func validate() throws {
        try ServiceRegistry.validateIdentity(consumer)
        try ServiceRegistry.validateIdentity(binding.providerIdentity)

        guard binding.consumer == consumer.addonID,
              binding.provider == binding.providerIdentity.addonID,
              let feature = binding.featureID,
              [feature, binding.requirementID, serviceID, operation].allSatisfy(ServiceRegistry.identifier),
              !partition.isEmpty,
              partition.utf8.count <= 256,
              !binding.digest.isEmpty,
              binding.digest.utf8.count <= 512,
              binding.contractVersion.description.utf8.count <= 128,
              let canonical = SemanticVersion(binding.contractVersion.description),
              canonical.description == binding.contractVersion.description
        else {
            throw ServiceBroker.failure(.invalidPayload)
        }

        guard consumer.publisher == binding.providerIdentity.publisher || crossPublisherConsent else {
            throw ServiceBroker.failure(.permissionDenied)
        }
    }
}
