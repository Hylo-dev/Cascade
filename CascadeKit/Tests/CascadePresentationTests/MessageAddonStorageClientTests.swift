//
//  MessageAddonStorageClientTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

@Suite(.timeLimit(.minutes(1)))
struct MessageAddonStorageClientTests {
    @Test func roundTripPreservesMissingEmptyAndByteKeys() async throws {
        let channel = StorageScriptChannel()
        let client = try MessageAddonStorageClient(channel: channel)
        #expect(try await client.read(key: "missing") == nil)
        try await client.write(Data(), key: "empty")
        #expect(try await client.read(key: "empty") == Data())
        try await client.write(Data([1]), key: "é")
        try await client.write(Data([2]), key: "e\u{301}")
        #expect(try await client.read(key: "é") == Data([1]))
        #expect(try await client.read(key: "e\u{301}") == Data([2]))
        try await client.remove(key: "é")
        #expect(try await client.read(key: "é") == nil)
        try await client.remove(key: "missing")
        let records = await channel.records
        #expect(records.map(\.sequence) == Array(1...10).map(UInt64.init))
        #expect(Set(records.map { $0.request.requestID }).count == 10)
        await client.close()
    }

    @Test func exactHostFailureIsNotPoisonOrMissing() async throws {
        let channel = StorageScriptChannel(fault: .host(.permissionDenied))
        let client = try MessageAddonStorageClient(channel: channel)
        await storageExpect(.permissionDenied) { _ = try await client.read(key: "key") }
        #expect(await channel.closeCount == 0)
        try await client.write(Data([7]), key: "key")
        #expect(try await client.read(key: "key") == Data([7]))
        await channel.arm(.host(.outcomeUnknown))
        await storageExpect(.outcomeUnknown) { try await client.remove(key: "key") }
        #expect(await channel.closeCount == 0)
        #expect(try await client.read(key: "key") == Data([7]))
        await client.close()
    }

    @Test func provenRequestRejectionDiffersFromGenericFailure() async throws {
        let channel = StorageScriptChannel(fault: .reject)
        let client = try MessageAddonStorageClient(channel: channel)
        await storageExpect(.dependencyUnavailable) { try await client.write(Data([1]), key: "key") }
        #expect(await channel.closeCount == 0)
        try await client.write(Data([2]), key: "key")
        #expect(await channel.records.map(\.sequence) == [1, 2])
        await channel.arm(.transport)
        await storageExpect(.outcomeUnknown) { try await client.remove(key: "key") }
        #expect(await channel.closeCount == 1)
        await storageExpect(.sessionRevoked) { try await client.write(Data([3]), key: "key") }
        #expect(await channel.records.count == 3)
        await client.close()
        #expect(await channel.closeCount == 1)
    }

    @Test func unsupportedProfileAndInvalidArgumentsNeverExchange() async throws {
        let unsupported = StorageScriptChannel(profile: nil)
        #expect(throws: AddonFailure.self) { _ = try MessageAddonStorageClient(channel: unsupported) }
        #expect(await unsupported.records.isEmpty)
        let channel = StorageScriptChannel()
        let client = try MessageAddonStorageClient(channel: channel)
        for key in ["", "a\u{0}b", String(repeating: "x", count: 257)] {
            await storageExpect(.invalidPayload) { _ = try await client.read(key: key) }
        }
        await storageExpect(.invalidPayload) {
            try await client.write(Data(repeating: 0, count: 65_537), key: "key")
        }
        #expect(await channel.records.isEmpty)
        let key = String(repeating: "\u{1}", count: 256)
        let value = Data(repeating: 255, count: 65_536)
        try await client.write(value, key: key)
        #expect(try await client.read(key: key) == value)
        #expect(await channel.records.allSatisfy { $0.encodedBytes <= 196_608 })
        await client.close()
    }

    @Test(arguments: [StorageOperation.read, .write, .remove],
          [StorageScriptChannel.Fault.malformed, .oversized, .wrongID, .wrongOperation, .transport])
    fileprivate func unusableRepliesPoisonWithoutInventingMutationRefusal(
        operation: StorageOperation,
        fault: StorageScriptChannel.Fault
    ) async throws {
        let channel = StorageScriptChannel(fault: fault)
        let client = try MessageAddonStorageClient(channel: channel)
        let expected: AddonFailure.Code = operation == .read
            ? (fault == .transport ? .dependencyUnavailable : .invalidPayload) : .outcomeUnknown
        await storageExpect(expected) { try await storageCall(client, operation) }
        #expect(await channel.closeCount == 1)
        await storageExpect(.sessionRevoked) { _ = try await client.read(key: "later") }
        #expect(await channel.records.count == 1)
        await client.close()
    }

    @Test(arguments: [StorageOperation.read, .write, .remove])
    func cancellationBeforeAdmissionSendsNothing(operation: StorageOperation) async throws {
        let channel = StorageScriptChannel()
        let client = try MessageAddonStorageClient(channel: channel)
        let start = StorageTestGate()
        let task = Task {
            await start.hold()
            try await storageCall(client, operation)
        }
        await start.wait()
        task.cancel()
        await start.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await channel.records.isEmpty)
        await client.close()
    }

#if DEBUG
    @Test(arguments: [false, true])
    func preparedChannelDriftCannotStartHandoff(profileDrift: Bool) async throws {
        let channel = StorageDriftingChannel(profileDrift: profileDrift)
        let client = try MessageAddonStorageClient(channel: channel)
        let prepared = StorageTestGate()
        let work = Task {
            try await MessageAddonStorageClient.$preparedObserver.withValue({ await prepared.hold() }) {
                try await client.write(Data([7]), key: "key")
            }
        }
        await prepared.wait()
        channel.shift()
        await prepared.release()
        await storageExpect(.sessionRevoked) { try await work.value }
        #expect(await channel.inner.records.isEmpty)
        await client.close()
    }

    @Test(arguments: [StorageOperation.read, .write, .remove])
    func cancellationThenProvenRejectionNeverCompletesTwice(operation: StorageOperation) async throws {
        let physical = StorageTestGate()
        let channel = StorageScriptChannel(fault: .reject, exchangeGate: physical)
        let client = try MessageAddonStorageClient(channel: channel)
        let work = Task { try await storageCall(client, operation) }
        await physical.wait()
        work.cancel()
        // Busy admission precedes argument validation, even for an invalid next key.
        await storageExpect(.resourceDenied) { _ = try await client.read(key: "") }
        await physical.release()
        if operation == .read {
            await #expect(throws: CancellationError.self) { try await work.value }
        } else { await storageExpect(.outcomeUnknown) { try await work.value } }
        try await client.remove(key: "later")
        #expect(await channel.records.map(\.sequence) == [1, 2])
        #expect(await channel.closeCount == 0)
        await client.close()
    }

    @Test func poisonAndConcurrentCloseAwaitOneRealDrain() async throws {
        let closing = StorageTestGate()
        let observations = StorageDrainObservation()
        let channel = StorageScriptChannel(fault: .transport, closeGate: closing)
        let client = try MessageAddonStorageClient(channel: channel)
        let work = Task {
            await MessageAddonStorageClient.$drainWaitObserver.withValue({ observations.enter(0) }) {
                await storageExpect(.outcomeUnknown) { try await client.write(Data([7]), key: "key") }
                observations.returned(0)
            }
        }
        await closing.wait()
        let first = Task {
            await MessageAddonStorageClient.$drainWaitObserver.withValue({ observations.enter(1) }) {
                await client.close(); observations.returned(1)
            }
        }
        let second = Task {
            await MessageAddonStorageClient.$drainWaitObserver.withValue({ observations.enter(2) }) {
                await client.close(); observations.returned(2)
            }
        }
        await observations.waitForAll()
        #expect(observations.returnedCount == 0)
        #expect(await channel.closeCount == 1)
        await storageExpect(.sessionRevoked) { try await client.remove(key: "closed") }
        await closing.release()
        await work.value; await first.value; await second.value
        #expect(observations.returnedCount == 3)
    }

    @Test(arguments: [StorageOperation.read, .write, .remove])
    func preparedCancellationLeavesSequenceGap(operation: StorageOperation) async throws {
        let channel = StorageScriptChannel()
        let client = try MessageAddonStorageClient(channel: channel)
        let prepared = StorageTestGate()
        let task = Task {
            try await MessageAddonStorageClient.$preparedObserver.withValue({ await prepared.hold() }) {
                try await storageCall(client, operation)
            }
        }
        await prepared.wait()
        task.cancel()
        await prepared.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await channel.records.isEmpty)
        try await client.remove(key: "later")
        #expect(await channel.records.map(\.sequence) == [2])
        await client.close()
    }

    @Test(arguments: [StorageOperation.read, .write, .remove], [false, true])
    func cancellationAndConsumeAreOrdered(
        operation: StorageOperation,
        consumedFirst: Bool
    ) async throws {
        let physical = StorageTestGate()
        let consumed = StorageTestGate()
        let channel = StorageScriptChannel(exchangeGate: consumedFirst ? nil : physical)
        let client = try MessageAddonStorageClient(channel: channel)
        let task = Task {
            try await MessageAddonStorageClient.$consumedObserver.withValue({
                if consumedFirst { await consumed.hold() }
            }) { try await storageCall(client, operation) }
        }
        if consumedFirst { await consumed.wait() } else { await physical.wait() }
        task.cancel()
        await storageExpect(.resourceDenied) { try await client.remove(key: "busy") }
        #expect(await channel.records.count == 1)
        if consumedFirst { await consumed.release() } else { await physical.release() }
        if consumedFirst { try await task.value }
        else if operation == .read {
            await #expect(throws: CancellationError.self) { try await task.value }
        } else {
            await storageExpect(.outcomeUnknown) { try await task.value }
        }
        #expect(await channel.closeCount == 0)
        try await client.remove(key: "later")
        #expect(await channel.records.map(\.sequence) == [1, 2])
        await client.close()
    }

    @Test(arguments: [StorageOperation.read, .write, .remove], [false, true])
    func closeAfterValidationRetainsSlotThroughSharedPhysicalDrain(
        operation: StorageOperation,
        consumedFirst: Bool
    ) async throws {
        let physical = StorageTestGate()
        let consumed = StorageTestGate()
        let closing = StorageTestGate()
        let observations = StorageDrainObservation()
        let channel = StorageScriptChannel(
            exchangeGate: consumedFirst ? nil : physical,
            closeGate: closing
        )
        let client = try MessageAddonStorageClient(channel: channel)
        let work = Task {
            await MessageAddonStorageClient.$drainWaitObserver.withValue({ observations.enter(0) }) {
                await MessageAddonStorageClient.$consumedObserver.withValue({
                    if consumedFirst { await consumed.hold() }
                }) {
                    do {
                        try await storageCall(client, operation)
                        Issue.record("Revoked operation must not return success")
                    } catch {
                        let expected: AddonFailure.Code = consumedFirst || operation == .read
                            ? .sessionRevoked : .outcomeUnknown
                        #expect((error as? AddonFailure)?.code == expected)
                    }
                    observations.returned(0)
                }
            }
        }
        if consumedFirst { await consumed.wait() } else { await physical.wait() }
        let first = Task {
            await MessageAddonStorageClient.$drainWaitObserver.withValue({ observations.enter(1) }) {
                await client.close()
                observations.returned(1)
            }
        }
        await closing.wait()
        let second = Task {
            await MessageAddonStorageClient.$drainWaitObserver.withValue({ observations.enter(2) }) {
                await client.close()
                observations.returned(2)
            }
        }
        if consumedFirst { await consumed.release() }
        // close releases the physical hold, then the SDK operation joins the same drain.
        await observations.waitForAll()
        #expect(observations.returnedCount == 0)
        #expect(await channel.closeCount == 1)
        await storageExpect(.sessionRevoked) { try await client.remove(key: "closed") }
        #expect(await channel.records.count == 1)
        await closing.release()
        await work.value
        await first.value
        await second.value
        #expect(observations.returnedCount == 3)
        await client.close()
        #expect(await channel.closeCount == 1)
    }

    @Test(arguments: [StorageOperation.read, .write, .remove])
    func finalizedResultPrecedesLaterClose(operation: StorageOperation) async throws {
        let channel = StorageScriptChannel()
        let client = try MessageAddonStorageClient(channel: channel)
        try await storageCall(client, operation)
        await client.close()
        await storageExpect(.sessionRevoked) { try await storageCall(client, operation) }
        #expect(await channel.records.count == 1)
    }
#endif
}

private func storageCall(_ client: MessageAddonStorageClient, _ operation: StorageOperation) async throws {
    switch operation {
    case .read: _ = try await client.read(key: "key")
    case .write: try await client.write(Data([7]), key: "key")
    case .remove: try await client.remove(key: "key")
    }
}

private func storageExpect(
    _ code: AddonFailure.Code,
    _ operation: () async throws -> Void
) async {
    do { try await operation(); Issue.record("Expected \(code.rawValue)") }
    catch { #expect((error as? AddonFailure)?.code == code) }
}
