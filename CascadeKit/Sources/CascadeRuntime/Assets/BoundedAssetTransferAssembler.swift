//
//  BoundedAssetTransferAssembler.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AssetTransferBinding carries immutable host-derived assignment identity, never authentication.
/// Integration must mint and revalidate the assignment against publisher/digest/feature/privacy.
struct AssetTransferBinding: Equatable, Sendable {
    let incarnation    : RuntimeIncarnation
    let connectionToken: UUID
    let publicationID  : PublicationID
    let assignmentToken: UUID
}

/// BoundedAssetTransferAssembler owns one prepaid fixed buffer for one runtime incarnation.
/// It creates no worker, queue or timer. The host must explicitly close it and service deadlines.
final class BoundedAssetTransferAssembler: @unchecked Sendable {
    private enum Phase { case idle, admitting, receiving, decoding, disposing, closed }

    /// Record deliberately has no Data: it can survive governor awaits without retaining input.
    private struct Record: Sendable {
        let nonce     : UUID
        let transferID: UUID
        let binding   : AssetTransferBinding
        let token     : AssetTransferReservationToken
        let totalBytes: Int
        let deadline  : Duration
    }

    private enum DecodeOutcome {
        case raster(AssetRasterBacking)
        case failure(AddonFailure.Code)
        case cancelled
    }

    /// ReceivingOutcome carries only scalar progress or exact disposal authority across awaits.
    /// Rejection is committed while the original receiving lock is still held.
    private enum ReceivingOutcome<Value> {
        case accepted(Value)
        case rejected(Record, RequestRejection)
    }

    private enum RequestRejection {
        case failure(AddonFailure.Code)
        case cancelled

        init(_ error: any Error) {
            if error is CancellationError {
                self = .cancelled
            } else {
                self = .failure((error as? AddonFailure)?.code ?? .invalidPayload)
            }
        }

        var error: any Error {
            switch self {
            case .failure(let code): BoundedAssetTransferAssembler.failure(code)
            case .cancelled: CancellationError()
            }
        }
    }

    private let incarnation: RuntimeIncarnation
    private let clock      : any RuntimeClock
    private let decoder    : any AssetImageDecoding
    private let governor   : ResourceGovernor
    private let lock       = NSLock()
    private var phase      = Phase.idle
    private var closed     = false
    private var nonce      : UUID?
    /// admittingBinding ties a synchronous exact revocation to the one begin suspended in
    /// protected admission, before a Record exists to carry the immutable binding.
    private var admittingBinding: AssetTransferBinding?
    private var record     : Record?
    private var buffer     : Data?
    private var received   = 0
    private var lastSample : Duration?
    private var revoked    : AddonFailure.Code?
    /// disposalInFlight marks the one live refund attempt so a concurrent close/abort/expire
    /// cannot start a second actor hop for a record whose disposal is already owned.
    private var disposalInFlight = false

    init(
        incarnation: RuntimeIncarnation,
        clock      : any RuntimeClock,
        decoder    : any AssetImageDecoding
    ) {
        self.incarnation = incarnation
        self.clock       = clock
        self.decoder     = decoder
        self.governor    = decoder.assetGovernor
    }

    var nextDeadline: Duration? {
        lock.withLock {
            guard let record else { return nil }
            // A disposal-only record has already dropped its buffer and only owes a refund.
            // It is retried even after close so a failed begin rollback cannot lose its token.
            if phase == .disposing { return record.deadline }
            return closed ? nil : record.deadline
        }
    }

#if DEBUG
    struct LifecycleSnapshot: Sendable {
        let identity: ObjectIdentifier
        let phase: String
        let closed: Bool
        let binding: AssetTransferBinding?
        let reservationID: UUID?
        let bufferBytes: Int
        let refundInFlight: Bool
    }

    /// lifecycleSnapshotForTesting exposes current ownership, never refund authority.
    func lifecycleSnapshotForTesting() -> LifecycleSnapshot {
        lock.withLock {
            LifecycleSnapshot(
                identity      : ObjectIdentifier(self),
                phase         : String(describing: phase),
                closed        : closed,
                binding       : record?.binding ?? admittingBinding,
                reservationID : record?.token.reservation.id,
                bufferBytes   : buffer?.count ?? 0,
                refundInFlight: disposalInFlight
            )
        }
    }
#endif

    /// invalidate revokes return authority synchronously for runtime stop, exit or disable.
    /// It never refunds a buffer that a suspended decode still owns: async close/dispose
    /// remains the single accounting path, so a native finish cannot return authority after
    /// a synchronous stop and live raster bytes are not released early.
    func invalidate() {
        lock.withLock {
            closed = true
            revoked = .sessionRevoked
        }
    }

    /// revokeTransfer withdraws return authority synchronously for exactly one binding, without
    /// closing the assembler. It covers all three suspension points: admitting refuses to install
    /// a Record for a suspended begin, receiving drops its buffer and hands the exact refund to the
    /// host's deferred cleanup, and decoding only marks revocation so the running native finish
    /// keeps its own cleanup and refunds once. A foreign or replacement binding is ignored, and a
    /// terminally closed assembler is never reopened.
    func revokeTransfer(binding: AssetTransferBinding) {
        lock.withLock {
            guard !closed, binding.incarnation == incarnation else { return }
            switch phase {
            case .admitting:
                guard admittingBinding == binding else { return }
                revoked = .sessionRevoked
            case .receiving:
                guard let active = record, active.binding == binding else { return }
                revoked = .sessionRevoked
                // Drop the buffer now, but leave disposalInFlight false so the bounded deferred
                // cleanup owns the one refund attempt instead of waiting for the 30s deadline.
                buffer = nil
                phase = .disposing
                disposalInFlight = false
            case .disposing:
                guard let active = record, active.binding == binding else { return }
                revoked = .sessionRevoked
            case .decoding:
                guard let active = record, active.binding == binding else { return }
                revoked = .sessionRevoked
            case .idle, .closed:
                return
            }
        }
    }

    /// begin installs a scalar admission gate before requesting money; no buffer exists yet.
    func begin(
        totalBytes: Int,
        binding   : AssetTransferBinding
    ) async throws -> UUID {
        let operation = try lock.withLock {
            try Task.checkCancellation()
            guard !closed, binding.incarnation == incarnation else { throw Self.failure(.sessionRevoked) }
            guard phase == .idle else { throw Self.failure(.resourceDenied) }
            guard (1...1_048_576).contains(totalBytes) else { throw Self.failure(.invalidPayload) }
            _ = try sample()
            let operation = UUID()
            nonce = operation
            admittingBinding = binding
            // Isolate the new admission from any revocation left over by a fully disposed
            // transfer: the flag is only meaningful while a transfer owns return authority.
            revoked = nil
            phase = .admitting
            return operation
        }
        let token: AssetTransferReservationToken
        do {
            token = try await governor.admitAssetTransfer(
                bytes: totalBytes,
                owner: binding.publicationID.addonID
            )
#if DEBUG
            await AssetLifecycleTesting.observer(for: governor)?.admittedTransfer(
                reservationID: token.reservation.id,
                binding      : binding
            )
#endif
        } catch {
            lock.withLock {
                if nonce == operation {
                    nonce = nil
                    admittingBinding = nil
                    phase = closed ? .closed : .idle
                }
            }
            throw error
        }
        do {
            return try lock.withLock {
                try Task.checkCancellation()
                guard !closed, nonce == operation else { throw Self.failure(.sessionRevoked) }
                // A synchronous exact revocation raced this protected admission: refuse to install
                // the Record so the catch below refunds the retained token through the one path.
                if let revoked { throw Self.failure(revoked) }
                let accepted = try sample()
                let transferID = UUID()
                record = Record(
                    nonce     : operation,
                    transferID: transferID,
                    binding   : binding,
                    token     : token,
                    totalBytes: totalBytes,
                    deadline  : accepted + .seconds(30)
                )
                // A fixed count is allocated only after the governor and authority checks.
                buffer   = Data(count: totalBytes)
                received = 0
                revoked  = nil
                admittingBinding = nil
                phase    = .receiving
                return transferID
            }
        } catch {
            // The failed admission still owns the protected token. Install a disposal-only
            // Record *before* the refund so a throwing governor cannot drop the only handle:
            // it has no buffer, and close()/expire() retry the exact refund without spinning.
            let active = Record(
                nonce     : operation,
                transferID: UUID(),
                binding   : binding,
                token     : token,
                totalBytes: totalBytes,
                deadline  : (lastSample ?? .zero) + .seconds(30)
            )
            let installed = lock.withLock {
                guard nonce == operation, record == nil else { return false }
                record  = active
                admittingBinding = nil
                buffer  = nil
                revoked = nil
                phase   = .disposing
                disposalInFlight = true
                return true
            }
            guard installed else {
                // A concurrent path already owns this admission; refund without retaining.
                try? await governor.completeAssetTransfer(
                    token,
                    owner: binding.publicationID.addonID
                )
                throw error
            }
            do {
                try await dispose(active)
            } catch {
                // Retained with its exact token; the host drains it on close()/expire().
            }
            throw error
        }
    }

    /// append copies exactly the next full chunk (or the final remainder) in place.
    /// Foreign authority is checked before time/progression and cannot revoke the live slot.
    func append(
        transferID: UUID,
        binding   : AssetTransferBinding,
        offset    : Int,
        bytes     : Data
    ) async throws -> Int {
        let outcome: ReceivingOutcome<Int> = try lock.withLock {
            let active = try match(
                transferID: transferID,
                binding   : binding
            )
            // Foreign and busy calls never enter the terminal receiving-error path.
            guard phase == .receiving else { throw Self.failure(.resourceDenied) }
            do {
                try check(active)
                try Task.checkCancellation()
                let remaining = active.totalBytes - received
                guard remaining > 0, offset == received,
                      bytes.count == min(
                          65_536,
                          remaining
                      ) else { throw Self.failure(.invalidPayload) }
                buffer?.replaceSubrange(
                    received..<(received + bytes.count),
                    with: bytes
                )
                received += bytes.count
                return .accepted(received)
            } catch {
                // A competing finish must observe disposing, never the rejected receipt state.
                buffer = nil
                phase = .disposing
                disposalInFlight = true
                return .rejected(
                    active,
                    RequestRejection(error)
                )
            }
        }
        switch outcome {
        case .accepted(let nextOffset): return nextOffset
        case .rejected(let active, let rejection):
            try await dispose(active)
            throw rejection.error
        }
    }

    /// finish owns cleanup until native decoding has ended and all compressed borrows are gone.
    func finish(
        transferID: UUID,
        binding   : AssetTransferBinding
    ) async throws -> AssetRasterBacking {
        let admission: ReceivingOutcome<Record> = try lock.withLock {
            let active = try match(
                transferID: transferID,
                binding   : binding
            )
            guard phase == .receiving else { throw Self.failure(.resourceDenied) }
            do {
                try check(active)
                try Task.checkCancellation()
                guard received == active.totalBytes else { throw Self.failure(.invalidPayload) }
                phase = .decoding
                return .accepted(active)
            } catch {
                // Commit terminal cleanup before unlocking, including incomplete/cancelled finish.
                buffer = nil
                phase = .disposing
                disposalInFlight = true
                return .rejected(
                    active,
                    RequestRejection(error)
                )
            }
        }
        let active: Record
        switch admission {
        case .accepted(let admitted): active = admitted
        case .rejected(let rejected, let rejection):
            try await dispose(rejected)
            throw rejection.error
        }
        let outcome = await decodeBorrow(active)
        // decodeBorrow's lexical frame and Data/CFData references ended before this clear.
        // Mark the live refund so a concurrent close/abort cannot start a second hop.
        lock.withLock {
            buffer = nil
            phase = .disposing
            disposalInFlight = true
        }
        do {
            try await governor.completeAssetTransfer(
                active.token,
                owner: binding.publicationID.addonID
            )
        } catch {
            lock.withLock { disposalInFlight = false }
            throw error
        }
        lock.withLock { disposalInFlight = false }
        return try lock.withLock {
            defer { reset(active) }
            try Task.checkCancellation()
            try check(active)
            switch outcome {
            case .raster(let raster): return raster
            case .failure(let code): throw Self.failure(code)
            case .cancelled: throw CancellationError()
            }
        }
    }

    /// decodeBorrow is the only async frame allowed to borrow assembled bytes.
    /// Only a protected raster or bounded scalar failure escapes, never an arbitrary Error.
    private func decodeBorrow(_ active: Record) async -> DecodeOutcome {
        do {
            let encoded = try lock.withLock {
                try check(active)
                guard let buffer else { throw Self.failure(.sessionRevoked) }
                return buffer
            }
            let raster = try await decoder.decode(
                encoded: encoded,
                owner  : active.binding.publicationID.addonID
            )
            return .raster(raster)
        } catch is CancellationError {
            return .cancelled
        } catch let failure as AddonFailure {
            return .failure(failure.code)
        } catch {
            return .failure(.invalidPayload)
        }
    }

    /// abort revokes exact authority immediately; a running decoder retains its cleanup owner.
    func abort(
        transferID: UUID,
        binding   : AssetTransferBinding
    ) async throws {
        let action: (Record?, AddonFailure.Code?) = try lock.withLock {
            let active = try match(
                transferID: transferID,
                binding   : binding
            )
            do {
                try check(active)
                revoked = .sessionRevoked
                return (prepareDisposal(active), nil)
            } catch let failure as AddonFailure {
                revoked = failure.code
                return (prepareDisposal(active), failure.code)
            }
        }
        if let disposal = action.0 { try await dispose(disposal) }
        if let code = action.1 { throw Self.failure(code) }
    }

    /// expire is driven by the existing host deadline service, with no per-transfer timer.
    func expire() async throws {
        let action: (Record?, AddonFailure.Code?) = lock.withLock {
            guard let active = record else { return (nil, nil) }
            // A disposal-only record retries its refund even after close, unless a live
            // disposal already owns the hop.
            if phase == .disposing {
                return disposalInFlight ? (nil, nil) : (active, nil)
            }
            guard !closed else { return (nil, nil) }
            do {
                try check(active)
                return (nil, nil)
            } catch let error as AddonFailure {
                revoked = error.code
                return (prepareDisposal(active), error.code == .deadlineExceeded ? nil : error.code)
            } catch {
                revoked = .invalidPayload
                return (prepareDisposal(active), .invalidPayload)
            }
        }
        if let disposal = action.0 { try await dispose(disposal) }
        if let code = action.1 { throw Self.failure(code) }
    }

    /// close prevents future admission and revokes return authority without premature refunds.
    func close() async throws {
        let disposal = lock.withLock {
            closed = true
            revoked = .sessionRevoked
            guard let active = record else {
                if phase == .idle { phase = .closed }
                return Optional<Record>.none
            }
            return prepareDisposal(active)
        }
        if let disposal { try await dispose(disposal) }
    }

    /// drainPendingCleanup drives the bounded deferred owner for a retained assembler. It finishes
    /// a terminal close for a revoked process/connection, but for an exact nonterminal revocation it
    /// completes only the pending refund and returns the assembler to idle, so the same live process
    /// can admit a later authorized transfer. It never starts a second hop for a live native decode
    /// or an in-flight refund.
    func drainPendingCleanup() async throws {
        let disposal: Record? = lock.withLock {
            if closed {
                guard let active = record else {
                    if phase == .idle { phase = .closed }
                    return nil
                }
                return prepareDisposal(active)
            }
            guard phase == .disposing, !disposalInFlight, let active = record else { return nil }
            disposalInFlight = true
            return active
        }
        if let disposal { try await dispose(disposal) }
    }

    private func match(
        transferID: UUID,
        binding   : AssetTransferBinding
    ) throws -> Record {
        guard let active = record, active.transferID == transferID, active.binding == binding else {
            throw Self.failure(.sessionRevoked)
        }
        return active
    }

    /// sample rejects invalid or backward host time without changing the last valid sample.
    private func sample() throws -> Duration {
        let instant = clock.now()
        guard instant.wall.timeIntervalSince1970.isFinite, instant.monotonic >= .zero,
              instant.monotonic <= .seconds(Int64.max - 31),
              lastSample.map({ instant.monotonic >= $0 }) ?? true else {
            throw Self.failure(.invalidPayload)
        }
        lastSample = instant.monotonic
        return instant.monotonic
    }

    private func check(_ active: Record) throws {
        guard !closed, nonce == active.nonce else { throw Self.failure(.sessionRevoked) }
        if let revoked { throw Self.failure(revoked) }
        guard try sample() < active.deadline else { throw Self.failure(.deadlineExceeded) }
    }

    /// prepareDisposal transfers cleanup ownership from receipt waiting or from a retained
    /// failed refund, but never from decoding and never while a refund hop is already live.
    private func prepareDisposal(_ active: Record) -> Record? {
        switch phase {
        case .receiving:
            buffer = nil
            phase = .disposing
            disposalInFlight = true
            return active
        case .disposing:
            guard !disposalInFlight else { return nil }
            buffer = nil
            disposalInFlight = true
            return active
        case .decoding, .admitting, .idle, .closed:
            return nil
        }
    }

    private func dispose(_ active: Record) async throws {
        lock.withLock { disposalInFlight = true }
        do {
            try await governor.completeAssetTransfer(
                active.token,
                owner: active.binding.publicationID.addonID
            )
        } catch {
            lock.withLock { disposalInFlight = false }
            throw error
        }
        lock.withLock { disposalInFlight = false }
        lock.withLock { reset(active) }
    }

    private func reset(_ active: Record) {
        guard nonce == active.nonce else { return }
        record   = nil
        nonce    = nil
        admittingBinding = nil
        received = 0
        revoked  = nil
        phase    = closed ? .closed : .idle
    }

    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "Asset transfer cannot proceed: \(code.rawValue)."
        )
    }
}
