//
//  StandaloneClockProvider.swift
//  StandaloneClock
//

import CascadeAddonSDK
import CascadeContracts
import Foundation

/// StandaloneClockProvider is a finite, source-only example. The host owns assignment and revision history.
public actor StandaloneClockProvider: AddonProvider {
    private let owner: AddonID
    private let assignment: PublicationID
    private let clock: @Sendable () -> Date
    private var revision: UInt64
    private var stopped = false

    public init(
        expectedOwner: AddonID,
        publicationID: PublicationID,
        previousRevision: UInt64? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        try publicationID.validateOwner(expectedOwner)
        owner = expectedOwner
        assignment = publicationID
        revision = previousRevision ?? 0
        self.clock = clock
    }

    public func handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput {
        try event.validate()
        if case .stop = event {
            stopped = true
            return try emptyOutput()
        }
        guard !stopped else {
            throw AddonFailure(code: .sessionRevoked, reason: "Standalone clock stopped")
        }

        switch event {
        case .refresh(let publicationID):
            try validateAssignment(publicationID)
            return try publicationOutput()
        case .action(let request):
            let failure: AddonFailure
            do {
                try validateAssignment(request.publicationID)
                failure = AddonFailure(code: .invalidPayload, reason: "Standalone clock exposes no actions")
            } catch let value as AddonFailure {
                failure = value
            }
            let output = try ProviderOutput(
                schemaVersion: 1,
                publications: [],
                operations: [],
                completion: .action(requestID: request.requestID, outcome: .rejected(reason: failure)),
                checkpoint: nil
            )
            try output.validateContext(
                authenticatedAddonID: owner,
                expectedCompletion: .action(requestID: request.requestID),
                previousRevisions: [:]
            )
            return output
        case .scheduled:
            return try emptyOutput()
        case .serviceChanged, .serviceRequest:
            throw AddonFailure(code: .missingRequirement, reason: "Standalone clock has no services")
        case .stop:
            return try emptyOutput()
        }
    }

    private func validateAssignment(_ publicationID: PublicationID) throws {
        try publicationID.validateOwner(owner)
        guard publicationID == assignment else {
            throw AddonFailure(code: .invalidPayload, reason: "Clock assignment mismatch")
        }
    }

    private func publicationOutput() throws -> ProviderOutput {
        guard revision < UInt64.max else {
            throw AddonFailure(code: .resourceDenied, reason: "Clock publication revision exhausted")
        }
        let now = clock()
        guard now.timeIntervalSince1970.isFinite else {
            throw AddonFailure(code: .invalidPayload, reason: "Nonfinite clock time")
        }
        let expiresAt = now.addingTimeInterval(24 * 60 * 60)
        guard expiresAt.timeIntervalSince1970.isFinite, expiresAt > now else {
            throw AddonFailure(code: .invalidPayload, reason: "Invalid clock publication expiry")
        }
        let document = try ContentDocument(
            root: .clock(format: .hourMinute),
            privacy: .publicContent,
            accessibilityLabel: "Current time"
        )
        let content = try PresentationSet(
            widget: document,
            compactLeading: nil,
            compactTrailing: nil,
            minimal: nil,
            expanded: nil
        )
        let publication = try Publication(
            id: assignment,
            revision: revision + 1,
            kind: .widget,
            content: content,
            timeline: nil,
            expiresAt: expiresAt,
            stalePolicy: .remove
        )
        let output = try ProviderOutput(
            schemaVersion: 1,
            publications: [publication],
            operations: [],
            completion: nil,
            checkpoint: nil
        )
        try output.validateContext(
            authenticatedAddonID: owner,
            expectedCompletion: nil,
            previousRevisions: revision == 0 ? [:] : [assignment: revision]
        )
        revision += 1
        return output
    }

    private func emptyOutput() throws -> ProviderOutput {
        try ProviderOutput(
            schemaVersion: 1,
            publications: [],
            operations: [],
            completion: nil,
            checkpoint: nil
        )
    }
}
