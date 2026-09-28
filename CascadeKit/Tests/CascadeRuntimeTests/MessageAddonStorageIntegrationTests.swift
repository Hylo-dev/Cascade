//
//  MessageAddonStorageIntegrationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// These are real Swift runtime/POSIX storage tests, not authentication or OS-exit qualification.
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

private final class StorageScopeObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var entries = 0
    private var encodings = 0
    var counts: [Int] { lock.withLock { [entries, encodings] } }
    func entered() { lock.withLock { entries += 1 } }
    func encoded() { lock.withLock { encodings += 1 } }
}

/// Fixture control remains paid through cleanup; SDK results never escape its nested paid scope.
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

private struct StorageMessageHost: Sendable {
    let root: URL
    let keyedRoot: URL
    let owner: AddonID
    let identity: VerifiedAddonIdentity
    let governor: ResourceGovernor
    let storage: AddonStorageCoordinator
    let files: KeyedFileFaults
    let backendGate: KeyedResourceGate
    let runtime: AddonRuntime
    let adapter: StorageMessageAdapter
    let connection: RuntimeConnection
    let channel: StorageRuntimeByteBridge

    static func make(action: ActionFixture, governor: ResourceGovernor, minor: Int,
                     declared: Bool, granted: Bool, ready: Bool) async throws -> Self {
        let root = URL(fileURLWithPath: "/private/tmp/cascade-storage-client-\(UUID())")
        let keyed = root.appendingPathComponent("keyed")
        let checkpoint = root.appendingPathComponent("checkpoint")
        let archive = root.appendingPathComponent("archive")
        let adapter = StorageMessageAdapter()
        var rollbackStorage: AddonStorageCoordinator?
        var rollbackRuntime: AddonRuntime?
        do {
            for directory in [root, keyed, checkpoint, archive] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                         attributes: [.posixPermissions: 0o700])
            }
            let installed = try replacing(action.context().installed, permissions: declared
                ? [AddonPermission(id: .storageOwn, scope: .addon)] : [])
            let files = KeyedFileFaults()
            let backendGate = KeyedResourceGate(governor)
            let storage = try await AddonStorageCoordinator.make(
                checkpointRoot: checkpoint, keyedRoot: keyed, archiveRoot: archive,
                registrations: [StateRegistration(identity: installed.verifiedIdentity, maximumSchemaVersion: 1)],
                governor: governor, resourceAccess: backendGate, keyedFileOperations: files
            )
            rollbackStorage = storage
            if ready { try await storage.start() }
            let runtime = try await AddonRuntime.make(
                catalog: [installed],
                environment: HostEnvironment(osVersion: SemanticVersion(14, 0, 0), hostCapabilities: [:],
                                             applications: [:], grants: [action.owner: granted ? ["storage.own"] : []],
                                             explicitBindings: [], protocolVersion: (1, minor)),
                governor: governor, adapter: adapter,
                clock: FixedRuntimeClock(instant: RuntimeInstant(wall: action.wall, monotonic: .zero)),
                storageCoordinator: storage
            )
            rollbackRuntime = runtime
            _ = try await runtime.assignPublication(owner: action.owner, featureID: "controls", instanceID: UUID())
            let launch = try await runtime.requestLaunch(owner: action.owner)
            let connection = try await runtime.attach(launchID: launch,
                offer: ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: minor, contentSchemas: [1]))
            return Self(root: root, keyedRoot: keyed, owner: action.owner, identity: installed.verifiedIdentity,
                        governor: governor, storage: storage, files: files, backendGate: backendGate, runtime: runtime,
                        adapter: adapter, connection: connection,
                        channel: StorageRuntimeByteBridge(runtime: runtime, adapter: adapter, connection: connection))
        } catch {
            await rollbackRuntime?.stop()
            if let incarnation = adapter.incarnation {
                // Explicit modeled cleanup for a partially constructed test fixture.
                await rollbackRuntime?.observeExit(incarnation)
            }
            _ = try? await rollbackStorage?.close()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func withSDK(_ body: @Sendable (MessageAddonStorageClient) async throws -> Void) async throws {
        try await governor.withAssetDecodeReservation(bytes: 8 * 1_024 * 1_024, owner: owner) {
            let client = try MessageAddonStorageClient(channel: channel)
            do { try await body(client) }
            catch { await client.close(); throw error }
            await client.close()
            // No Data, request/response DTO, client or physical-work task is returned from here.
        }
    }
    func diskValue(key: String = "key") throws -> Data? {
        let file = try AddonKeyedStorageTests.valueFile(keyedRoot, identity: identity, key: key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try KeyedStorageRecord.decode(Data(contentsOf: file), key: Data(key.utf8),
                                             namespace: KeyedStorageRecord.namespaceDigest(identity), storageClass: .data).value
    }
    func cleanup() async {
        await channel.close()
        await runtime.stop()
        // Explicitly modeled cleanup input; close itself never refunds an unobserved process.
        await runtime.observeExit(connection.incarnation)
        _ = try? await storage.close()
        try? FileManager.default.removeItem(at: root)
    }
}

/// A single current incarnation, typed ingress and delivery; all mutable access uses this lock.
/// Capacity comes only from the real runtime's prepaid start delivery. No receipt history/queue.
private final class StorageMessageAdapter: AddonRuntimeStorageAdapter, AddonRuntimeAssetAdapter, @unchecked Sendable {
    private enum Handle: Equatable {
        case storage(RuntimeStorageIngressHandle)
        case asset(RuntimeAssetIngressHandle)
        case publication(RuntimeIngressHandle)
    }
    private enum Input {
        case storage(RuntimeStorageIngressHandle, Data)
        case asset(RuntimeAssetIngressHandle, Data)
        case publication(RuntimeIngressHandle, ProviderOutput)
        var handle: Handle {
            switch self {
            case .storage(let h, _): .storage(h)
            case .asset(let h, _): .asset(h)
            case .publication(let h, _): .publication(h)
            }
        }
    }
    private let lock = NSLock()
    private var start: RuntimeStartDelivery?
    private var stopped = false
    private var input: Input?
    private var transferred = false
    private var output: RuntimeAdapterDelivery?
    private var reject = false
    private var receipts = 0
    private var takes = 0
    private var stops = 0
    var rejectReplies: Bool {
        get { lock.withLock { reject } }
        set { lock.withLock { reject = newValue } }
    }
    var incarnation: RuntimeIncarnation? { lock.withLock { start?.incarnation } }
    var receivedCount: Int { lock.withLock { receipts } }
    var takeCount: Int { lock.withLock { takes } }
    var stopCount: Int { lock.withLock { stops } }
    var hasIngress: Bool { lock.withLock { input != nil } }
    var reply: RuntimeStorageResponseDelivery? {
        lock.withLock {
            if case .storageResponse(let value) = output { return value }
            return nil
        }
    }
    func stage(_ bytes: Data, sequence: UInt64, incarnation: RuntimeIncarnation) -> RuntimeStorageIngressHandle? {
        lock.withLock {
            guard let start, incarnation == start.incarnation, !stopped, input == nil, !bytes.isEmpty,
                  bytes.count <= start.maximumStorageIngressBytes else { return nil }
            let h = RuntimeStorageIngressHandle(token: UUID(), incarnation: start.incarnation,
                                                encodedBytes: bytes.count, sequence: sequence)
            input = .storage(h, bytes.withUnsafeBytes { Data($0) }); transferred = false
            return h
        }
    }
    func stageAsset(_ bytes: Data, sequence: UInt64) -> RuntimeAssetIngressHandle? {
        lock.withLock {
            guard let start, !stopped, input == nil, !bytes.isEmpty,
                  bytes.count <= start.maximumAssetIngressBytes else { return nil }
            let h = RuntimeAssetIngressHandle(token: UUID(), incarnation: start.incarnation,
                                              encodedBytes: bytes.count, sequence: sequence)
            input = .asset(h, bytes.withUnsafeBytes { Data($0) }); transferred = false
            return h
        }
    }
    func stagePublication(_ value: ProviderOutput) -> RuntimeIngressHandle? {
        lock.withLock {
            guard let start, !stopped, input == nil,
                  let count = try? JSONEncoder().encode(value).count, count <= start.maximumIngressBytes else { return nil }
            let h = RuntimeIngressHandle(token: UUID(), incarnation: start.incarnation, encodedBytes: count, isCompletionOnly: false)
            input = .publication(h, value); transferred = false
            return h
        }
    }
    func takeStorageIngress(_ h: RuntimeStorageIngressHandle, incarnation: RuntimeIncarnation) -> Data? {
        lock.withLock {
            takes += 1
            guard incarnation == start?.incarnation, !transferred, case .storage(let current, let bytes) = input,
                  current == h else { return nil }
            transferred = true; return bytes
        }
    }
    func takeAssetIngress(_ h: RuntimeAssetIngressHandle, incarnation: RuntimeIncarnation) -> Data? {
        lock.withLock {
            guard incarnation == start?.incarnation, !transferred, case .asset(let current, let bytes) = input,
                  current == h else { return nil }
            transferred = true; return bytes
        }
    }
    func takeIngress(_ h: RuntimeIngressHandle, incarnation: RuntimeIncarnation) -> ProviderOutput? {
        lock.withLock {
            guard incarnation == start?.incarnation, !transferred, case .publication(let current, let value) = input,
                  current == h else { return nil }
            transferred = true; return value
        }
    }
    private func dispose(_ handle: Handle, incarnation: RuntimeIncarnation, wasTransferred: Bool) {
        lock.withLock {
            guard incarnation == start?.incarnation, input?.handle == handle, transferred == wasTransferred else { return }
            input = nil; transferred = false
        }
    }
    func rejectStorageIngress(_ h: RuntimeStorageIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.storage(h), incarnation: incarnation, wasTransferred: false)
    }
    func cancelStorageIngress(_ h: RuntimeStorageIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.storage(h), incarnation: incarnation, wasTransferred: true)
    }
    func finishStorageIngress(_ h: RuntimeStorageIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.storage(h), incarnation: incarnation, wasTransferred: true)
    }
    func rejectAssetIngress(_ h: RuntimeAssetIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.asset(h), incarnation: incarnation, wasTransferred: false)
    }
    func cancelAssetIngress(_ h: RuntimeAssetIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.asset(h), incarnation: incarnation, wasTransferred: true)
    }
    func finishAssetIngress(_ h: RuntimeAssetIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.asset(h), incarnation: incarnation, wasTransferred: true)
    }
    func rejectIngress(_ h: RuntimeIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.publication(h), incarnation: incarnation, wasTransferred: false)
    }
    func cancelIngress(_ h: RuntimeIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.publication(h), incarnation: incarnation, wasTransferred: true)
    }
    func finishIngress(_ h: RuntimeIngressHandle, incarnation: RuntimeIncarnation) {
        dispose(.publication(h), incarnation: incarnation, wasTransferred: true)
    }
    func tryHandoff(incarnation: RuntimeIncarnation, delivery: RuntimeAdapterDelivery) -> RuntimeHandoffResult {
        lock.withLock {
            if case .start(let value) = delivery {
                guard start == nil, incarnation == value.incarnation else { return .rejectedBeforeHandoff }
                start = value; stopped = false
                return .accepted
            }
            guard let start, incarnation == start.incarnation, !stopped, output == nil else { return .rejectedBeforeHandoff }
            if case .storageResponse(let value) = delivery {
                guard !reject, value.receipt.incarnation == incarnation,
                      value.payload.count <= start.maximumDeliveryBytes else { return .rejectedBeforeHandoff }
            }
            output = delivery
            return .accepted
        }
    }
    func requestStop(incarnation: RuntimeIncarnation, reason: RuntimeStopReason) {
        lock.withLock {
            guard incarnation == start?.incarnation, !stopped else { return }
            stops += 1; stopped = true; input = nil; output = nil
        }
    }
    func deliveryWasReceived(incarnation: RuntimeIncarnation) {
        lock.withLock {
            guard incarnation == start?.incarnation else { return }
            receipts += 1; output = nil
        }
    }
    func discardTransportReply(incarnation: RuntimeIncarnation) {
        lock.withLock {
            if incarnation == start?.incarnation { output = nil }
            // This is buffer disposal, not a receipt or a release of runtime credit/quota.
        }
    }
    func processDidExit(incarnation: RuntimeIncarnation) {
        lock.withLock {
            guard incarnation == start?.incarnation else { return }
            input = nil; output = nil; start = nil
        }
    }
}

/// One physical exchange task, one shared close task. The SDK owns the enclosing memory scope.
private final class StorageRuntimeByteBridge: AddonStorageMessageChannel, @unchecked Sendable {
    enum HoldPoint { case beforeReceive, afterHandoff }
    let generation: ConnectionGeneration
    let profile: StorageFrameProfile?
    let gate = StorageBridgeGate()
    let closeEntered = StorageBridgeGate()
    private let lock = NSLock()
    private let runtime: AddonRuntime
    private let adapter: StorageMessageAdapter
    private let connection: RuntimeConnection
    private var holdPoint: HoldPoint?
    private var inFlight: Task<AddonStorageMessageExchangeResult, any Error>?
    private var closeTask: Task<Void, Never>?
    private var revoked = false
    private var lastSequence: UInt64 = 0
    private var result: AddonRuntime.RuntimeStorageRequestResult?
    private var exchanges = 0
    private var closes = 0
    private var drained = false
    private var fault: Bool?
    var lastResult: AddonRuntime.RuntimeStorageRequestResult? { lock.withLock { result } }
    var exchangeCount: Int { lock.withLock { exchanges } }
    var closeCount: Int { lock.withLock { closes } }
    var didDrain: Bool { lock.withLock { drained } }

    init(runtime: AddonRuntime, adapter: StorageMessageAdapter, connection: RuntimeConnection) {
        self.runtime = runtime; self.adapter = adapter; self.connection = connection
        generation = connection.publicationConnection.generation
        profile = connection.publicationConnection.negotiatedProtocol.storageFrameProfile
    }
    func hold(_ point: HoldPoint) async { lock.withLock { holdPoint = point } }
    func armFault(wrongNonce: Bool) { lock.withLock { fault = wrongNonce } }
    func exchange(_ frame: Data, sequence: UInt64) async throws -> AddonStorageMessageExchangeResult {
        let task: Task<AddonStorageMessageExchangeResult, any Error> = try lock.withLock {
            guard !revoked else { throw AddonFailure(code: .sessionRevoked, reason: "Revoked bridge") }
            guard inFlight == nil else { throw AddonFailure(code: .resourceDenied, reason: "Occupied bridge") }
            guard sequence > lastSequence, !frame.isEmpty, frame.count <= 196_608 else {
                throw AddonFailure(code: .invalidPayload, reason: "Invalid physical frame")
            }
            lastSequence = sequence; exchanges += 1
            let created = Task { try await self.perform(frame, sequence: sequence) }
            inFlight = created
            return created
        }
        do {
            let value = try await task.value
            lock.withLock { inFlight = nil }
            return value
        } catch {
            lock.withLock { inFlight = nil }
            throw error
        }
    }
    private func perform(_ frame: Data, sequence: UInt64) async throws -> AddonStorageMessageExchangeResult {
        let request = try StorageFrameCodec.decodeRequest(frame, profile: profile)
        guard let handle = adapter.stage(frame, sequence: sequence, incarnation: connection.incarnation) else {
            return .rejectedBeforeHandoff
        }
        defer { adapter.rejectStorageIngress(handle, incarnation: connection.incarnation) }
        let point = lock.withLock { () -> HoldPoint? in defer { holdPoint = nil }; return holdPoint }
        if point == .beforeReceive { await gate.hold(); try checkRevoked() }
        let result = await runtime.receiveStorageRequest(handle, connection: connection)
        lock.withLock { self.result = result }
        guard case .completed(_, .handedOff) = result else {
            // Refused reply delivery is NOT a request-side non-exposure observation.
            throw AddonFailure(code: .dependencyUnavailable, reason: "No deliverable host response")
        }
        guard let delivery = adapter.reply else {
            throw AddonFailure(code: .dependencyUnavailable, reason: "Missing host response")
        }
        var consumed = false
        defer { if !consumed { adapter.discardTransportReply(incarnation: connection.incarnation) } }
        if point == .afterHandoff { await gate.hold(); try checkRevoked() }
        let fault = lock.withLock { () -> Bool? in defer { self.fault = nil }; return self.fault }
        if fault == false {
            lock.withLock { revoked = true }
            throw AddonFailure(code: .dependencyUnavailable, reason: "Physical fault after host handoff")
        }
        let original = delivery.receipt
        let r = fault == true
            ? RuntimeStorageReceipt(token: UUID(), incarnation: original.incarnation, connectionToken: original.connectionToken,
                                    sequence: original.sequence, requestID: original.requestID, operation: original.operation)
            : original
        guard r.incarnation == connection.incarnation, r.connectionToken == connection.token,
              r.sequence == sequence, r.requestID == request.requestID, r.operation == request.operation,
              delivery.payload.count <= 196_608,
              await runtime.receiveStorageReceipt(r, connection: connection) else {
            lock.withLock { revoked = true }
            throw AddonFailure(code: .sessionRevoked, reason: "Exact host receipt refused")
        }
        consumed = true
        return .response(delivery.payload)
    }
    private func checkRevoked() throws {
        if lock.withLock({ revoked }) { throw AddonFailure(code: .sessionRevoked, reason: "Closed physical exchange") }
    }
    func close() async {
        let task = lock.withLock { () -> Task<Void, Never> in
            if let closeTask { return closeTask }
            revoked = true; closes += 1
            let physical = inFlight
            let created = Task {
                await self.runtime.closeConnection(self.connection)
                await self.closeEntered.report()
                await self.gate.release()
                if let physical { _ = try? await physical.value }
                self.lock.withLock { self.drained = physical != nil }
            }
            closeTask = created
            return created
        }
        await task.value
    }
}

private actor StorageBridgeGate {
    private var arrived = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var resume: CheckedContinuation<Void, Never>?
    func hold() async {
        arrived = true; arrival?.resume(); arrival = nil
        if !released { await withCheckedContinuation { resume = $0 } }
    }
    func wait() async { if !arrived { await withCheckedContinuation { arrival = $0 } } }
    func report() { arrived = true; arrival?.resume(); arrival = nil }
    func release() { released = true; resume?.resume(); resume = nil }
}
