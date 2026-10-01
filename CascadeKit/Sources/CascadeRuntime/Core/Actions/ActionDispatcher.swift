//
//  ActionDispatcher.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ActionDispatcher coordinates values in one future runtime actor; it runs no provider code.
/// The actor must serialize canonical publication/permission changes, final consume,
/// mark-sent and transport handoff. A context or ticket is not process authentication.
public struct ActionDispatcher: Sendable {

    struct AdmissionQuote: Equatable, Sendable {

        let owner        : AddonID
        let requestID    : UUID
        let retainedBytes: Int
    }

    enum Classification: Equatable, Sendable {

        case duplicate(ActionJournal.State)
        case admission(AdmissionQuote)
    }

    struct RecordAccounting: Equatable, Sendable {

        let owner         : AddonID
        let requestID     : UUID
        let journalBytes  : Int
        let schedulerBytes: Int
        let bindingBytes  : Int
        let jobID         : UUID?
        let phase         : AddonScheduler.Phase?
        let isHandedOff   : Bool
    }

    public struct Ticket: Equatable, Sendable {

        public let id     : UUID
        public let request: ActionRequest

        fileprivate init(
            id     : UUID,
            request: ActionRequest
        ) {
            self.id      = id
            self.request = request
        }
    }

    public struct Delivery: Equatable, Sendable {

        public let ticket    : Ticket
        public let generation: ConnectionGeneration

        fileprivate init(
            ticket    : Ticket,
            generation: ConnectionGeneration
        ) {
            self.ticket     = ticket
            self.generation = generation
        }
    }

    private struct Key: Hashable, Sendable {

        let owner    : AddonID
        let requestID: UUID
    }

    private struct Record: Sendable {

        let binding      : ActionAuthorizer.Binding
        let publicationID: PublicationID
        var jobID        : UUID?
        var ticketID     : UUID?
        var generation   : ConnectionGeneration?
        var revoked       = false
    }

    // 16 KiB covers the <=4 KiB publisher, digest/feature/key, dictionary overhead,
    // canonical decision IDs and bounded returned ticket/stop projections. Journal
    // separately reserves the entire 64 KiB result before any possible send.
    private static let bindingCharge   = 16_384
    private static let admissionCharge = 69_632 + 8_192 + bindingCharge

    private let maximumRetainedBytes: Int

    private var journal  : ActionJournal
    private var scheduler: AddonScheduler
    private var records  : [Key: Record] = [:]
    private var stopped   = false

    public init(maximumRetainedBytes: Int = 8 * 1_024 * 1_024) {
        let ceiling = min(8 * 1_024 * 1_024, max(0, maximumRetainedBytes))

        self.maximumRetainedBytes = ceiling
        journal                   = ActionJournal(maximumRetainedBytes: ceiling)
        scheduler                 = AddonScheduler(maximumRetainedBytes: ceiling)
    }

    public var retainedBytes: Int {
        journal.retainedBytes + scheduler.retainedBytes + records.count * Self.bindingCharge
    }

    public var historyCount: Int { journal.count }
    public var jobCount    : Int { scheduler.count }
    public var bindingCount: Int { records.count }
    public var runningCount: Int { scheduler.runningCount }

    func state(
        _ requestID: UUID,
        owner      : AddonID
    ) -> ActionJournal.State? {
        journal.state(requestID, owner: owner)
    }

    public var nextDeadline: Duration? {
        switch (journal.nextDeadline, scheduler.nextDeadline) {
            case (let first?, let second?): min(first, second)
            case (let first?, nil): first
            case (nil, let second?): second
            case (nil, nil): nil
        }
    }

    /// classify validates recovery or quotes a new request without inserting it.
    mutating func classify(
        request   : ActionRequest,
        context   : ActionAuthorizer.Context,
        at instant: RuntimeInstant
    ) throws -> Classification {
        guard !stopped else { throw revokedFailure }

        let binding = try ActionAuthorizer.binding(request, context: context)
        guard instant.monotonic >= .zero, instant.wall.timeIntervalSince1970.isFinite else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The runtime clock is invalid."
            )
        }

        journal.expire(at: instant.monotonic)
        pruneHistory()

        let key = Key(owner: binding.identity.addonID, requestID: request.requestID)
        if let record = records[key] {
            guard record.binding == binding,
                  journal.request(key.requestID, owner: key.owner) == request,
                  let state = journal.state(key.requestID, owner: key.owner)
            else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "The request binding is unavailable or changed."
                )
            }

            return .duplicate(state)
        }

        try ActionAuthorizer.validate(
            request,
            context: context,
            at     : instant.wall
        )

        let quote = AdmissionQuote(
            owner        : key.owner,
            requestID    : key.requestID,
            retainedBytes: Self.admissionCharge + request.input.count
        )
        guard quote.retainedBytes <= maximumRetainedBytes - retainedBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The combined command state budget is exhausted."
            )
        }

        return .admission(quote)
    }

    /// recordAccounting projects canonical component-owned charges for one request.
    func recordAccounting(
        owner    : AddonID,
        requestID: UUID
    ) -> RecordAccounting? {
        let key = Key(owner: owner, requestID: requestID)
        guard let record = records[key] else { return nil }

        let journalBytes = journal.storedCharge(requestID, owner: owner) ?? 0
        let job          = record.jobID.flatMap(scheduler.job)

        return RecordAccounting(
            owner         : owner,
            requestID     : requestID,
            journalBytes  : journalBytes,
            schedulerBytes: job == nil ? 0 : AddonScheduler.recordCharge,
            bindingBytes  : Self.bindingCharge,
            jobID         : record.jobID,
            phase         : job?.phase,
            isHandedOff   : record.generation != nil
        )
    }

    /// hasRecord reports whether retained action authority still references a publication.
    func hasRecord(publicationID: PublicationID) -> Bool {
        records.contains { key, record in
            key.owner == publicationID.addonID && record.publicationID == publicationID
        }
    }

    /// visitRecordAccounting performs a bounded synchronous scan without copying payloads.
    func visitRecordAccounting(_ visit: (RecordAccounting) -> Void) {
        for key in records.keys {
            if let accounting = recordAccounting(owner: key.owner, requestID: key.requestID) {
                visit(accounting)
            }
        }
    }

    /// hasCurrentQueuedDemand reports only exact, unexpired queued command demand; retained
    /// journal rows and already handed-off work never authorize a provider crash retry.
    func hasCurrentQueuedDemand(
        owner     : AddonID,
        at instant: Duration
    ) -> Bool {
        records.contains { key, record in
            guard key.owner == owner,
                  !record.revoked,
                  record.generation == nil,
                  let jobID = record.jobID,
                  let job   = scheduler.job(jobID),
                  job.phase == .queued,
                  job.deadline > instant
            else { return false }

            if case .command = job.work { return true }
            return false
        }
    }

    /// peekReady exposes the current winner without taking the local scheduler slot.
    func peekReady(at instant: Duration) -> AddonScheduler.Job? {
        scheduler.peekReady(at: instant)
    }

    /// takeReady conditionally consumes the winner observed before global job admission.
    mutating func takeReady(
        expectedJobID: UUID,
        at instant   : Duration
    ) -> Ticket? {
        guard !stopped,
              let job = scheduler.takeReady(expectedJobID: expectedJobID, at: instant),
              case .command(let request) = job.work
        else { return nil }

        let key = Key(owner: job.owner, requestID: request.requestID)
        guard var record = records[key], record.jobID == job.id, !record.revoked else {
            scheduler.releaseUnsentReservation(job.id, owner: job.owner)
            return nil
        }

        let ticket      = Ticket(id: UUID(), request: request)
        record.ticketID = ticket.id
        records[key]    = record

        return ticket
    }

    /// submit authenticates new intent, while exact recovery only checks its current
    /// verified owner/artifact/feature. Recovery never queues or extends a deadline.
    public mutating func submit(
        _ request : ActionRequest,
        context   : ActionAuthorizer.Context,
        at instant: RuntimeInstant
    ) throws -> ActionJournal.Admission {
        guard !stopped else { throw revokedFailure }

        let binding = try ActionAuthorizer.binding(request, context: context)
        guard instant.monotonic >= .zero, instant.wall.timeIntervalSince1970.isFinite else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The runtime clock is invalid."
            )
        }

        journal.expire(at: instant.monotonic)
        pruneHistory()

        let key = Key(owner: binding.identity.addonID, requestID: request.requestID)
        if let record = records[key] {
            guard record.binding == binding,
                  journal.request(key.requestID, owner: key.owner) == request,
                  let state = journal.state(key.requestID, owner: key.owner)
            else {
                // An old running job keeps this ID occupied after the history TTL.
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "The request binding is unavailable or changed."
                )
            }

            return .duplicate(state)
        }

        try ActionAuthorizer.validate(
            request,
            context: context,
            at     : instant.wall
        )

        guard Self.admissionCharge + request.input.count <= maximumRetainedBytes - retainedBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The combined command state budget is exhausted."
            )
        }

        _ = try journal.admit(
            request,
            owner: key.owner,
            at   : instant
        )

        do {
            guard let deadline = journal.deadline(key.requestID, owner: key.owner)
            else { throw revokedFailure }

            let jobID = try scheduler.enqueue(
                .command(request),
                owner   : key.owner,
                deadline: deadline,
                at      : instant
            )
            records[key] = Record(
                binding      : binding,
                publicationID: request.publicationID,
                jobID        : jobID
            )
        } catch {
            journal.rollbackAdmission(key.requestID, owner: key.owner)
            throw error
        }

        return .admitted
    }

    /// takeReady reserves capacity for one canonical decision, without sending.
    /// The host must call consume with fresh canonical state immediately before handoff.
    public mutating func takeReady(at instant: Duration) -> Ticket? {
        guard !stopped,
              let job = scheduler.takeReady(at: instant),
              case .command(let request) = job.work
        else { return nil }

        let key = Key(owner: job.owner, requestID: request.requestID)
        guard var record = records[key], record.jobID == job.id, !record.revoked else { return nil }

        let ticket      = Ticket(id: UUID(), request: request)
        record.ticketID = ticket.id
        records[key]    = record

        return ticket
    }

    /// consume checks a one-use canonical ticket and records the irreversible send
    /// before returning work. Failure to hand it off afterward has unknown outcome.
    public mutating func consume(
        _ ticket  : Ticket,
        context   : ActionAuthorizer.Context,
        generation: ConnectionGeneration,
        at instant: RuntimeInstant
    ) throws -> Delivery? {
        let key = Key(
            owner    : ticket.request.publicationID.addonID,
            requestID: ticket.request.requestID
        )

        guard !stopped,
              var record = records[key],
              !record.revoked,
              record.ticketID == ticket.id,
              record.generation == nil,
              journal.request(key.requestID, owner: key.owner) == ticket.request,
              let jobID = record.jobID,
              scheduler.job(jobID)?.phase == .running
        else { return nil }

        do {
            guard record.binding == (try ActionAuthorizer.binding(ticket.request, context: context))
            else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "The command artifact or feature changed."
                )
            }

            try ActionAuthorizer.validate(
                ticket.request,
                context             : context,
                at                  : instant.wall,
                checkRequestDeadline: false
            )
            try journal.markSent(
                key.requestID,
                owner     : key.owner,
                generation: generation,
                at        : instant.monotonic
            )
        } catch {
            rejectReserved(key, jobID: jobID)
            throw error
        }

        record.generation = generation
        records[key]      = record

        return Delivery(ticket: ticket, generation: generation)
    }

    /// acknowledge records receipt without releasing work or treating it as completion.
    public mutating func acknowledge(
        _ delivery: Delivery,
        owner     : AddonID,
        generation: ConnectionGeneration,
        at instant: Duration
    ) -> Bool {
        guard let key = canonical(
                  delivery,
                  owner     : owner,
                  generation: generation
              ),
              records[key]?.revoked == false
        else { return false }

        return journal.acknowledge(
            key.requestID,
            owner     : owner,
            generation: generation,
            at        : instant
        )
    }

    /// rejectNeverHandedOff records a terminal rejection after the synchronous adapter
    /// proves that the exact delivery was never accepted, queued, written or exposed.
    mutating func rejectNeverHandedOff(
        delivery: Delivery,
        failure : AddonFailure
    ) -> Bool {
        guard let key = canonical(
                  delivery,
                  owner     : delivery.ticket.request.publicationID.addonID,
                  generation: delivery.generation
              ),
              let jobID = records[key]?.jobID,
              scheduler.job(jobID)?.phase == .running,
              journal.rejectNeverHandedOff(
                  key.requestID,
                  owner     : key.owner,
                  generation: delivery.generation,
                  failure   : failure
              )
        else { return false }

        scheduler.releaseUnsentReservation(jobID, owner: key.owner)
        records[key]?.jobID   = nil
        records[key]?.revoked = true
        pruneHistory()

        return true
    }

    /// connectionLost invalidates sent decisions while retaining actual running slots.
    public mutating func connectionLost(
        owner     : AddonID,
        generation: ConnectionGeneration
    ) -> [Delivery] {
        let keys = records.keys.filter { $0.owner == owner && records[$0]?.generation == generation }
        for key in keys { records[key]?.revoked = true }

        journal.connectionLost(owner: owner, generation: generation)

        return cancelJobs(keys)
    }

    /// complete accepts only the current canonical delivery and a validated result.
    /// A late result after timeout/revocation never releases admission; observeExit
    /// is the separate host observation that can close such uncertain work.
    public mutating func complete(
        _ delivery: Delivery,
        owner     : AddonID,
        generation: ConnectionGeneration,
        outcome   : ActionOutcome,
        at instant: Duration
    ) throws -> Bool {
        guard let key = canonical(
                  delivery,
                  owner     : owner,
                  generation: generation
              ),
              let record = records[key],
              !record.revoked,
              let jobID = record.jobID
        else { return false }

        guard try journal.complete(
                  key.requestID,
                  owner     : owner,
                  generation: generation,
                  outcome   : outcome,
                  at        : instant
              )
        else { return false }

        try scheduler.finish(jobID, owner: owner)
        records[key]?.jobID = nil
        pruneHistory()

        return true
    }

    /// canComplete checks the same canonical ticket and reserved result slot without mutation.
    func canComplete(
        _ delivery: Delivery,
        owner     : AddonID,
        generation: ConnectionGeneration,
        outcome   : ActionOutcome,
        at instant: Duration
    ) throws -> Bool {
        guard let key = canonical(
                  delivery,
                  owner     : owner,
                  generation: generation
              ),
              let record = records[key],
              !record.revoked,
              record.jobID != nil
        else { return false }

        try outcome.validate()

        return journal.canComplete(
            key.requestID,
            owner     : owner,
            generation: generation,
            at        : instant
        )
    }

    /// observeExit releases a real job only for its exact host-owned delivery.
    public mutating func observeExit(
        _ delivery: Delivery,
        owner     : AddonID,
        generation: ConnectionGeneration
    ) throws -> Bool {
        guard let key = canonical(
                  delivery,
                  owner     : owner,
                  generation: generation
              ),
              let jobID = records[key]?.jobID
        else { return false }

        journal.connectionLost(owner: owner, generation: generation)
        try scheduler.finish(jobID, owner: owner)
        records[key]?.jobID   = nil
        records[key]?.revoked = true
        pruneHistory()

        return true
    }

    /// disable revokes every old ticket before cancellation; fresh enabled host
    /// context may admit new requests, but cannot revive those retained tickets.
    public mutating func disable(owner: AddonID) -> [Delivery] {
        let keys = records.keys.filter { $0.owner == owner }
        for key in keys { records[key]?.revoked = true }

        journal.cancel(owner: owner)

        return cancelJobs(keys)
    }

    /// expire participates in the host's common deadline queue and reports stops once.
    public mutating func expire(at instant: Duration) -> [Delivery] {
        guard instant >= .zero else { return [] }

        journal.expire(at: instant)

        let cancellations = scheduler.expire(at: instant)

        var stops: [Delivery] = []
        for cancellation in cancellations {
            guard case .command(let request) = cancellation.job.work else { continue }

            let key = Key(owner: cancellation.job.owner, requestID: request.requestID)
            records[key]?.revoked = true
            if let delivery = delivery(for: key) {
                stops.append(delivery)
            } else {
                if cancellation.requiresStop {
                    // Reserved but never delivered: no external work exists.
                    scheduler.releaseUnsentReservation(cancellation.job.id, owner: key.owner)
                }
                records[key]?.jobID = nil
            }
        }

        pruneHistory()

        return stops
    }

    /// stop permanently closes admission on this coordinator before revoking work.
    public mutating func stop() -> [Delivery] {
        stopped  = true
        let keys = Array(records.keys)
        for key in keys { records[key]?.revoked = true }
        for owner in Set(keys.map(\.owner)) { journal.cancel(owner: owner) }

        return cancelJobs(keys)
    }

    private var revokedFailure: AddonFailure {
        AddonFailure(
            code  : .sessionRevoked,
            reason: "The command is no longer eligible for delivery."
        )
    }

    private func canonical(
        _ delivery: Delivery,
        owner     : AddonID,
        generation: ConnectionGeneration
    ) -> Key? {
        let request = delivery.ticket.request
        let key     = Key(owner: owner, requestID: request.requestID)

        guard request.publicationID.addonID == owner,
              delivery.generation == generation,
              let record = records[key],
              record.ticketID == delivery.ticket.id,
              record.generation == generation,
              let jobID = record.jobID,
              scheduler.job(jobID)?.work == .command(request)
        else { return nil }

        return key
    }

    private func delivery(for key: Key) -> Delivery? {
        guard let record = records[key],
              let generation = record.generation,
              let ticketID   = record.ticketID,
              let jobID      = record.jobID,
              let job        = scheduler.job(jobID),
              case .command(let request) = job.work
        else { return nil }

        return Delivery(
            ticket    : Ticket(id: ticketID, request: request),
            generation: generation
        )
    }

    private mutating func rejectReserved(
        _ key: Key,
        jobID: UUID
    ) {
        records[key]?.revoked = true
        journal.rejectUnsent(
            key.requestID,
            owner  : key.owner,
            failure: revokedFailure
        )
        scheduler.releaseUnsentReservation(jobID, owner: key.owner)
        records[key]?.jobID = nil
    }

    private mutating func cancelJobs(_ keys: [Key]) -> [Delivery] {
        var stops: [Delivery] = []
        for key in keys {
            guard let jobID = records[key]?.jobID,
                  let cancellation = scheduler.cancelJob(jobID, owner: key.owner)
            else { continue }

            if let delivery = delivery(for: key) {
                stops.append(delivery)
            } else {
                if cancellation.requiresStop {
                    scheduler.releaseUnsentReservation(jobID, owner: key.owner)
                }
                records[key]?.jobID = nil
            }
        }

        pruneHistory()

        return stops
    }

    private mutating func pruneHistory() {
        for key in records.keys
        where records[key]?.jobID == nil && journal.state(key.requestID, owner: key.owner) == nil {
            records.removeValue(forKey: key)
        }
    }
}
