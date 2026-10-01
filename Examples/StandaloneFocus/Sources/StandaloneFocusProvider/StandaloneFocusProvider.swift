//
//  StandaloneFocusProvider.swift
//  StandaloneFocus
//

import CascadeAddonSDK
import CascadeContracts
import Foundation

/// StandaloneFocusProvider owns one assigned timer, one bounded record, and one
/// host-serialized writer.
/// Storage commit and output admission are separate; this API provides no CAS.
public actor StandaloneFocusProvider: AddonProvider {

    public static let storageKey = "standalone-focus.state.v1"

    private let owner     : AddonID
    private let assignment: PublicationID
    private let mode      : FocusInitializationMode
    private let duration  : TimeInterval
    private let clock     : @Sendable () -> Date

    private var busy           = false
    private var stopped        = false
    private var mayHaveWritten = false

    public init(
        expectedOwner: AddonID,
        publicationID: PublicationID,
        mode         : FocusInitializationMode,
        duration     : TimeInterval = 25 * 60,
        clock        : @escaping @Sendable () -> Date = { Date() }
    ) throws {
        try publicationID.validateOwner(expectedOwner)
        _ = try FocusSession(duration: duration)

        owner         = expectedOwner
        assignment    = publicationID
        self.mode     = mode
        self.duration = duration
        self.clock    = clock
    }

    public func handle(
        _ event: AddonEvent,
        context: AddonContext
    ) async throws -> ProviderOutput {
        guard !busy else { throw FocusError.busy }

        busy = true
        defer { busy = false }

        if case .stop = event {
            stopped = true
            return try FocusPresentation.empty()
        }
        guard !stopped else { throw FocusError.stopped }

        try Task.checkCancellation()

        let request: ActionRequest?
        if case .action(let value) = event { request = value } else { request = nil }

        var now = clock()
        guard now.timeIntervalSince1970.isFinite else { throw FocusError.invalidConfiguration }

        // These refusals precede any storage handoff or lifecycle reconciliation.
        do {
            try event.validate()

            switch event {
                case .refresh(let id): try validateAssignment(id)

                case .action(let action):
                    try validateAssignment(action.publicationID)
                    guard FocusCommand(rawValue: action.actionID) != nil,
                          action.input.isEmpty
                    else {
                        throw AddonFailure(
                            code  : .invalidPayload,
                            reason: "Unsupported focus action or input"
                        )
                    }

                case .scheduled: break

                case .serviceChanged, .serviceRequest:
                    throw AddonFailure(
                        code  : .missingRequirement,
                        reason: "Standalone focus has no services"
                    )

                case .stop: break
            }
        } catch {
            if let request { return try rejection(request, error: error) }
            throw error
        }

        // A failed read cannot establish whether a valid action already committed,
        // including after recreation with no in-memory history. Never infer rejection.
        let data: Data?
        do {
            data = try await context.storage.read(key: Self.storageKey)
        } catch {
            if let request {
                return try FocusPresentation.empty(
                    completion: .action(requestID: request.requestID, outcome: .outcomeUnknown)
                )
            }
            throw error
        }

        var record: FocusRecord
        do {
            try Task.checkCancellation()

            if let data {
                record = try FocusStateCodec.decode(data)
                guard record.assignment == assignment else { throw FocusError.assignmentMismatch }
                guard mode == .resumeExisting || mayHaveWritten
                else { throw FocusError.assignmentMismatch }
                guard record.session.duration == duration
                else { throw FocusError.invalidConfiguration }
            } else {
                guard mode == .freshAssignment && !mayHaveWritten
                else { throw FocusError.missingState }

                record = try FocusRecord(assignment: assignment, duration: duration)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Readable bytes are not necessarily usable action history. Without a
            // validated ledger for this assignment/configuration, neither receipt
            // absence nor its revision fence proves that the original action failed.
            if let request {
                return try FocusPresentation.empty(
                    completion: .action(requestID: request.requestID, outcome: .outcomeUnknown)
                )
            }
            throw error
        }

        // The storage await may span sleep or a civil-clock jump.
        now = clock()
        guard now.timeIntervalSince1970.isFinite else { throw FocusError.invalidConfiguration }

        if case .scheduled(let token) = event {
            guard token == record.activeToken,
                  let deadline = record.session.deadline,
                  deadline <= now
            else { return try FocusPresentation.empty() }
        }

        // Duplicate fingerprint matching precedes observed-revision fencing.
        var actionOutcome   : ActionOutcome?
        var recoveredOutcome: ActionOutcome?
        var newReceipt       = false

        if let request {
            if let receipt = record.receipts.first(where: { $0.request.requestID == request.requestID }) {
                guard receipt.request == request else {
                    return try rejection(
                        request,
                        error: AddonFailure(
                            code  : .invalidPayload,
                            reason: "Request ID reused with different request"
                        )
                    )
                }

                actionOutcome    = receipt.outcome
                recoveredOutcome = receipt.outcome
            } else {
                // Deadlines fence fresh commands, never hide a known committed receipt.
                guard request.deadline > now else {
                    return try rejection(
                        request,
                        error: AddonFailure(
                            code  : .deadlineExceeded,
                            reason: "Action deadline elapsed"
                        )
                    )
                }
                guard request.observedRevision > 0,
                      request.observedRevision == record.revision
                else {
                    return try rejection(
                        request,
                        error: AddonFailure(
                            code  : .invalidPayload,
                            reason: "Observed revision is stale or unknown"
                        )
                    )
                }

                newReceipt = true
            }
        }

        let previousSession = record.session
        try record.session.reconcile(now: now)

        if let request, newReceipt, let command = FocusCommand(rawValue: request.actionID) {
            do {
                try record.session.apply(command, now: now)
                actionOutcome = .completed(payload: Data())
            } catch let failure as AddonFailure {
                actionOutcome = .rejected(reason: failure)
            }
        }

        // Persist one active logical token; no physical scheduler cancellation is claimed.
        let schedule = record.session.phase == .running && record.session != previousSession
        if schedule {
            record.activeToken = "focus.expiry." + UUID().uuidString
        } else if record.session.phase != .running {
            record.activeToken = nil
        }

        try record.reserveRevision()

        if let request, newReceipt, let actionOutcome {
            record.receipts.append(FocusReceipt(
                request : request,
                outcome : actionOutcome,
                revision: record.revision
            ))
            if record.receipts.count > 16 { record.receipts.removeFirst(record.receipts.count - 16) }
        }

        let completion = request.flatMap { actionRequest in
            actionOutcome.map { InvocationCompletion.action(requestID: actionRequest.requestID, outcome: $0) }
        }

        // Validate candidate publication/completion and bounded bytes before handing off storage.
        let output = try FocusPresentation.output(
            record    : record,
            now       : now,
            completion: completion,
            schedule  : schedule
        )
        try output.validateContext(
            authenticatedAddonID: owner,
            expectedCompletion  : request.map { .action(requestID: $0.requestID) },
            previousRevisions   : [assignment: record.revision - 1]
        )

        let bytes = try FocusStateCodec.encode(record)
        try Task.checkCancellation()

        // Recheck civil deadline after the read await, immediately before write handoff.
        if let request, newReceipt, request.deadline <= clock() {
            return try rejection(
                request,
                error: AddonFailure(
                    code  : .deadlineExceeded,
                    reason: "Action deadline elapsed before commit"
                )
            )
        }

        mayHaveWritten = true
        do {
            try await context.storage.write(bytes, key: Self.storageKey)
        } catch {
            // The snapshot may or may not have committed; discard it and reread next time.
            // An exact receipt recovered from authority still proves the original command's
            // outcome. Snapshot uncertainty (even cancellation) cannot erase that knowledge.
            if let request {
                return try FocusPresentation.empty(
                    completion: .action(
                        requestID: request.requestID,
                        outcome  : recoveredOutcome ?? .outcomeUnknown
                    )
                )
            }
            throw AddonFailure(
                code  : .outcomeUnknown,
                reason: "Storage commit uncertain; next invocation must reread state"
            )
        }

        // Known successful commit stays committed even if the task was cancelled during write.
        return output
    }

    private func validateAssignment(_ id: PublicationID) throws {
        try id.validateOwner(owner)
        guard id == assignment else { throw FocusError.assignmentMismatch }
    }

    private func rejection(
        _ request: ActionRequest,
        error    : any Error
    ) throws -> ProviderOutput {
        let failure = (error as? AddonFailure) ?? AddonFailure(
            code  : .invalidPayload,
            reason: "Focus state unavailable: \(error)"
        )

        return try FocusPresentation.empty(
            completion: .action(requestID: request.requestID, outcome: .rejected(reason: failure))
        )
    }
}
