//
//  ServiceRegistry.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

struct ServiceRegistry {

    struct Session {

        let identity   : VerifiedAddonIdentity
        let generation : ConnectionGeneration
        let reservation: ResourceReservation
    }

    struct SourceKey: Hashable {

        let provider : VerifiedAddonIdentity
        let digest   : String
        // SemanticVersion equality omits build metadata; exact selection must retain it.
        let version  : String
        let serviceID: String
        let partition: String
        let featureID: String
        let operation: String

        init(_ permission: HostServicePermission) {
            provider  = permission.binding.providerIdentity
            digest    = permission.binding.digest
            version   = permission.binding.contractVersion.description
            serviceID = permission.serviceID
            partition = permission.partition
            featureID = permission.binding.featureID!
            operation = permission.operation
        }
    }

    struct Source {

        let id             : UUID
        let key            : SourceKey
        let reservation    : ResourceReservation
        var startConsumed   = false
        var restartRequired = false
    }

    struct Interest {

        let id          : UUID
        let permissionID: UUID
        let sourceID    : UUID
        let consumer    : VerifiedAddonIdentity
        let deadline    : Duration
        let reservation : ResourceReservation
    }

    var sessions    : [ServiceSession: Session] = [:]
    var sources     : [UUID: Source] = [:]
    var interests   : [UUID: Interest] = [:]
    var pendingWakes: Set<VerifiedAddonIdentity> = []

    static func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || $0 == 45 || $0 == 46 || $0 == 95
        }
    }

    static func validateIdentity(_ identity: VerifiedAddonIdentity) throws {
        guard !identity.publisher.isEmpty, identity.publisher.utf8.count <= 256 else {
            throw ServiceBroker.failure(.invalidPayload)
        }
    }
}
