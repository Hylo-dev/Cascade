//
//  MessageAddonAssetClientTests.swift
//  CascadeKit
//

@testable import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing

/// MessageAddonAssetClientTests exercise the concrete SDK client against a scripted channel.
/// Canned channels are sufficient here; the real host path is covered by the runtime bridge test.
@Suite(.timeLimit(.minutes(1)))
struct MessageAddonAssetClientTests {
    private static let publication = PublicationID(
        addonID   : AddonID(rawValue: "com.example.assets")!,
        instanceID: UUID(),
        sessionID : UUID()
    )

    private static func sourceHandle() throws -> AssetHandle {
        try AssetHandle(
            assetID       : "asset-1",
            owner         : publication.addonID,
            publicationID : publication,
            rasterRevision: 1,
            width         : 1,
            height        : 1,
            byteCount     : 4
        )
    }

    @Test func importSendsOrderedChunksAndMonotonicSequences() async throws {
        let channel = ScriptedAssetChannel()
        let client = MessageAddonAssetClient(channel: channel)
        let data = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        let handle = try await client.importAsset(
            data,
            publicationID: Self.publication
        )
        #expect(handle.owner == Self.publication.addonID)
        #expect(handle.publicationID == Self.publication)
        let sequences = await channel.observedSequences
        #expect(sequences == Array(1...UInt64(sequences.count)))
        #expect(Set(sequences).count == sequences.count)
        let operations = await channel.observedOperations
        #expect(operations.first == .begin)
        #expect(operations.last == .finish)
        // Full chunks then a final remainder.
        let chunkSizes = await channel.chunkSizes
        #expect(chunkSizes.dropLast().allSatisfy { $0 == 65_536 })
        #expect(chunkSizes.last == 200_000 - 3 * 65_536)
        await client.close()
        #expect(await channel.closeCount == 1)
    }

    @Test func unsupportedProfileIsRejectedBeforeAnyExchange() async throws {
        let channel = ScriptedAssetChannel(profile: nil)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            try await client.importAsset(
                Data([1]),
                publicationID: Self.publication
            )
        }
        #expect(await channel.observedSequences.isEmpty)
    }

    @Test func busyOperationIsRejectedWithoutDisturbingActiveWork() async throws {
        let channel = ScriptedAssetChannel(
            gateExchange: true
        )
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task {
            try await client.importAsset(
                Data(repeating: 7, count: 1_024),
                publicationID: Self.publication
            )
        }
        await channel.waitUntilBlocked()
        await #expect(throws: AddonFailure.self) {
            try await client.shareAsset(
                try Self.sourceHandle(),
                to: Self.publication
            )
        }
        await channel.release()
        _ = try await task.value
        await client.close()
    }

    @Test func transportErrorPoisonsAndClosesWithoutRetry() async throws {
        let channel = ScriptedAssetChannel(mode: .transportErrorOnChunk)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
        // The client is irreversibly poisoned: no further exchange and no retry.
        let countAfterFailure = await channel.observedSequences.count
        await #expect(throws: AddonFailure.self) {
            try await client.releaseAsset(
                try Self.sourceHandle()
            )
        }
        #expect(await channel.observedSequences.count == countAfterFailure)
    }

    @Test func malformedReplyPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .malformedReply)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
    }

    @Test func hostFailureSurfacesBoundedCodeAndAbortsLiveTransfer() async throws {
        let channel = ScriptedAssetChannel(
            mode: .hostFailure(operation: .chunk, code: .permissionDenied)
        )
        let client = MessageAddonAssetClient(channel: channel)
        do {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
            Issue.record("Expected a host failure")
        } catch let failure as AddonFailure {
            #expect(failure.code == .permissionDenied)
        }
        // A non-terminal host failure still owes cleanup for the known live import.
        #expect(await channel.observedOperations == [.begin, .chunk, .abort])
        // It is a known result, not a poisoned transport.
        #expect(await channel.closeCount == 0)
        await client.close()
    }

    @Test func cancellationBeforeBeginSendsNothing() async throws {
        let channel = ScriptedAssetChannel()
        let client = MessageAddonAssetClient(channel: channel)
        let gate = StartGate()
        let task = Task {
            await gate.wait()
            return try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        // The gate guarantees the cancellation is set before importAsset is reached, so this is
        // not a scheduling race.
        task.cancel()
        await gate.open()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(await channel.observedSequences.isEmpty)
        #expect(await channel.closeCount == 0)
        await client.close()
    }

    @Test func cancellationBetweenExchangesAbortsKnownTransferWithoutPoisoning() async throws {
        let channel = ScriptedAssetChannel(holdAt: 2)
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task {
            try await client.importAsset(
                Data(repeating: 1, count: 200_000),
                publicationID: Self.publication
            )
        }
        await channel.waitUntilHeld()
        task.cancel()
        await channel.releaseHeld()
        await #expect(throws: (any Error).self) { try await task.value }
        // The still-live transfer is aborted and drained; no finish is attempted.
        #expect(await channel.observedOperations == [.begin, .chunk, .abort])
        #expect(await channel.closeCount == 0)
    }

    @Test func cancellationAfterLastChunkBeforeFinishAbortsWithoutSendingFinish() async throws {
        let channel = ScriptedAssetChannel(holdAt: 2)
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task {
            try await client.importAsset(
                Data(repeating: 1, count: 1_024),
                publicationID: Self.publication
            )
        }
        await channel.waitUntilHeld()
        task.cancel()
        await channel.releaseHeld()
        await #expect(throws: (any Error).self) { try await task.value }
        // The last chunk is acknowledged, then cancellation aborts instead of losing the transfer.
        #expect(await channel.observedOperations == [.begin, .chunk, .abort])
        #expect(await channel.observedOperations.contains(.finish) == false)
        #expect(await channel.closeCount == 0)
    }

    @Test func terminalStaleTransferFailureDoesNotAbortOrPoison() async throws {
        let channel = ScriptedAssetChannel(
            mode: .hostFailure(operation: .chunk, code: .sessionRevoked)
        )
        let client = MessageAddonAssetClient(channel: channel)
        do {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
            Issue.record("Expected a terminal host failure")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        // A transfer known to be gone is not aborted again and does not poison a healthy channel.
        #expect(await channel.observedOperations == [.begin, .chunk])
        #expect(await channel.closeCount == 0)
        // The channel still carries a bounded operation.
        try await client.releaseAsset(try Self.sourceHandle())
        #expect(await channel.observedOperations.last == .release)
        await client.close()
    }

    @Test func terminalExpiredTransferFailureDoesNotAbortOrPoison() async throws {
        let channel = ScriptedAssetChannel(
            mode: .hostFailure(operation: .chunk, code: .deadlineExceeded)
        )
        let client = MessageAddonAssetClient(channel: channel)
        do {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
            Issue.record("Expected a terminal host failure")
        } catch let failure as AddonFailure {
            #expect(failure.code == .deadlineExceeded)
        }
        #expect(await channel.observedOperations == [.begin, .chunk])
        #expect(await channel.closeCount == 0)
        try await client.releaseAsset(try Self.sourceHandle())
        #expect(await channel.observedOperations.last == .release)
        await client.close()
    }

    @Test func abortRefusedAsAlreadyGoneDoesNotPoisonHealthyChannel() async throws {
        let channel = ScriptedAssetChannel(
            mode            : .hostFailure(operation: .chunk, code: .permissionDenied),
            abortFailureCode: .sessionRevoked
        )
        let client = MessageAddonAssetClient(channel: channel)
        do {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
            Issue.record("Expected a host failure")
        } catch let failure as AddonFailure {
            #expect(failure.code == .permissionDenied)
        }
        // The abort was attempted for the live-transfer cleanup, but its terminal refusal proves
        // the transfer is gone and must not poison the still-healthy channel.
        #expect(await channel.observedOperations == [.begin, .chunk, .abort])
        #expect(await channel.closeCount == 0)
        try await client.releaseAsset(try Self.sourceHandle())
        #expect(await channel.observedOperations.last == .release)
        await client.close()
    }

    @Test func abortRefusedForOtherReasonPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(
            mode            : .hostFailure(operation: .chunk, code: .permissionDenied),
            abortFailureCode: .resourceDenied
        )
        let client = MessageAddonAssetClient(channel: channel)
        do {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
            Issue.record("Expected a host failure")
        } catch let failure as AddonFailure {
            #expect(failure.code == .permissionDenied)
        }
        // An abort that cannot complete leaves the live transfer unconfirmed: poison and drain.
        #expect(await channel.observedOperations == [.begin, .chunk, .abort])
        #expect(await channel.closeCount == 1)
    }

    @Test func lateCancellationPreservesKnownImportResult() async throws {
        let channel = ScriptedAssetChannel(holdAt: 3)
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task {
            try await client.importAsset(
                Data(repeating: 1, count: 1_024),
                publicationID: Self.publication
            )
        }
        await channel.waitUntilHeld()
        // Cancellation arrives while the finish is physically in flight and the host then commits.
        task.cancel()
        await channel.releaseHeld()
        let handle = try await task.value
        #expect(handle.owner == Self.publication.addonID)
        #expect(handle.publicationID == Self.publication)
        // The known committed alias is returned; no abort and no drain that would lose it.
        #expect(await channel.observedOperations == [.begin, .chunk, .finish])
        #expect(await channel.closeCount == 0)
        await client.close()
    }

    @Test func lateCancellationPreservesKnownShareResult() async throws {
        let channel = ScriptedAssetChannel(holdAt: 1)
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task {
            try await client.shareAsset(
                try Self.sourceHandle(),
                to: Self.publication
            )
        }
        await channel.waitUntilHeld()
        task.cancel()
        await channel.releaseHeld()
        let handle = try await task.value
        #expect(handle.publicationID == Self.publication)
        #expect(await channel.observedOperations == [.share])
        #expect(await channel.closeCount == 0)
        await client.close()
    }

    @Test func lateCancellationPreservesKnownReleaseResult() async throws {
        let channel = ScriptedAssetChannel(holdSuccessAt: 1)
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task { try await client.releaseAsset(try Self.sourceHandle()) }
        // The successful, correlated release response has already been encoded.
        await channel.waitUntilHeld()
        task.cancel()
        await channel.releaseHeld()
        try await task.value
        #expect(await channel.observedOperations == [.release])
        #expect(await channel.observedSequences == [1])
        #expect(await channel.closeCount == 0)
        // Cancellation did not revoke the slot or force physical disposal.
        try await client.releaseAsset(try Self.sourceHandle())
        #expect(await channel.observedSequences == [1, 2])
        #expect(await channel.observedOperations == [.release, .release])
        await client.close()
    }

#if DEBUG
    @Test(arguments: [AssetTransferOperation.finish, .share, .release], [false, true])
    func explicitCloseRevokesSuccessfulMutationReturnAfterSharedDrain(
        operation: AssetTransferOperation,
        afterValidation: Bool
    ) async throws {
        let operations: [AssetTransferOperation] = operation == .finish
            ? [.begin, .chunk, .finish] : [operation]
        let observation = SharedDrainObservation()
        let validated = StartGate()
        let finalize = StartGate()
        let channel = ScriptedAssetChannel(
            holdClose       : true,
            holdSuccessAt   : afterValidation ? nil : operations.count,
            drainObservation: observation
        )
        let client = MessageAddonAssetClient(channel: channel)
        let mutation = Task {
            await MessageAddonAssetClient.$successFinalizationObserver.withValue({
                if afterValidation {
                    await validated.open()
                    await finalize.wait()
                }
            }) {
                await MessageAddonAssetClient.$drainWaitObserver.withValue({
                    observation.entered(.mutation)
                }) {
                    do {
                        switch operation {
                        case .finish:
                            _ = try await client.importAsset(
                                Data([1]),
                                publicationID: Self.publication
                            )
                        case .share:
                            _ = try await client.shareAsset(
                                try Self.sourceHandle(),
                                to: Self.publication
                            )
                        default:
                            try await client.releaseAsset(try Self.sourceHandle())
                        }
                        observation.returned(.mutation)
                        Issue.record("Explicit close must revoke successful mutation return authority.")
                    } catch {
                        // Record immediately on SDK return, before assertions or any actor hop.
                        observation.returned(.mutation)
                        #expect((error as? AddonFailure)?.code == .sessionRevoked)
                    }
                }
            }
        }
        if afterValidation { await validated.wait() }
        else { await channel.waitUntilHeld() }
        let firstClose = Task {
            await MessageAddonAssetClient.$drainWaitObserver.withValue({
                observation.entered(.firstClose)
            }) {
                await client.close()
                observation.returned(.firstClose)
            }
        }
        await channel.waitUntilCloseEntered()
        let secondClose = Task {
            await MessageAddonAssetClient.$drainWaitObserver.withValue({
                observation.entered(.secondClose)
            }) {
                await client.close()
                observation.returned(.secondClose)
            }
        }
        // The first two acknowledgements come from inside SDK drain(), after obtaining its
        // shared task. Starting a caller task alone is not evidence of participation.
        await observation.waitFor([.firstClose, .secondClose])
        await #expect(throws: AddonFailure.self) {
            try await client.releaseAsset(try Self.sourceHandle())
        }
        #expect(await channel.observedOperations == operations)
        #expect(await channel.didCloseComplete == false)
        if afterValidation { await finalize.open() }
        else { await channel.releaseHeld() }
        // Unlike the channel's success-returned event, this proves the mutation resumed in
        // the SDK and entered the same drain before physical completion is permitted.
        await observation.waitFor(Set(SharedDrainObservation.Caller.allCases))
        #expect(observation.returnedCallers.isEmpty)
        await #expect(throws: AddonFailure.self) {
            try await client.releaseAsset(try Self.sourceHandle())
        }
        #expect(await channel.observedOperations == operations)
        await channel.releaseClose()
        await mutation.value
        await firstClose.value
        await secondClose.value
        #expect(observation.callersAtPhysicalCompletion == [])
        #expect(observation.earlyReturns.isEmpty)
        #expect(observation.returnedCallers == Set(SharedDrainObservation.Caller.allCases))
        #expect(await channel.closeCount == 1)
        #expect(await channel.observedOperations == operations)
        #expect(await channel.observedSequences == Array(1...UInt64(operations.count)))
        let expectedEvents = afterValidation
            ? ["close-entered", "close-completed"]
            : ["close-entered", "success-returned", "close-completed"]
        #expect(await channel.events == expectedEvents)
        await client.close()
        #expect(await channel.closeCount == 1)
    }

#endif


    @Test(arguments: [AssetTransferOperation.finish, .share, .release])
    func finalizedSuccessPrecedesLaterExplicitClose(operation: AssetTransferOperation) async throws {
        let channel = ScriptedAssetChannel()
        let client = MessageAddonAssetClient(channel: channel)
        switch operation {
        case .finish:
            let handle = try await client.importAsset(Data([1]), publicationID: Self.publication)
            #expect(handle.publicationID == Self.publication)
        case .share:
            let handle = try await client.shareAsset(try Self.sourceHandle(), to: Self.publication)
            #expect(handle.publicationID == Self.publication)
        default:
            try await client.releaseAsset(try Self.sourceHandle())
        }
        #expect(await channel.closeCount == 0)
        await client.close()
        #expect(await channel.closeCount == 1)
        do {
            try await client.releaseAsset(try Self.sourceHandle())
            Issue.record("A later close must revoke future operations.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .sessionRevoked)
        }
        let expected: [AssetTransferOperation] = operation == .finish
            ? [.begin, .chunk, .finish] : [operation]
        #expect(await channel.observedOperations == expected)
    }

    @Test func closeDuringExchangeRevokesInFlightImport() async throws {
        let channel = ScriptedAssetChannel(
            gateExchange: true
        )
        let client = MessageAddonAssetClient(channel: channel)
        let task = Task {
            try await client.importAsset(
                Data(repeating: 1, count: 1_024),
                publicationID: Self.publication
            )
        }
        await channel.waitUntilBlocked()
        await client.close()
        await channel.release()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(await channel.closeCount == 1)
    }

    @Test func responseRequestIDMismatchPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .responseRequestIDMismatch)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
        // The mismatch irreversibly poisons the client: the next call never reaches the channel.
        let exchanges = await channel.observedSequences.count
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        #expect(await channel.observedSequences.count == exchanges)
    }

    @Test func chunkTransferIDMismatchPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .chunkTransferIDMismatch)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 1_024),
                publicationID: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
    }

    @Test func importAliasOwnerMismatchPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .importOwnerMismatch)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
    }

    @Test func importAliasPublicationMismatchPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .importPublicationMismatch)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
    }

    @Test func shareAliasOwnerMismatchPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .shareOwnerMismatch)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.shareAsset(
                try Self.sourceHandle(),
                to: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
    }

    @Test func shareAliasPublicationMismatchPoisonsAndCloses() async throws {
        let channel = ScriptedAssetChannel(mode: .sharePublicationMismatch)
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.shareAsset(
                try Self.sourceHandle(),
                to: Self.publication
            )
        }
        #expect(await channel.closeCount == 1)
    }

    @Test func generationShiftMidOperationPoisonsAndCloses() async throws {
        let channel = GenerationShiftingChannel()
        let client = MessageAddonAssetClient(channel: channel)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 1_024),
                publicationID: Self.publication
            )
        }
        // The stale physical generation was detected at the next boundary; the client never
        // retried the possibly completed begin on the new generation.
        #expect(channel.exchangeCount == 1)
        #expect(channel.closeCount == 1)
        await #expect(throws: AddonFailure.self) {
            _ = try await client.importAsset(
                Data(repeating: 1, count: 16),
                publicationID: Self.publication
            )
        }
        #expect(channel.exchangeCount == 1)
    }

    @Test func concurrentCloseCallersAwaitTheSameCompletedDrain() async throws {
        let channel = ScriptedAssetChannel(holdClose: true)
        let client = MessageAddonAssetClient(channel: channel)
        let first = Task {
            await client.close()
            await channel.recordCallerReturn()
        }
        await channel.waitUntilCloseEntered()
        #expect(await channel.closeCount == 1)
        let secondStarted = StartGate()
        let second = Task {
            await secondStarted.open()
            await client.close()
            await channel.recordCallerReturn()
        }
        await secondStarted.wait()
        // Let the second caller run into close while the drain is still physically held; a caller
        // that returns early would already have recorded its return here.
        for _ in 0..<200 { await Task.yield() }
        #expect(await channel.events == ["close-entered"])
        await channel.waitUntilCloseEntered()
        #expect(await channel.didCloseComplete == false)
        await channel.releaseClose()
        await first.value
        await second.value
        // Both callers returned only after the one physical drain actually completed.
        #expect(await channel.closeCount == 1)
        #expect(await channel.didCloseComplete == true)
        #expect(
            await channel.events == [
                "close-entered",
                "close-completed",
                "caller-returned",
                "caller-returned",
            ]
        )
        // Repeated close after completion stays a single shared drain.
        await client.close()
        #expect(await channel.closeCount == 1)
        #expect(await channel.events.count == 4)
    }

    @Test func poisonAndConcurrentCloseAwaitTheSameCompletedDrain() async throws {
        let channel = ScriptedAssetChannel(
            mode     : .transportErrorOnChunk,
            holdClose: true
        )
        let client = MessageAddonAssetClient(channel: channel)
        let importTask = Task {
            try await client.importAsset(
                Data(repeating: 1, count: 100_000),
                publicationID: Self.publication
            )
        }
        // The transport failure poisoned the client and its drain is physically held.
        await channel.waitUntilCloseEntered()
        #expect(await channel.closeCount == 1)
        let closeStarted = StartGate()
        let closeTask = Task {
            await closeStarted.open()
            await client.close()
            await channel.recordCallerReturn()
        }
        await closeStarted.wait()
        for _ in 0..<200 { await Task.yield() }
        #expect(await channel.events == ["close-entered"])
        await channel.waitUntilCloseEntered()
        #expect(await channel.didCloseComplete == false)
        await channel.releaseClose()
        await closeTask.value
        #expect(await channel.didCloseComplete == true)
        #expect(await channel.closeCount == 1)
        #expect(
            await channel.events == [
                "close-entered",
                "close-completed",
                "caller-returned",
            ]
        )
        await #expect(throws: AddonFailure.self) { try await importTask.value }
    }
}

/// GenerationShiftingChannel is a bounded canned channel that flips its physical generation
/// after the first exchange. It proves the SDK detects a stale physical generation at the very
/// next boundary and never retries a possibly completed mutation.
private final class GenerationShiftingChannel: AddonAssetMessageChannel, @unchecked Sendable {
    let profile: AssetTransferFrameProfile? = .v1

    private let lock = NSLock()
    private var currentGeneration = ConnectionGeneration()
    private var transferID: UUID?
    private var exchanges = 0
    private var closes = 0

    nonisolated var generation: ConnectionGeneration { lock.withLock { currentGeneration } }
    var exchangeCount: Int { lock.withLock { exchanges } }
    var closeCount: Int { lock.withLock { closes } }

    func exchange(_ frame: Data, sequence: UInt64) async throws -> Data {
        let request = try AssetTransferFrameCodec.decodeRequest(
            frame,
            profile: .v1
        )
        let response: AssetTransferResponse
        switch request.operation {
        case .begin:
            let id = UUID()
            lock.withLock { transferID = id }
            response = try AssetTransferResponse(
                requestID : request.requestID,
                operation : .begin,
                result    : .begun,
                transferID: id
            )
        case .chunk:
            let id = try #require(lock.withLock { transferID })
            response = try AssetTransferResponse(
                requestID : request.requestID,
                operation : .chunk,
                result    : .acknowledged,
                transferID: id,
                nextOffset: try #require(request.offset) + (try #require(request.bytes).count)
            )
        default:
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "GenerationShiftingChannel stops after the first exchange."
            )
        }
        let encoded = try AssetTransferFrameCodec.encode(
            response,
            profile: .v1
        )
        lock.withLock {
            exchanges += 1
            // The physical connection was replaced between the two frames.
            currentGeneration = ConnectionGeneration()
        }
        return encoded
    }

    func close() async {
        lock.withLock { closes += 1 }
    }
}

/// StartGate is a one-shot synchronization point so a test can cancel a task deterministically
/// before the client operation begins.
private actor StartGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// SharedDrainObservation records SDK entry and return without scheduling an actor job.
/// Only the test coordinator waits for observations; observed callers are never held here.
private final class SharedDrainObservation: @unchecked Sendable {
    enum Caller: CaseIterable, Hashable, Sendable {
        case firstClose, secondClose, mutation
    }

    private let lock = NSLock()
    private var participants: Set<Caller> = []
    private var returned: Set<Caller> = []
    private var premature: Set<Caller> = []
    private var completionSnapshot: Set<Caller>?
    private var awaitedParticipants: Set<Caller> = []
    private var waiter: CheckedContinuation<Void, Never>?

    var returnedCallers: Set<Caller> { lock.withLock { returned } }
    var earlyReturns: Set<Caller> { lock.withLock { premature } }
    var callersAtPhysicalCompletion: Set<Caller>? { lock.withLock { completionSnapshot } }

    func entered(_ caller: Caller) {
        let continuation = lock.withLock {
            participants.insert(caller)
            guard awaitedParticipants.isSubset(of: participants) else { return nil as CheckedContinuation<Void, Never>? }
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume()
    }

    func returned(_ caller: Caller) {
        lock.withLock {
            returned.insert(caller)
            if completionSnapshot == nil { premature.insert(caller) }
        }
    }

    func physicalCloseCompleted() {
        lock.withLock { completionSnapshot = returned }
    }

    /// waitFor acknowledges distinct callers, not invocation count: a mutation can rejoin
    /// drain during conclusion and must never stand in for a missing second close caller.
    func waitFor(_ callers: Set<Caller>) async {
        await withCheckedContinuation { continuation in
            let alreadyEntered = lock.withLock {
                if callers.isSubset(of: participants) { return true }
                precondition(waiter == nil, "Only one test coordinator may wait.")
                awaitedParticipants = callers
                waiter = continuation
                return false
            }
            if alreadyEntered { continuation.resume() }
        }
    }
}

/// ScriptedAssetChannel is a bounded canned channel for SDK-only tests. It records the exact
/// bounded exchange history and can physically hold one exchange or its close/drain so
/// cancellation and close coordination are deterministic rather than scheduling-dependent.
private actor ScriptedAssetChannel: AddonAssetMessageChannel {
    enum Mode: Sendable {
        case normal
        case transportErrorOnChunk
        case malformedReply
        case hostFailure(operation: AssetTransferOperation, code: AddonFailure.Code)
        case responseRequestIDMismatch
        case chunkTransferIDMismatch
        case importOwnerMismatch
        case importPublicationMismatch
        case shareOwnerMismatch
        case sharePublicationMismatch
    }

    nonisolated let generation = ConnectionGeneration()
    nonisolated let profile   : AssetTransferFrameProfile?

    private let mode        : Mode
    private let gateExchange: Bool
    private let holdAt      : Int?
    private let drainObservation: SharedDrainObservation?
    private let holdSuccessAt: Int?
    private let successReturned = StartGate()
    private let holdClose   : Bool
    private let abortFailureCode: AddonFailure.Code?
    private var blocked     = false
    private var exchangeIndex = 0
    private var transferID  : UUID?
    private var observedPublication: PublicationID?
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var holdArrived = false
    private var heldContinuation: CheckedContinuation<Void, Never>?
    private var heldRelease: CheckedContinuation<Void, Never>?
    private var closeEntered = false
    private var closeArrival: CheckedContinuation<Void, Never>?
    private var closeRelease: CheckedContinuation<Void, Never>?

    private(set) var observedSequences: [UInt64] = []
    private(set) var observedOperations: [AssetTransferOperation] = []
    private(set) var chunkSizes: [Int] = []
    private(set) var closeCount = 0
    private(set) var didCloseComplete = false
    private(set) var events: [String] = []

    init(
        profile     : AssetTransferFrameProfile? = .v1,
        mode        : Mode = .normal,
        gateExchange: Bool = false,
        holdAt      : Int? = nil,
        holdClose   : Bool = false,
        holdSuccessAt: Int? = nil,
        drainObservation: SharedDrainObservation? = nil,
        abortFailureCode: AddonFailure.Code? = nil
    ) {
        self.profile = profile
        self.mode = mode
        self.gateExchange = gateExchange
        self.drainObservation = drainObservation
        self.holdSuccessAt = holdSuccessAt
        self.holdAt = holdAt
        self.holdClose = holdClose
        self.abortFailureCode = abortFailureCode
    }

    // MARK: Test-only deterministic points

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { continuation in
            arrivalContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func waitUntilHeld() async {
        if holdArrived { return }
        await withCheckedContinuation { continuation in
            heldContinuation = continuation
        }
    }

    func releaseHeld() {
        heldRelease?.resume()
        heldRelease = nil
    }

    func waitUntilCloseEntered() async {
        if closeEntered { return }
        await withCheckedContinuation { continuation in
            closeArrival = continuation
        }
    }

    func waitUntilSuccessReturned() async {
        await successReturned.wait()
    }

    func releaseClose() {
        closeRelease?.resume()
        closeRelease = nil
    }

    func recordCallerReturn() {
        events.append("caller-returned")
    }

    // MARK: AddonAssetMessageChannel

    func exchange(_ frame: Data, sequence: UInt64) async throws -> Data {
        let request = try AssetTransferFrameCodec.decodeRequest(
            frame,
            profile: .v1
        )
        exchangeIndex += 1
        observedSequences.append(sequence)
        observedOperations.append(request.operation)
        if let bytes = request.bytes, request.operation == .chunk {
            chunkSizes.append(bytes.count)
        }
        if gateExchange, !blocked {
            blocked = true
            arrivalContinuation?.resume()
            arrivalContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        if let holdAt, holdAt == exchangeIndex {
            holdArrived = true
            heldContinuation?.resume()
            heldContinuation = nil
            await withCheckedContinuation { continuation in
                heldRelease = continuation
            }
        }
        if request.operation == .abort, let abortFailureCode {
            return try AssetTransferFrameCodec.encode(
                try AssetTransferResponse(
                    requestID    : request.requestID,
                    operation    : .abort,
                    result       : .failure,
                    failureCode  : abortFailureCode,
                    failureReason: "Scripted abort refusal."
                ),
                profile: .v1
            )
        }
        switch mode {
        case .normal:
            let encoded = try AssetTransferFrameCodec.encode(
                try response(for: request),
                profile: .v1
            )
            if holdSuccessAt == exchangeIndex {
                holdArrived = true
                heldContinuation?.resume()
                heldContinuation = nil
                await withCheckedContinuation { heldRelease = $0 }
                events.append("success-returned")
                await successReturned.open()
            }
            return encoded
        case .transportErrorOnChunk:
            if request.operation == .chunk {
                throw AddonFailure(
                    code  : .dependencyUnavailable,
                    reason: "Scripted transport failure."
                )
            }
            return try AssetTransferFrameCodec.encode(
                try response(for: request),
                profile: .v1
            )
        case .malformedReply:
            return Data([0xFF, 0x00, 0x01])
        case .responseRequestIDMismatch:
            return try AssetTransferFrameCodec.encode(
                try AssetTransferResponse(
                    requestID    : UUID(),
                    operation    : request.operation,
                    result       : .failure,
                    failureCode  : .invalidPayload,
                    failureReason: "Scripted correlation mismatch."
                ),
                profile: .v1
            )
        case .chunkTransferIDMismatch, .importOwnerMismatch, .importPublicationMismatch,
             .shareOwnerMismatch, .sharePublicationMismatch:
            return try AssetTransferFrameCodec.encode(
                try response(for: request),
                profile: .v1
            )
        case .hostFailure(let operation, let code):
            if request.operation == operation {
                return try AssetTransferFrameCodec.encode(
                    try AssetTransferResponse(
                        requestID    : request.requestID,
                        operation    : operation,
                        result       : .failure,
                        failureCode  : code,
                        failureReason: "Scripted host refusal."
                    ),
                    profile: .v1
                )
            }
            return try AssetTransferFrameCodec.encode(
                try response(for: request),
                profile: .v1
            )
        }
    }

    func close() async {
        closeCount += 1
        events.append("close-entered")
        if holdClose {
            closeEntered = true
            closeArrival?.resume()
            closeArrival = nil
            await withCheckedContinuation { continuation in
                closeRelease = continuation
            }
            closeRelease = nil
        }
        // The physical channel cannot finish disposal before the held exchange exits.
        if holdSuccessAt != nil { await successReturned.wait() }
        events.append("close-completed")
        didCloseComplete = true
        drainObservation?.physicalCloseCompleted()
    }

    private func response(for request: AssetTransferRequest) throws -> AssetTransferResponse {
        switch request.operation {
        case .begin:
            let id = UUID()
            transferID = id
            observedPublication = request.publicationID
            return try AssetTransferResponse(
                requestID : request.requestID,
                operation : .begin,
                result    : .begun,
                transferID: id
            )
        case .chunk:
            let id = try #require(transferID)
            let offset = try #require(request.offset)
            let count = try #require(request.bytes).count
            let acknowledgedID: UUID
            if case .chunkTransferIDMismatch = mode { acknowledgedID = UUID() } else { acknowledgedID = id }
            return try AssetTransferResponse(
                requestID : request.requestID,
                operation : .chunk,
                result    : .acknowledged,
                transferID: acknowledgedID,
                nextOffset: offset + count
            )
        case .finish:
            let id = try #require(transferID)
            let publication = try #require(observedPublication)
            let owner: AddonID
            let handlePublication: PublicationID
            switch mode {
            case .importOwnerMismatch:
                owner = try #require(AddonID(rawValue: "com.example.asset-other"))
                handlePublication = PublicationID(
                    addonID   : owner,
                    instanceID: UUID(),
                    sessionID : UUID()
                )
            case .importPublicationMismatch:
                owner = publication.addonID
                handlePublication = PublicationID(
                    addonID   : owner,
                    instanceID: UUID(),
                    sessionID : UUID()
                )
            default:
                owner = publication.addonID
                handlePublication = publication
            }
            return try AssetTransferResponse(
                requestID  : request.requestID,
                operation  : .finish,
                result     : .imported,
                transferID : id,
                assetHandle: try AssetHandle(
                    assetID       : "asset-" + UUID().uuidString,
                    owner         : owner,
                    publicationID : handlePublication,
                    rasterRevision: 1,
                    width         : 1,
                    height        : 1,
                    byteCount     : 4
                )
            )
        case .abort:
            return try AssetTransferResponse(
                requestID : request.requestID,
                operation : .abort,
                result    : .acknowledged,
                transferID: try #require(transferID)
            )
        case .share:
            let target = try #require(request.publicationID)
            let source = try #require(request.sourceHandle)
            let owner: AddonID
            let handlePublication: PublicationID
            switch mode {
            case .shareOwnerMismatch:
                owner = try #require(AddonID(rawValue: "com.example.asset-other"))
                handlePublication = PublicationID(
                    addonID   : owner,
                    instanceID: UUID(),
                    sessionID : UUID()
                )
            case .sharePublicationMismatch:
                owner = source.owner
                handlePublication = PublicationID(
                    addonID   : owner,
                    instanceID: UUID(),
                    sessionID : UUID()
                )
            default:
                owner = source.owner
                handlePublication = target
            }
            return try AssetTransferResponse(
                requestID  : request.requestID,
                operation  : .share,
                result     : .shared,
                assetHandle: try AssetHandle(
                    assetID       : "asset-" + UUID().uuidString,
                    owner         : owner,
                    publicationID : handlePublication,
                    rasterRevision: 1,
                    width         : 1,
                    height        : 1,
                    byteCount     : 4
                )
            )
        case .release:
            return try AssetTransferResponse(
                requestID: request.requestID,
                operation: .release,
                result   : .acknowledged
            )
        }
    }
}
