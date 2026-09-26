import CascadeContracts
import Foundation

public struct ServiceSession: Hashable, Sendable {
    fileprivate let id: UUID
    init() { id = UUID() }
}

public struct ServiceBrokerLimits: Sendable {
    public let sessions: Int
    public let permissions: Int
    public let interests: Int
    public let sources: Int
    public let grantsPerOwner: Int
    public let operations: Int
    public let requestsPerOwner: Int
    public let requests: Int
    public init(sessions: Int = 32, permissions: Int = 256, interests: Int = 256,
        sources: Int = 128, grantsPerOwner: Int = 64, operations: Int = 128,
        requestsPerOwner: Int = 128, requests: Int = 1_024) {
        self.sessions = max(0, min(sessions, 32))
        self.permissions = max(0, min(permissions, 256))
        self.interests = max(0, min(interests, 256))
        self.sources = max(0, min(sources, 128))
        self.grantsPerOwner = max(0, min(grantsPerOwner, 64))
        self.operations = max(0, min(operations, 128))
        self.requestsPerOwner = max(0, min(requestsPerOwner, 128))
        self.requests = max(0, min(requests, 1_024))
    }
}

struct ServiceRegistry {
    struct Session {
        let identity: VerifiedAddonIdentity
        let generation: ConnectionGeneration
        let reservation: ResourceReservation
    }
    struct SourceKey: Hashable {
        let provider: VerifiedAddonIdentity
        let digest: String
        // SemanticVersion equality omits build metadata; exact selection must retain it.
        let version: String
        let serviceID: String
        let partition: String
        let featureID: String
        let operation: String
        init(_ permission: HostServicePermission) {
            provider = permission.binding.providerIdentity
            digest = permission.binding.digest
            version = permission.binding.contractVersion.description
            serviceID = permission.serviceID
            partition = permission.partition
            featureID = permission.binding.featureID!
            operation = permission.operation
        }
    }
    struct Source {
        let id: UUID
        let key: SourceKey
        let reservation: ResourceReservation
        var startConsumed = false
        var restartRequired = false
    }
    struct Interest {
        let id: UUID
        let permissionID: UUID
        let sourceID: UUID
        let consumer: VerifiedAddonIdentity
        let deadline: Duration
        let reservation: ResourceReservation
    }
    var sessions: [ServiceSession: Session] = [:]
    var sources: [UUID: Source] = [:]
    var interests: [UUID: Interest] = [:]
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
