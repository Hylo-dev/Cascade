//
//  MessageAddonAssetClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// MessageAddonAssetClient is the concrete message-based `AddonAssetClient` for one injected
/// `AddonAssetMessageChannel`.
///
/// Responsibilities:
/// - it owns one synchronous lock-gated whole-operation slot for import/share/release and their
///   abort cleanup, with no waiter queue, and coordinates every close/drain through one shared
///   completion so no caller mistakes a revoked flag for finished disposal;
/// - it reads the immutable generation/profile from the channel and rejects unsupported syntax
///   before any exchange;
/// - it issues strictly increasing per-channel sequences (first = 1) with a fresh request UUID
///   per frame and never reuses a sequence on failure or overflow;
/// - it encodes and validates every request/response with the existing Foundation codec.
///
/// Limitations:
/// - the channel is injected bytes for an already-authenticated connection; this client performs
///   no authentication and installs no OS transport;
/// - a malformed/mismatched reply or a transport exception irreversibly poisons the client, which
///   awaits `channel.close()` and never retries a possibly completed mutation;
/// - cancellation alone is never treated as proof of physical rejection or disposal.
public final class MessageAddonAssetClient: AddonAssetClient, @unchecked Sendable {

    private let channel: any AddonAssetMessageChannel
    private let lock    = NSLock()

    private var closed       = false
    private var poisoned     = false
    private var busy         = false
    private var lastSequence: UInt64 = 0

    /// drainTask is the one shared physical channel drain. Every caller that requires disposal
    /// awaits this exact task instead of mistaking a closed/poisoned flag for completed cleanup.
    private var drainTask: Task<Void, Never>?

#if DEBUG
    /// drainWaitObserver lets tests acknowledge this caller's shared-drain participation.
    /// It runs synchronously outside the client lock and cannot suspend the caller or replace
    /// the physical wait. Task-local storage keeps concurrent clients and callers independent.
    @TaskLocal
    internal static var drainWaitObserver: (@Sendable () -> Void)?
#endif

#if DEBUG
    /// Default-inert checkpoint after success validation, before the final completion decision.
    @TaskLocal
    internal static var successFinalizationObserver: (@Sendable () async -> Void)?
#endif

    /// init installs one connection-bound channel; the channel keeps its own generation/profile.
    public init(channel: any AddonAssetMessageChannel) {
        self.channel = channel
    }

    // MARK: AddonAssetClient

    public func importAsset(
        _ data       : Data,
        publicationID: PublicationID
    ) async throws -> AssetHandle {
        let generation = try acquire()

        do {
            let handle = try await performImport(
                data,
                publicationID: publicationID,
                generation   : generation
            )
            try await concludeSuccess()
            return handle
        } catch {
            await conclude()
            throw error
        }
    }

    public func shareAsset(
        _ asset: AssetHandle,
        to     : PublicationID
    ) async throws -> AssetHandle {
        let generation = try acquire()

        do {
            let handle = try await performShare(
                asset,
                to        : to,
                generation: generation
            )
            try await concludeSuccess()
            return handle
        } catch {
            await conclude()
            throw error
        }
    }

    public func releaseAsset(_ asset: AssetHandle) async throws {
        let generation = try acquire()

        do {
            try await performRelease(asset, generation: generation)
            try await concludeSuccess()
        } catch {
            await conclude()
            throw error
        }
    }

    // MARK: Import

    /// performImport drives begin -> ordered chunks -> finish, aborting a transfer that is still
    /// known live whenever the operation stops before finish, including a late cancellation.
    private func performImport(
        _ data       : Data,
        publicationID: PublicationID,
        generation   : ConnectionGeneration
    ) async throws -> AssetHandle {
        let profile = try requireProfile()

        // Cancellation before begin sends nothing.
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= AssetTransferFrameCodec.maximumTotalBytes else {
            throw failure(.invalidPayload)
        }

        var transferID: UUID?
        var finishing  = false

        do {
            let begun = try await exchange(
                try AssetTransferRequest(
                    requestID    : UUID(),
                    operation    : .begin,
                    publicationID: publicationID,
                    totalBytes   : data.count
                ),
                profile   : profile,
                generation: generation
            )
            guard begun.result == .begun, let id = begun.transferID else {
                throw failure(.invalidPayload)
            }

            transferID = id
            var offset = 0
            while offset < data.count {
                // Every between-exchange boundary aborts a still-live transfer on cancellation.
                try Task.checkCancellation()

                let count = min(AssetTransferFrameCodec.maximumChunkBytes, data.count - offset)
                let chunk = data.subdata(in: offset..<(offset + count))

                let acknowledgement = try await exchange(
                    try AssetTransferRequest(
                        requestID : UUID(),
                        operation : .chunk,
                        transferID: id,
                        offset    : offset,
                        bytes     : chunk
                    ),
                    profile   : profile,
                    generation: generation
                )
                guard acknowledgement.result == .acknowledged,
                      acknowledgement.transferID == id,
                      acknowledgement.nextOffset == offset + count
                else {
                    throw failure(.invalidPayload)
                }

                offset = acknowledgement.nextOffset ?? (offset + count)
            }

            // After the final chunk and before finish, cancellation still aborts the known live
            // transfer instead of abandoning the host's receiving assembly.
            try Task.checkCancellation()
            finishing = true
            let imported = try await exchange(
                try AssetTransferRequest(
                    requestID : UUID(),
                    operation : .finish,
                    transferID: id
                ),
                profile   : profile,
                generation: generation
            )
            // A known successful finish is never discarded because of a later cancellation.
            transferID = nil
            guard imported.result == .imported, let handle = imported.assetHandle else {
                throw failure(.invalidPayload)
            }

            // The imported alias must match the original begin publication and owner.
            guard handle.owner == publicationID.addonID,
                  handle.publicationID == publicationID
            else {
                await poison()
                throw failure(.invalidPayload)
            }

            return handle
        } catch {
            // A terminal stale/expired failure already revoked the transfer at the host, so a
            // redundant abort would be refused and must not poison a healthy channel. A finish
            // failure is host-owned cleanup too. Only a still-live transfer is aborted.
            if let transferID, !finishing, !isTerminalTransferFailure(error) {
                await abortOrPoison(
                    transferID,
                    profile   : profile,
                    generation: generation
                )
            }

            throw error
        }
    }

    // MARK: Share and release

    private func performShare(
        _ asset   : AssetHandle,
        to        : PublicationID,
        generation: ConnectionGeneration
    ) async throws -> AssetHandle {
        let profile = try requireProfile()
        try Task.checkCancellation()
        try asset.validate()

        let response = try await exchange(
            try AssetTransferRequest(
                requestID    : UUID(),
                operation    : .share,
                publicationID: to,
                sourceHandle : asset
            ),
            profile   : profile,
            generation: generation
        )
        guard response.result == .shared, let handle = response.assetHandle else {
            throw hostFailure(response)
        }
        guard handle.owner == asset.owner, handle.publicationID == to else {
            await poison()
            throw failure(.invalidPayload)
        }

        return handle
    }

    private func performRelease(
        _ asset   : AssetHandle,
        generation: ConnectionGeneration
    ) async throws {
        let profile = try requireProfile()
        try Task.checkCancellation()
        try asset.validate()

        let response = try await exchange(
            try AssetTransferRequest(
                requestID   : UUID(),
                operation   : .release,
                sourceHandle: asset
            ),
            profile   : profile,
            generation: generation
        )

        guard response.result == .acknowledged else { throw hostFailure(response) }
    }

    // MARK: Explicit close

    /// close irreversibly revokes the client and the channel and drains outstanding exchange.
    /// In-flight operations observe the closure on their next boundary and honor it. Repeated and
    /// concurrent callers all await the same actual drain rather than a revoked flag.
    public func close() async {
        lock.withLock { closed = true }

        await drain()
    }

    // MARK: Protected scalar state

    /// acquire claims the whole-operation slot synchronously; busy is reported without waiting.
    private func acquire() throws -> ConnectionGeneration {
        try lock.withLock {
            if Task.isCancelled { throw CancellationError() }
            if closed || poisoned { throw failure(.sessionRevoked) }
            guard !busy else { throw failure(.resourceDenied) }

            busy = true
            return channel.generation
        }
    }

    /// conclude holds the whole-operation slot until any required channel drain has actually
    /// completed, so no later caller can enter the slot while disposal is still in flight.
    private func conclude() async {
        if isRevoked { await drain() }

        lock.withLock { busy = false }
    }

    /// concludeSuccess orders successful completion and explicit close under the same lock. Once
    /// success wins, a later close cannot revoke that completed result. If revocation wins, keep
    /// the whole-operation slot through physical disposal and reject even a validated response.
    private func concludeSuccess() async throws {
#if DEBUG
        await Self.successFinalizationObserver?()
#endif
        let completed = lock.withLock {
            guard !closed, !poisoned else { return false }

            busy = false
            return true
        }

        guard completed else {
            await drain()
            lock.withLock { busy = false }
            throw failure(.sessionRevoked)
        }
    }

    private func requireProfile() throws -> AssetTransferFrameProfile {
        guard channel.profile == .v1 else { throw failure(.versionConflict) }

        return .v1
    }

    private var isClosed  : Bool { lock.withLock { closed } }
    private var isPoisoned: Bool { lock.withLock { poisoned } }
    private var isRevoked : Bool { lock.withLock { closed || poisoned } }

    /// nextSequence advances the checked counter; a failed attempt keeps its consumed value.
    private func nextSequence() throws -> UInt64 {
        try lock.withLock {
            guard lastSequence < UInt64.max else { throw failure(.resourceDenied) }

            lastSequence += 1
            return lastSequence
        }
    }

    // MARK: Exchange and poisoning

    /// exchange bounds, sends and validates one request/response pair.
    /// Malformed or mismatched replies and transport exceptions poison the client.
    private func exchange(
        _ request : AssetTransferRequest,
        profile   : AssetTransferFrameProfile,
        generation: ConnectionGeneration
    ) async throws -> AssetTransferResponse {
        guard !isClosed, !isPoisoned, channel.generation == generation else {
            await poison()
            throw failure(.sessionRevoked)
        }

        let sequence = try nextSequence()
        let frame    = try AssetTransferFrameCodec.encode(request, profile: profile)

        let reply: Data
        do {
            reply = try await channel.exchange(frame, sequence: sequence)
        } catch {
            await poison()
            throw failure(.outcomeUnknown)
        }

        if isClosed {
            await poison()
            throw failure(.sessionRevoked)
        }

        let response: AssetTransferResponse
        do {
            response = try AssetTransferFrameCodec.decodeResponse(reply, profile: profile)
            try response.validate(matching: request)
        } catch {
            await poison()
            throw failure(.invalidPayload)
        }

        if response.result == .failure { throw hostFailure(response) }
        return response
    }

    /// abortOrPoison drains an abort acknowledgement for a known live import.
    /// When the abort exchange cannot complete, the client is poisoned and the channel closed. A
    /// terminal refusal means the transfer is already gone, so the healthy channel is kept.
    private func abortOrPoison(
        _ transferID: UUID,
        profile     : AssetTransferFrameProfile,
        generation  : ConnectionGeneration
    ) async {
        guard !isPoisoned, !isClosed else { return }

        do {
            _ = try await exchange(
                try AssetTransferRequest(
                    requestID : UUID(),
                    operation : .abort,
                    transferID: transferID
                ),
                profile   : profile,
                generation: generation
            )
        } catch {
            if isTerminalTransferFailure(error) { return }

            await poison()
        }
    }

    /// poison is one-way and idempotent; every caller awaits the same shared channel drain.
    private func poison() async {
        lock.withLock { poisoned = true }

        await drain()
    }

    /// drain starts the one shared physical channel close and awaits its real completion. The
    /// unstructured task does not inherit caller cancellation, so a cancelled caller cannot
    /// abandon a drain that another caller is still awaiting.
    private func drain() async {
        let task: Task<Void, Never> = lock.withLock {
            if let drainTask { return drainTask }

            let channel = self.channel
            let created = Task { await channel.close() }
            drainTask   = created
            return created
        }
#if DEBUG
        Self.drainWaitObserver?()
#endif
        await task.value
    }

    /// isTerminalTransferFailure reports a bounded refusal that proves the transfer is gone:
    /// a revoked/finished transfer or an expired deadline. A redundant abort would be refused.
    private func isTerminalTransferFailure(_ error: any Error) -> Bool {
        guard let failure = error as? AddonFailure else { return false }

        switch failure.code {
            case .sessionRevoked, .deadlineExceeded: return true
            default: return false
        }
    }

    private func hostFailure(_ response: AssetTransferResponse) -> AddonFailure {
        failure(response.failureCode ?? .invalidPayload)
    }

    private func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "The asset client cannot complete this operation (\(code.rawValue))."
        )
    }
}
