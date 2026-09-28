//
//  ServiceConsumerProvider.swift
//  ServiceConsumer
//

import Foundation
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract

/// ServiceConsumerProvider serves one host assignment with fresh memory-only revisions. Not
/// reconnect/recovery support.
public actor ServiceConsumerProvider: AddonProvider {
    private let owner: AddonID
    private let assignment: PublicationID
    private let clock: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var busy = false
    private var stopped = false

    public init(owner: AddonID, assignment: PublicationID,
                clock: @escaping @Sendable () -> Date = { Date() }) throws {
        try assignment.validateOwner(owner)
        self.owner = owner
        self.assignment = assignment
        self.clock = clock
    }

    public func handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput {
        try event.validate()
        // Actor reentrancy permits stop during an outstanding invocation.
        if case .stop = event { stopped = true; return try output() }
        guard case .refresh(let supplied) = event else { return try output() }
        try Task.checkCancellation()
        guard !stopped else { throw AddonFailure(code: .sessionRevoked, reason: "Example consumer stopped") }
        guard supplied == assignment else { throw AddonFailure(code: .invalidPayload, reason: "Refresh assignment mismatch") }
        try supplied.validateOwner(owner)
        guard !busy else { throw AddonFailure(code: .rateLimited, reason: "Example refresh already in flight") }
        busy = true
        defer { busy = false }
        let now = try civilNow()
        let scope = try FocusSessionsContract.scope()
        let usable = context.grants.filter {
            $0.owner == owner && $0.serviceID == FocusSessionsContract.serviceID && $0.scope == scope
                && $0.generation == context.generation && $0.expiresAt.timeIntervalSince1970.isFinite && $0.expiresAt > now
        }
        guard usable.count <= 1 else { throw AddonFailure(code: .invalidPayload, reason: "Ambiguous example service grants") }
        guard let grant = usable.first else {
            return try output(operations: [.requestService(requirementID: FocusSessionsContract.serviceID, scope: scope)])
        }
        let deadline = min(now.addingTimeInterval(2), grant.expiresAt)
        guard deadline.timeIntervalSince1970.isFinite, deadline > now else {
            throw AddonFailure(code: .deadlineExceeded, reason: "No positive example invocation interval")
        }
        let invocation = try ServiceInvocation(schemaVersion: 1, requestID: UUID(), contractID: FocusSessionsContract.serviceID,
                                               operation: FocusSessionsContract.operation, payload: Data(), deadline: deadline)
        // The client authenticates, correlates, enforces monotonic deadlines and rechecks canonical authority.
        let response = try await context.services.invoke(invocation, grant: grant)
        try Task.checkCancellation()
        guard !stopped else { throw AddonFailure(code: .sessionRevoked, reason: "Example consumer stopped during invoke") }
        let receivedAt = try civilNow()
        guard receivedAt < invocation.deadline, receivedAt < grant.expiresAt else {
            throw AddonFailure(code: .deadlineExceeded, reason: "Example response arrived after civil deadline")
        }
        try response.validate()
        guard response.contractID == invocation.contractID, response.operation == invocation.operation else {
            throw AddonFailure(code: .invalidPayload, reason: "Example response identity mismatch")
        }
        let count = try FocusSessionsContract.decode(response.payload)
        guard revision < UInt64.max else { throw AddonFailure(code: .resourceDenied, reason: "Fresh assignment revision exhausted") }
        let label = "Example completed sessions: \(count)"
        let document = try ContentDocument(root: .text(label), privacy: .publicContent, accessibilityLabel: label)
        let content = try PresentationSet(widget: document, compactLeading: nil, compactTrailing: nil, minimal: nil, expanded: nil)
        let expiresAt = receivedAt.addingTimeInterval(30)
        guard expiresAt.timeIntervalSince1970.isFinite, expiresAt > receivedAt else {
            throw AddonFailure(code: .invalidPayload, reason: "Invalid example publication expiry")
        }
        let publication = try Publication(id: assignment, revision: revision + 1, kind: .widget, content: content,
                                          timeline: nil, expiresAt: expiresAt, stalePolicy: .remove)
        let result = try output(publications: [publication])
        try Task.checkCancellation()
        revision += 1
        return result
    }

    private func civilNow() throws -> Date {
        let now = clock()
        guard now.timeIntervalSince1970.isFinite else { throw AddonFailure(code: .invalidPayload, reason: "Nonfinite example clock") }
        return now
    }

    private func output(publications: [Publication] = [], operations: [OperationRequest] = []) throws -> ProviderOutput {
        try ProviderOutput(schemaVersion: 1, publications: publications, operations: operations, completion: nil, checkpoint: nil)
    }
}
