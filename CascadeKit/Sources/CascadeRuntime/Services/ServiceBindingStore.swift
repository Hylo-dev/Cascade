import CascadeContracts
import Foundation

/// A feature is part of binding identity; no resolver fallback is performed here.
struct ServiceBindingStore {
    struct Key: Hashable {
        let consumer: VerifiedAddonIdentity
        let requirementID: String
        let featureID: String
        let operation: String
    }
    var permissions: [Key: UUID] = [:]

    static func key(_ permission: HostServicePermission) -> Key {
        Key(consumer: permission.consumer, requirementID: permission.binding.requirementID,
            featureID: permission.binding.featureID!, operation: permission.operation)
    }
}
