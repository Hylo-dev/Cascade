//
//  MessageAddonStorageIntegrationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// MessageAddonStorageIntegrationTests are real Swift runtime/POSIX storage tests, not
/// authentication or OS-exit qualification.
@Suite(.timeLimit(.minutes(1)))
struct MessageAddonStorageIntegrationTests {
    @Test(arguments: [1, 2])
    func realRoundTripConsumesExactReceiptsWithoutChangingStorageSyntax(minor: Int) async throws {
        try await withStorageHost(minor: minor) { host in
            #expect(host.connection.publicationConnection.negotiatedProtocol.minor == minor)
            #expect(host.channel.profile == .v1_1)
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                #expect(try await client.read(key: "missing") == nil)
                try await client.write(Data(), key: "empty")
                #expect(try await client.read(key: "empty") == Data())
                let full = Data(repeating: 255, count: 65_536)
                let key = String(repeating: "\u{1}", count: 256)
                try await client.write(full, key: key)
                #expect(try await client.read(key: key) == full)
                #expect(try host.diskValue(key: key) == full)
                try await client.write(Data([1]), key: "é")
                try await client.write(Data([2]), key: "e\u{301}")
                #expect(try await client.read(key: "é") == Data([1]))
                #expect(try await client.read(key: "e\u{301}") == Data([2]))
                try await client.remove(key: "é")
                #expect(try await client.read(key: "é") == nil)
                try await client.remove(key: "absent")
                #expect(host.adapter.receivedCount == 12)
                #expect(host.adapter.reply == nil && !host.adapter.hasIngress)
            }
        }
    }

    @Test(arguments: [StorageOperation.write, .remove])
    func committedMutationWithRejectedReplyIsUnknownToSDK(operation: StorageOperation) async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                try await client.write(Data([1]), key: "key")
                host.adapter.rejectReplies = true
                await storageIntegrationExpect(.outcomeUnknown) {
                    try await storageIntegrationCall(client, operation)
                }
                #expect(host.channel.lastResult == .completed(.acknowledged, .rejectedBeforeHandoff))
                #expect(try host.diskValue() == (operation == .write ? Data([7]) : nil))
                #expect(host.adapter.receivedCount == 1)
                #expect(host.adapter.reply == nil)
                #expect(host.channel.closeCount == 1)
                #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
            }
        }
    }

    @Test func realBackendErrorProducesExactUnknownResponseWithoutPoison() async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                try await client.write(Data([1]), key: "key")
                host.files.set(write: true)
                await storageIntegrationExpect(.outcomeUnknown) { try await client.write(Data([9]), key: "key") }
                host.files.set()
                #expect(host.channel.lastResult == .completed(.outcomeUnknown, .handedOff))
                #expect(host.channel.closeCount == 0)
                #expect(try await client.read(key: "key") == Data([1]))
                #expect(host.adapter.receivedCount == 3)
            }
        }
    }

    @Test func wrongReceiptsAndCompetingIngressCannotReleaseHeldReply() async throws {
        try await withStorageHost(minor: 2) { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                await host.channel.hold(.afterHandoff)
                let work = Task { try await client.write(Data([7]), key: "key") }
                await host.channel.gate.wait()
                let delivery = try #require(host.adapter.reply)
                let r = delivery.receipt
                let wrong = [
                    RuntimeStorageReceipt(token: UUID(), incarnation: r.incarnation, connectionToken: r.connectionToken,
                                          sequence: r.sequence, requestID: r.requestID, operation: r.operation),
                    RuntimeStorageReceipt(token: r.token, incarnation: RuntimeIncarnation(), connectionToken: r.connectionToken,
                                          sequence: r.sequence, requestID: r.requestID, operation: r.operation),
                    RuntimeStorageReceipt(token: r.token, incarnation: r.incarnation, connectionToken: UUID(),
                                          sequence: r.sequence, requestID: r.requestID, operation: r.operation),
                    RuntimeStorageReceipt(token: r.token, incarnation: r.incarnation, connectionToken: r.connectionToken,
                                          sequence: 2, requestID: r.requestID, operation: r.operation),
                    RuntimeStorageReceipt(token: r.token, incarnation: r.incarnation, connectionToken: r.connectionToken,
                                          sequence: r.sequence, requestID: UUID(), operation: r.operation),
                    RuntimeStorageReceipt(token: r.token, incarnation: r.incarnation, connectionToken: r.connectionToken,
                                          sequence: r.sequence, requestID: r.requestID, operation: .remove)
                ]
                for receipt in wrong {
                    #expect(await host.runtime.receiveStorageReceipt(receipt, connection: host.connection) == false)
                }
                #expect(await host.runtime.receiveAssetReceipt(
                    RuntimeAssetReceipt(token: r.token, incarnation: r.incarnation, connectionToken: r.connectionToken,
                                        sequence: r.sequence, requestID: r.requestID, operation: .begin),
                    connection: host.connection
                ) == false)
                #expect(host.adapter.reply == delivery)
                #expect(host.adapter.receivedCount == 0)
                let competing = try StorageFrameCodec.encode(
                    StorageRequest(requestID: UUID(), operation: .read, key: "key"), profile: .v1_1
                )
                let staged = try #require(host.adapter.stage(competing, sequence: 2, incarnation: host.connection.incarnation))
                let publication = try ProviderOutput(schemaVersion: 1, publications: [], operations: [],
                                                     completion: nil, checkpoint: nil)
                #expect(host.adapter.stagePublication(publication) == nil)
                #expect(host.adapter.stageAsset(Data([1]), sequence: 1) == nil)
                #expect(await host.runtime.receiveStorageRequest(staged, connection: host.connection) == .refused(.resourceDenied))
                #expect(host.adapter.reply == delivery)
                await host.channel.gate.release()
                try await work.value
                #expect(host.adapter.receivedCount == 1 && host.adapter.reply == nil)
                // A duplicate exact old receipt cannot free the newer accepted reply.
                let next = try #require(host.adapter.stage(competing, sequence: 2, incarnation: host.connection.incarnation))
                #expect(await host.runtime.receiveStorageRequest(next, connection: host.connection) == .completed(.value, .handedOff))
                let newer = try #require(host.adapter.reply)
                #expect(await host.runtime.receiveStorageReceipt(r, connection: host.connection) == false)
                #expect(host.adapter.reply == newer)
                #expect(await host.runtime.receiveStorageReceipt(newer.receipt, connection: host.connection))
                #expect(host.adapter.receivedCount == 2)
            }
        }
    }

    @Test(arguments: [StorageOperation.read, .write, .remove])
    func cancellationBeforeConsumeDrainsRealCommittedResponse(operation: StorageOperation) async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                try await client.write(Data([1]), key: "key")
                await host.channel.hold(.afterHandoff)
                let work = Task { try await storageIntegrationCall(client, operation) }
                await host.channel.gate.wait()
                #expect(host.adapter.reply != nil)
                #expect(try host.diskValue() == (operation == .remove ? nil : Data([operation == .write ? 7 : 1])))
                work.cancel()
                await storageIntegrationExpect(.resourceDenied) { try await client.remove(key: "busy") }
                await host.channel.gate.release()
                if operation == .read {
                    await #expect(throws: CancellationError.self) { try await work.value }
                } else {
                    await storageIntegrationExpect(.outcomeUnknown) { try await work.value }
                }
                #expect(host.adapter.receivedCount == 2)
                #expect(host.adapter.reply == nil && host.channel.closeCount == 0)
                #expect(try await client.read(key: "key") == (operation == .remove ? nil : Data([operation == .write ? 7 : 1])))
            }
        }
    }

    @Test(arguments: [false, true])
    func closeDrainsRealHeldExchangeWithoutObservingProcessExit(afterHandoff: Bool) async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                await host.channel.hold(afterHandoff ? .afterHandoff : .beforeReceive)
                let work = Task { try await client.write(Data([7]), key: "key") }
                await host.channel.gate.wait()
                work.cancel()
                async let first: Void = client.close()
                async let second: Void = client.close()
                _ = await (first, second)
                await storageIntegrationExpect(.outcomeUnknown) { try await work.value }
                #expect(host.channel.closeCount == 1 && host.channel.didDrain)
                #expect(host.adapter.reply == nil && !host.adapter.hasIngress)
                #expect(host.adapter.stopCount == 1)
                #expect(try host.diskValue() == (afterHandoff ? Data([7]) : nil))
                #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
                #expect(await host.runtime.diagnostics(owner: host.owner)?.hasProcess == true)
                await storageIntegrationExpect(.sessionRevoked) { _ = try await client.read(key: "key") }
            }
        }
    }

#if DEBUG
    @Test func sdkEmbeddingRefusesBeforeEncodingAtExhaustedBudget() async throws {
        try await withStorageHost { host in
            let memory = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
            let filler = try await host.governor.admit(.temporaryMemory(bytes: 128 * 1_024 * 1_024 - memory), owner: host.owner)
            let observation = StorageScopeObservation()
            await storageIntegrationExpect(.resourceDenied) {
                try await MessageAddonStorageClient.$encodingObserver.withValue({ observation.encoded() }) {
                    try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                        observation.entered()
                        try await client.write(Data([7]), key: "key")
                    }
                }
            }
            #expect(observation.counts == [0, 0])
            #expect(host.channel.exchangeCount == 0 && host.adapter.takeCount == 0)
            try await host.governor.release(filler.id, owner: host.owner)
            // This is embedding admission evidence, not a quota check inside the public client.
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in try await client.write(Data([7]), key: "key") }
        }
    }
#endif

    @Test func protectedSDKScopeSurvivesModeledExitAndOwnerRelease() async throws {
        try await withStorageHost { host in
            let beforeSDK = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                let inSDK = await host.governor.usage(.admittedMemoryBytes, owner: host.owner)
                #expect(inSDK == beforeSDK + 8 * 1_024 * 1_024)
                await host.channel.hold(.afterHandoff)
                let work = Task { try await client.write(Data([7]), key: "key") }
                await host.channel.gate.wait()
                // Modeled trusted runtime input, not a physical death observation by the channel.
                await host.runtime.observeExit(host.connection.incarnation)
                await host.governor.releaseAll(owner: host.owner)
                #expect(await host.governor.usage(.providers, owner: host.owner) == 0)
                #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) >= 8 * 1_024 * 1_024 + 16_384)
                #expect(try host.diskValue() == Data([7]))
                await host.channel.gate.release()
                await storageIntegrationExpect(.outcomeUnknown) { try await work.value }
                #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) >= 8 * 1_024 * 1_024 + 16_384)
            }
            #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) < 8 * 1_024 * 1_024)
        }
    }

    // An ungranted declared permission blocks resolution before a connection can be injected;
    // existing declaredPermissionNeedsGrantAndResolverCannotAdvertiseMissingImplementation
    // supplies that adjacent real-runtime check. Do not fabricate an attached ungranted peer.
    @Test(arguments: [0, 2])
    func canonicalAuthorityCannotBeManufacturedByByteClient(mode: Int) async throws {
        try await withStorageHost(declared: mode != 0, granted: mode != 1, ready: mode != 2) { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                await storageIntegrationExpect(.dependencyUnavailable) { _ = try await client.read(key: "key") }
                #expect(host.adapter.takeCount == 0)
                #expect(host.channel.lastResult == .refused(mode == 2 ? .dependencyUnavailable : .permissionDenied))
                #expect(host.adapter.receivedCount == 0)
            }
        }
    }

    @Test(arguments: [false, true], [0, 1, 2])
    func realBackendSuspensionKeepsProtectedWorkThroughCancellationOrRevocation(
        committed: Bool,
        terminal: Int
    ) async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                try await client.write(Data([1]), key: "key")
                await host.backendGate.arm(committed ? .release : .temporary, skipping: committed ? 1 : 0)
                let work = Task { try await client.write(Data([7]), key: "key") }
                await host.backendGate.wait()
                do { #expect(try host.diskValue() == Data([committed ? 7 : 1])) }
                catch {
                    await host.backendGate.resume(); _ = try? await work.value
                    throw error
                }
                var closing: Task<Void, Never>?
                if terminal == 0 { work.cancel() }
                else if terminal == 1 {
                    closing = Task { await client.close() }
                    await host.channel.closeEntered.wait()
                } else { await host.runtime.disable(owner: host.owner) }
                // Both SDK and host scopes are still live; stop/releaseAll cannot refund them.
                #expect(await host.governor.usage(.admittedMemoryBytes, owner: host.owner) >= 16 * 1_024 * 1_024 + 16_384)
                await host.backendGate.resume()
                await storageIntegrationExpect(.outcomeUnknown) { try await work.value }
                await closing?.value
                #expect(try host.diskValue() == Data([7]))
                #expect(host.channel.lastResult == .completed(.acknowledged, terminal == 0 ? .handedOff : .suppressed))
                #expect(host.adapter.receivedCount == (terminal == 0 ? 2 : 1))
                #expect(host.adapter.reply == nil && !host.adapter.hasIngress)
                #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
            }
        }
    }

#if DEBUG
    @Test(arguments: [StorageOperation.read, .write, .remove], [false, true])
    func consumedRealReceiptOrdersLateCancellationAndExplicitClose(
        operation: StorageOperation,
        close: Bool
    ) async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                let consumed = StorageBridgeGate()
                let work = Task {
                    try await MessageAddonStorageClient.$consumedObserver.withValue({ await consumed.hold() }) {
                        try await storageIntegrationCall(client, operation)
                    }
                }
                await consumed.wait()
                #expect(host.adapter.receivedCount == 1 && host.adapter.reply == nil)
                if close { await client.close() } else { work.cancel() }
                await consumed.release()
                if close { await storageIntegrationExpect(.sessionRevoked) { try await work.value } }
                else { try await work.value }
                #expect(host.channel.closeCount == (close ? 1 : 0))
                #expect(try host.diskValue() == (operation == .write ? Data([7]) : nil))
            }
        }
    }
#endif

    @Test(arguments: [false, true])
    func physicalReplyFaultDrainsWithoutFabricatingReceiptOrRejection(wrongNonce: Bool) async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                host.channel.armFault(wrongNonce: wrongNonce)
                await storageIntegrationExpect(.outcomeUnknown) { try await client.write(Data([7]), key: "key") }
                #expect(try host.diskValue() == Data([7]))
                #expect(host.channel.lastResult == .completed(.acknowledged, .handedOff))
                #expect(host.channel.closeCount == 1 && host.adapter.receivedCount == 0)
                #expect(host.adapter.reply == nil && !host.adapter.hasIngress)
                #expect(await host.governor.usage(.providers, owner: host.owner) == 1)
            }
        }
    }

    @Test func staleBridgeCloseCannotRevokeReplacementStorageTraffic() async throws {
        try await withStorageHost { host in
            try await host.withSDK { (client: MessageAddonStorageClient) async throws -> Void in
                try await client.write(Data([7]), key: "key")
                // Modeled old-process exit permits a replacement; close is not that observation.
                await host.runtime.observeExit(host.connection.incarnation)
                let launch = try await host.runtime.requestLaunch(owner: host.owner)
                let replacement = try await host.runtime.attach(launchID: launch,
                    offer: ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 1, contentSchemas: [1]))
                let bridge = StorageRuntimeByteBridge(runtime: host.runtime, adapter: host.adapter, connection: replacement)
                let next = try MessageAddonStorageClient(channel: bridge)
                do {
                    let stale = StorageRuntimeByteBridge(runtime: host.runtime, adapter: host.adapter,
                                                         connection: host.connection)
                    let frame = try StorageFrameCodec.encode(
                        StorageRequest(requestID: UUID(), operation: .write, key: "key", value: Data([99])),
                        profile: .v1_1)
                    let takes = host.adapter.takeCount
                    do {
                        let result = try await stale.exchange(frame, sequence: 1)
                        if case .rejectedBeforeHandoff = result {} else { Issue.record("Stale staging was admitted") }
                    } catch {
                        Issue.record("Stale staging must establish request rejection before host processing: \(error)")
                    }
                    await stale.close()
                    #expect(host.adapter.takeCount == takes)
                    await host.channel.close()
                    await host.channel.close()
                    #expect(host.adapter.stopCount == 0)
                    #expect(try await next.read(key: "key") == Data([7]))
                    try await next.write(Data([9]), key: "key")
                    #expect(try await next.read(key: "key") == Data([9]))
                } catch {
                    await next.close()
                    await host.runtime.observeExit(replacement.incarnation)
                    throw error
                }
                await next.close()
                // Explicit replacement-fixture cleanup, not observed death inferred by the SDK.
                await host.runtime.observeExit(replacement.incarnation)
                #expect(host.adapter.stopCount == 1)
                #expect(try host.diskValue() == Data([9]))
            }
        }
    }
}

private func storageIntegrationCall(_ client: MessageAddonStorageClient, _ operation: StorageOperation) async throws {
    switch operation {
    case .read: _ = try await client.read(key: "key")
    case .write: try await client.write(Data([7]), key: "key")
    case .remove: try await client.remove(key: "key")
    }
}

private func storageIntegrationExpect(_ code: AddonFailure.Code, _ body: () async throws -> Void) async {
    do { try await body(); Issue.record("Expected \(code.rawValue)") }
    catch { #expect((error as? AddonFailure)?.code == code) }
}

/// withStorageHost keeps fixture control paid through cleanup; SDK results never escape its
/// nested paid scope.
private func withStorageHost(
    minor: Int = 1, declared: Bool = true, granted: Bool = true, ready: Bool = true,
    _ body: @Sendable (StorageMessageHost) async throws -> Void
) async throws {
    let action = try ActionFixture()
    let governor = ResourceGovernor()
    try await governor.withAssetDecodeReservation(bytes: 16_384, owner: action.owner) {
        let host = try await StorageMessageHost.make(action: action, governor: governor, minor: minor,
                                                     declared: declared, granted: granted, ready: ready)
        do { try await body(host) }
        catch { await host.cleanup(); throw error }
        await host.cleanup()
    }
}
