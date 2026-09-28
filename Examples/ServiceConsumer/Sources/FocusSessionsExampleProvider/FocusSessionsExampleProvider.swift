import Foundation
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract

/// Fixed synthetic count 3; this provider does not read real Focus history.
public actor FocusSessionsExampleProvider: AddonProvider {
    private let clock: @Sendable () -> Date
    private var stopped = false

    public init(clock: @escaping @Sendable () -> Date = { Date() }) { self.clock = clock }

    public func handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput {
        try event.validate()
        if case .stop = event {
            stopped = true
            return try ProviderOutput(schemaVersion: 1, publications: [], operations: [], completion: nil, checkpoint: nil)
        }
        try Task.checkCancellation()
        guard !stopped else { throw AddonFailure(code: .sessionRevoked, reason: "Example provider stopped") }
        guard case .serviceRequest(let request) = event,
              request.contractID == FocusSessionsContract.serviceID,
              request.operation == FocusSessionsContract.operation, request.payload.isEmpty
        else { throw AddonFailure(code: .invalidPayload, reason: "Unsupported example service request") }
        let now = clock()
        guard now.timeIntervalSince1970.isFinite, request.deadline > now else {
            throw AddonFailure(code: .deadlineExceeded, reason: "Example request deadline expired")
        }
        return try ProviderOutput(schemaVersion: 1, publications: [], operations: [],
                                  completion: .service(requestID: request.requestID, response: FocusSessionsContract.syntheticResponse()), checkpoint: nil)
    }
}
