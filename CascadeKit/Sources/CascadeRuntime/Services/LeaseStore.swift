import CascadeContracts
import Foundation

struct LeaseStore {
    struct Entry {
        let lease: Lease
        let session: ServiceSession
        let permissionID: UUID
        let interestID: UUID
        let deadline: Duration
        let reservation: ResourceReservation
    }
    struct RequestKey: Hashable {
        let consumer: VerifiedAddonIdentity
        let requestID: UUID
    }
    struct RequestRecord {
        let invocation: ServiceInvocation
        let requirementID: String
        let source: ServiceRegistry.SourceKey
        let workID: UUID
        let retainUntil: Duration
        let reservation: ResourceReservation
        var outcome: ServiceRequestOutcome
        var needsResultReduction = false
    }
    struct Operation {
        let id: UUID
        let grantID: UUID
        let requestKey: RequestKey
        let contractID: String
        let operation: String
        var consumed = false
        let deadline: Duration
    }
    var requests: [RequestKey: RequestRecord] = [:]
    var grants: [UUID: Entry] = [:]
    var operations: [UUID: Operation] = [:]
}
