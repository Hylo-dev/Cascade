//
//  AddonKeyedStorageTests.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct AddonKeyedStorageTests {
    static func root() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/cascade-keyed-\(UUID())")
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    static func identity(_ publisher: String = "publisher.one") throws -> VerifiedAddonIdentity {
        VerifiedAddonIdentity(
            publisher: publisher,
            addonID: try #require(AddonID(rawValue: "com.example.keyed"))
        )
    }

    @Test
    func independentMaximumValuesPersistAndEmptyDiffersFromMissing() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor
        )
        let owner = try await store.owner(for: identity)
        let value = Data(repeating: 7, count: 65_536)
        try await store.write(value, key: "one", owner: owner)
        try await store.write(value, key: "two", owner: owner)
        try await store.write(Data(), key: "empty", owner: owner)
        #expect(try await store.read(key: "one", owner: owner) == value)
        #expect(try await store.read(key: "two", owner: owner) == value)
        #expect(try await store.read(key: "empty", owner: owner) == Data())
        #expect(try await store.read(key: "missing", owner: owner) == nil)
        #expect(await governor.usage(.diskStateBytes) > 131_072)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
        let maximumKey = String(repeating: "a", count: 256)
        try await store.write(value, key: maximumKey, owner: owner)
        #expect(try await store.read(key: maximumKey, owner: owner) == value)
        #expect(try Data(contentsOf: Self.valueFile(root, identity: identity, key: maximumKey)).count == 65_920)
        _ = try await store.close()
    }

    static func valueFile(
        _ root: URL,
        identity: VerifiedAddonIdentity,
        key: String,
        storageClass: KeyedStorageClass = .data
    ) throws -> URL {
        root.appendingPathComponent(KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(identity)))
            .appendingPathComponent(storageClass.directoryName)
            .appendingPathComponent(
                KeyedStorageRecord.hex(
                    KeyedStorageRecord.keyDigest(
                        try KeyedStorageRecord.validatedKey(key)
                    )
                ) + ".value"
            )
    }

    @Test
    func exactKeyBytesAndPublisherNamespacesRemainIndependent() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let other = try Self.identity("publisher.two")
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [identity, other].map(KeyedStorageRegistration.init),
            governor: ResourceGovernor()
        )
        let owner = try await store.owner(for: identity)
        let otherOwner = try await store.owner(for: other)
        let keys = ["é", "e\u{301}", "/../", ".", " ", String(repeating: "a", count: 256)]
        for (index, key) in keys.enumerated() {
            try await store.write(Data([UInt8(index)]), key: key, owner: owner)
        }
        for (index, key) in keys.enumerated() {
            #expect(try await store.read(key: key, owner: owner) == Data([UInt8(index)]))
            #expect(try await store.read(key: key, owner: otherOwner) == nil)
        }
        for key in ["", "a\0b", String(repeating: "a", count: 257), String(repeating: "é", count: 129)] {
            await #expect(throws: KeyedStorageFailure.invalidKey) {
                try await store.write(Data(), key: key, owner: owner)
            }
        }
        await #expect(throws: KeyedStorageFailure.oversized) {
            try await store.write(Data(repeating: 0, count: 65_537), key: "large", owner: owner)
        }
        #expect(try await store.close() == .closed)
    }

    @Test
    func stageCancelRevokeCloseAndReopenPreserveCommittedValuesAndCharges() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor
        )
        var owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let original = await governor.usage(.diskBytes)
        let retained = await governor.usage(.retainedStateBytes)
        for action in 0..<3 {
            let ticket = try await store.stage(Data([2]), key: "k", owner: owner)
            #expect(try await store.read(key: "k", owner: owner) == Data([1]))
            #expect(await governor.usage(.diskBytes) == original + 4_226)
            if action == 0 { try await store.cancel(ticket, owner: owner) }
            if action == 1 { try await store.revoke(owner: owner); owner = try await store.owner(for: identity) }
            if action == 2 {
                #expect(try await store.close() == .closed)
                #expect(await governor.usage(.diskBytes) == original)
                try await store.reopen(root: root)
                owner = try await store.owner(for: identity)
            }
            #expect(await governor.usage(.diskBytes) == original)
            #expect(await governor.usage(.retainedStateBytes) == retained)
            await #expect(throws: KeyedStorageFailure.invalidTicket) { try await store.commit(ticket, owner: owner) }
        }
        try await store.write(Data([3]), key: "k", owner: owner)
        _ = try await store.close()
        try await store.reopen(root: root)
        owner = try await store.owner(for: identity)
        #expect(try await store.read(key: "k", owner: owner) == Data([3]))
        #expect(await governor.usage(.diskBytes) == original)
        _ = try await store.close()
    }

    @Test
    func quotaRejectsOldPlusStageBeforeFileCreationAndKeepsUnrelatedReservations() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let unrelated = try await governor.admit(.provider, owner: identity.addonID)
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            diskBudget: 20_000
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        await #expect(throws: KeyedStorageFailure.quotaExceeded) {
            try await store.write(Data([2]), key: "k", owner: owner)
        }
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        #expect(await governor.usage(.diskBytes) == before)
        #expect(await governor.usage(.providers) == 1)
        let file = try Self.valueFile(root, identity: identity, key: "k")
        #expect(
            !FileManager.default.fileExists(
                atPath: file.deletingLastPathComponent().appendingPathComponent(".pending").path
            )
        )
        try await governor.release(unrelated.id, owner: unrelated.owner)
        _ = try await store.close()
    }

    @Test
    func emptyFilesConsumeMetadataAndReconcileWithoutRetainedKeyMap() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            diskBudget: 25_000
        )
        var owner = try await store.owner(for: identity)
        for key in ["a", "b", "c"] { try await store.write(Data(), key: key, owner: owner) }
        #expect(await governor.usage(.diskBytes) == 12_288 + 3 * 4_225)
        await #expect(throws: KeyedStorageFailure.quotaExceeded) {
            try await store.write(Data(), key: "d", owner: owner)
        }
        _ = try await store.close()
        try await store.reopen(root: root)
        owner = try await store.owner(for: identity)
        #expect(try await store.read(key: "c", owner: owner) == Data())
        #expect(await governor.usage(.diskBytes) == 12_288 + 3 * 4_225)
        _ = try await store.close()
    }

    @Test
    func closeKeepsCheckpointCompetitionAndCachePurgeHasDisjointEffects() async throws {
        let root = try Self.root()
        let checkpointRoot = try Self.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: checkpointRoot) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let checkpoint = try await AddonStateStore.open(
            root: checkpointRoot,
            registrations: [StateRegistration(identity: identity, maximumSchemaVersion: 1)],
            governor: governor
        )
        let checkpointOwner = try await checkpoint.owner(for: identity)
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor
        )
        var owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        try await store.write(Data([9]), key: "k", owner: owner, storageClass: .cache)
        let state = await governor.usage(.diskStateBytes)
        let cache = await governor.usage(.diskCacheBytes)
        #expect(cache == 4_096 + 4_226)
        _ = try await store.close()
        #expect(await governor.usage(.diskStateBytes) == state)
        #expect(await governor.usage(.diskCacheBytes) == cache)
        let filler = try await governor.admit(
            .diskState(bytes: 10 * 1_024 * 1_024 - state - 4_159),
            owner: identity.addonID
        )
        do {
            try await checkpoint.write(Data([1]), schemaVersion: 1, owner: checkpointOwner)
            Issue.record("Checkpoint spent retained keyed quota")
        } catch let failure as AddonFailure { #expect(failure.code == .resourceDenied) }
        try await governor.release(filler.id, owner: filler.owner)
        try await checkpoint.write(Data([2]), schemaVersion: 1, owner: checkpointOwner)
        try await store.reopen(root: root)
        owner = try await store.owner(for: identity)
        let dataBefore = await governor.usage(.diskStateBytes)
        try await store.purgeCache(identity: identity)
        #expect(await governor.usage(.diskStateBytes) == dataBefore)
        #expect(await governor.usage(.diskCacheBytes) == 4_096)
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        #expect(try await checkpoint.read(owner: checkpointOwner)?.data == Data([2]))
        try await store.remove(key: "k", owner: owner)
        #expect(await governor.usage(.diskCacheBytes) == 4_096)
        _ = try await store.close()
        try await checkpoint.close()
    }

    @Test
    func corruptFutureSwappedAndOversizedLiveRecordsStayChargedUntilExplicitRemoval() async throws {
        for corruption in 0..<6 {
            let root = try Self.root()
            defer { try? FileManager.default.removeItem(at: root) }
            let identity = try Self.identity()
            let governor = ResourceGovernor()
            let store = try await AddonKeyedStorage.open(
                root: root,
                registrations: [KeyedStorageRegistration(identity: identity)],
                governor: governor
            )
            var owner = try await store.owner(for: identity)
            try await store.write(Data([1]), key: "k", owner: owner)
            try await store.write(Data([9]), key: "healthy", owner: owner)
            _ = try await store.close()
            let file = try Self.valueFile(root, identity: identity, key: "k")
            var bytes = try Data(contentsOf: file)
            if corruption == 0 { bytes[127] ^= 1 }
            if corruption == 1 { bytes[9] = 2 }
            if corruption == 2 { bytes[11] = 1 }
            if corruption == 3 {
                bytes = try Data(contentsOf: Self.valueFile(root, identity: identity, key: "healthy"))
            }
            if corruption == 4 { bytes = Data(repeating: 0, count: 66_000) }
            if corruption == 5 {
                bytes = KeyedStorageRecord.encode(
                    key: Data("k".utf8), value: Data([9]),
                    namespace: KeyedStorageRecord.namespaceDigest(try Self.identity("publisher.other")),
                    storageClass: .data, revision: 1)
            }
            try bytes.write(to: file)
            try await store.reopen(root: root)
            owner = try await store.owner(for: identity)
            let expected: KeyedStorageFailure =
                corruption == 1 ? .futureFormat : corruption == 4 ? .oversized : .corrupt
            await #expect(throws: expected) { try await store.read(key: "k", owner: owner) }
            await #expect(throws: expected) { try await store.write(Data([2]), key: "k", owner: owner) }
            #expect(try Data(contentsOf: file) == bytes)
            #expect(try await store.read(key: "healthy", owner: owner) == Data([9]))
            let before = await governor.usage(.diskBytes)
            try await store.remove(key: "k", owner: owner)
            #expect(await governor.usage(.diskBytes) == before - bytes.count - 4_096)
            _ = try await store.close()
        }
    }

    @Test
    func unsafeRootsEntriesAndSecondOpenerFailClosed() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let registrations = [KeyedStorageRegistration(identity: identity)]
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: registrations,
            governor: ResourceGovernor()
        )
        await #expect(throws: KeyedStorageFailure.busy) {
            try await AddonKeyedStorage.open(root: root, registrations: registrations, governor: ResourceGovernor())
        }
        _ = try await store.close()
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        await #expect(throws: KeyedStorageFailure.unsafePath) {
            try await AddonKeyedStorage.open(root: link, registrations: registrations, governor: ResourceGovernor())
        }
        await #expect(throws: KeyedStorageFailure.unsafePath) {
            try await AddonKeyedStorage.open(
                root: URL(fileURLWithPath: root.path + "/../" + root.lastPathComponent),
                registrations: registrations,
                governor: ResourceGovernor()
            )
        }
        try FileManager.default.removeItem(at: link)
        try Data().write(to: root.appendingPathComponent("unknown"))
        await #expect(throws: KeyedStorageFailure.unrecognizedEntry) {
            try await AddonKeyedStorage.open(root: root, registrations: registrations, governor: ResourceGovernor())
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("unknown").path))
    }

    @Test
    func unsafeChildFilesAndDirectoriesAreNeverFollowed() async throws {
        for kind in 0..<5 {
            let root = try Self.root()
            defer { try? FileManager.default.removeItem(at: root) }
            let identity = try Self.identity()
            let registrations = [KeyedStorageRegistration(identity: identity)]
            let store = try await AddonKeyedStorage.open(
                root: root,
                registrations: registrations,
                governor: ResourceGovernor()
            )
            let owner = try await store.owner(for: identity)
            try await store.write(Data([1]), key: "k", owner: owner)
            _ = try await store.close()
            let file = try Self.valueFile(root, identity: identity, key: "k")
            if kind == 0 { #expect(chmod(file.path, 0o644) == 0) }
            if kind == 1 {
                try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("hardlink"))
            }
            if kind == 2 {
                try FileManager.default.removeItem(at: file)
                #expect(mkfifo(file.path, 0o600) == 0)
            }
            if kind == 3 {
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root)
            }
            if kind == 4 {
                let directory = file.deletingLastPathComponent()
                try FileManager.default.removeItem(at: directory)
                try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: root)
            }
            await #expect(throws: (any Error).self) { try await store.reopen(root: root) }
        }
    }
}

/// KeyedResourceGate delays one real governor result, never admission or disk I/O itself.
actor KeyedResourceGate: RuntimeResourceAccess {
    enum Point { case temporary, diskAdmission, diskResize, release }
    nonisolated let resourceGovernorTarget: ResourceGovernor
    private var point: Point?
    private var remainingSkips = 0
    private var arrived = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    init(_ governor: ResourceGovernor) { resourceGovernorTarget = governor }
    /// arm skips only a bounded number of matching real returns, distinguishing stage from commit cleanup.
    func arm(
        _ point : Point,
        skipping: Int = 0
    ) {
        precondition((0...8).contains(skipping))
        self.point = point
        remainingSkips = skipping
        arrived = false
        released = false
    }
    func wait() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resume() { released = true; completion?.resume(); completion = nil }
    private func hold(_ candidate: Point) async {
        guard point == candidate else { return }
        if remainingSkips > 0 {
            remainingSkips -= 1
            return
        }
        point = nil
        arrived = true
        arrival?.resume()
        arrival = nil
        if released { return }
        await withCheckedContinuation { completion = $0 }
    }
    func admit(_ request: ResourceRequest, owner: AddonID) async throws -> ResourceReservation {
        let result = try await resourceGovernorTarget.admit(request, owner: owner)
        switch request {
        case .temporaryMemory: await hold(.temporary)
        case .diskState, .diskCache: await hold(.diskAdmission)
        default: break
        }
        return result
    }
    func release(_ reservationID: UUID, owner: AddonID) async throws {
        try await resourceGovernorTarget.release(reservationID, owner: owner)
        await hold(.release)
    }
    func reduceStateReservation(_ reservationID: UUID, owner: AddonID, toBytes: Int) async -> Bool {
        await resourceGovernorTarget.reduceStateReservation(reservationID, owner: owner, toBytes: toBytes)
    }
    func resizeStateReservation(
        _ reservationID: UUID,
        owner: AddonID,
        fromBytes: Int,
        toBytes: Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeStateReservation(
            reservationID,
            owner: owner,
            fromBytes: fromBytes,
            toBytes: toBytes
        )
    }
    func resizeDiskReservation(
        _ reservationID: UUID,
        owner: AddonID,
        fromBytes: Int,
        toBytes: Int
    ) async throws -> Bool {
        let result = try await resourceGovernorTarget.resizeDiskReservation(
            reservationID,
            owner: owner,
            fromBytes: fromBytes,
            toBytes: toBytes
        )
        await hold(.diskResize)
        return result
    }
}

/// KeyedFileFaults forwards real successful syscalls and injects only narrowly classified failures.
final class KeyedFileFaults: KeyedStorageFileOperations, @unchecked Sendable {
    private let lock = NSLock()
    private var unlinkFailure = false
    private var directoryFailure = false
    private var writeFailure = false
    private var shortWrites = false
    private var disappearancePath: URL?
    private var directoryFailureCount = 0
    private let real = POSIXKeyedStorageFileOperations()

    func set(unlink: Bool = false, directory: Bool = false, write: Bool = false, short: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        unlinkFailure = unlink
        directoryFailure = directory
        writeFailure = write
        shortWrites = short
        disappearancePath = nil
        directoryFailureCount = 0
    }
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) -> Int {
        lock.lock()
        let fails = writeFailure
        let short = shortWrites
        lock.unlock()
        if fails { errno = EIO; return -1 }
        if short { return real.write(descriptor, bytes: UnsafeRawBufferPointer(rebasing: bytes.prefix(7))) }
        return real.write(descriptor, bytes: bytes)
    }
    func unlink(_ directory: Int32, name: String) -> Int32 {
        lock.lock()
        let fails = unlinkFailure
        lock.unlock()
        if fails { errno = EIO; return -1 }
        return real.unlink(directory, name: name)
    }
    /// failDirectorySync targets a real visibility transition, not ancestor setup or stage admission.
    func failDirectorySync(afterDisappearanceOf path: URL) {
        lock.lock()
        defer { lock.unlock() }
        disappearancePath = path
        directoryFailureCount = 0
    }

    var injectedDirectoryFailures: Int {
        lock.lock()
        defer { lock.unlock() }
        return directoryFailureCount
    }

    func syncDirectory(_ descriptor: Int32) -> Int32 {
        lock.lock()
        let fails =
            directoryFailure
            || disappearancePath.map { !FileManager.default.fileExists(atPath: $0.path) } == true
        if fails { directoryFailureCount += 1 }
        lock.unlock()
        if fails {
            errno = EIO
            return -1
        }
        return real.syncDirectory(descriptor)
    }
}

extension AddonKeyedStorageTests {
    @Test
    func realAdmissionAndResizeReturnsCannotResurrectRevokedOrClosedOwners() async throws {
        for point in [KeyedResourceGate.Point.temporary, .diskResize, .release] {
            for closing in [false, true] {
                let root = try Self.root()
                defer { try? FileManager.default.removeItem(at: root) }
                let identity = try Self.identity()
                let governor = ResourceGovernor()
                let gate = KeyedResourceGate(governor)
                let store = try await AddonKeyedStorage.open(
                    root: root,
                    registrations: [KeyedStorageRegistration(identity: identity)],
                    governor: governor,
                    resourceAccess: gate
                )
                let owner = try await store.owner(for: identity)
                try await store.write(Data([1]), key: "k", owner: owner)
                let beforeDisk = await governor.usage(.diskBytes)
                let beforeMemory = await governor.usage(.retainedStateBytes)
                await gate.arm(point)
                let task = Task { try await store.stage(Data([2]), key: "k", owner: owner) }
                await gate.wait()
                await #expect(throws: KeyedStorageFailure.busy) { try await store.read(key: "k", owner: owner) }
                if closing {
                    #expect(try await store.close() == .draining)
                } else {
                    try await store.revoke(owner: owner)
                }
                await gate.resume()
                do { _ = try await task.value; Issue.record("Stale stage returned a ticket") } catch {
                    #expect(error is KeyedStorageFailure)
                }
                #expect(await governor.usage(.diskBytes) == beforeDisk)
                #expect(await governor.usage(.retainedStateBytes) == beforeMemory)
                #expect(await governor.usage(.admittedMemoryBytes) == 0)
                if closing { try await store.reopen(root: root) }
                let current = try await store.owner(for: identity)
                #expect(try await store.read(key: "k", owner: current) == Data([1]))
                _ = try await store.close()
            }
        }
    }

    @Test
    func readDoesNotReturnDataAfterRevocationDuringItsRealScratchRelease() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let gate = KeyedResourceGate(governor)
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            resourceAccess: gate
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        await gate.arm(.release)
        let task = Task { try await store.read(key: "k", owner: owner) }
        await gate.wait()
        try await store.revoke(owner: owner)
        await gate.resume()
        await #expect(throws: KeyedStorageFailure.invalidOwner) { try await task.value }
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        _ = try await store.close()
    }

    @Test
    func unrelatedRevocationAndInvalidTicketsCannotDiscardAnotherPublishersStage() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try Self.identity()
        let second = try Self.identity("publisher.two")
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [first, second].map(KeyedStorageRegistration.init),
            governor: ResourceGovernor()
        )
        let owner = try await store.owner(for: first)
        let other = try await store.owner(for: second)
        let ticket = try await store.stage(Data([1]), key: "k", owner: owner)
        await #expect(throws: KeyedStorageFailure.invalidTicket) { try await store.commit(ticket, owner: other) }
        try await store.revoke(owner: other)
        try await store.commit(ticket, owner: owner)
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        _ = try await store.close()
    }

    @Test
    func failedUnlinkRetainsStageAndLiveChargesAndShortWritesAreReal() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let faults = KeyedFileFaults()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            fileOperations: faults
        )
        let owner = try await store.owner(for: identity)
        faults.set(short: true)
        try await store.write(Data(repeating: 1, count: 100), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        let ticket = try await store.stage(Data([2]), key: "k", owner: owner)
        faults.set(unlink: true)
        await #expect(throws: KeyedStorageFailure.cleanupRequired) { try await store.cancel(ticket, owner: owner) }
        #expect(await governor.usage(.diskBytes) == before + 4_226)
        #expect(try await store.read(key: "k", owner: owner) == Data(repeating: 1, count: 100))
        faults.set()
        _ = try await store.close()
        #expect(await governor.usage(.diskBytes) == before)
        try await store.reopen(root: root)
        let current = try await store.owner(for: identity)
        faults.set(unlink: true)
        await #expect(throws: KeyedStorageFailure.cleanupRequired) { try await store.remove(key: "k", owner: current) }
        #expect(await governor.usage(.diskBytes) == before)
        faults.set()
        try await store.remove(key: "k", owner: current)
        #expect(await governor.usage(.diskBytes) == 12_288)
        _ = try await store.close()
    }

    @Test
    func postRenameDirectoryFailureReturnsCommittedUncertaintyAndPreservesNewValue() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let faults = KeyedFileFaults()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            fileOperations: faults
        )
        var owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        let ticket = try await store.stage(Data([2]), key: "k", owner: owner)
        faults.set(directory: true)
        await #expect(throws: KeyedStorageFailure.committedDurabilityUncertain) {
            try await store.commit(ticket, owner: owner)
        }
        #expect(await governor.usage(.diskBytes) == before)
        #expect(try await store.read(key: "k", owner: owner) == Data([2]))
        faults.set()
        _ = try await store.close()
        try await store.reopen(root: root)
        owner = try await store.owner(for: identity)
        #expect(try await store.read(key: "k", owner: owner) == Data([2]))
        _ = try await store.close()
    }

    @Test
    func startupAdmitsActualTruncatedPendingBeforeRecoveryAndRollsBackFailedGrowth() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        _ = try await store.close()
        let before = await governor.usage(.diskBytes)
        let file = try Self.valueFile(root, identity: identity, key: "k")
        let pending = file.deletingLastPathComponent().appendingPathComponent(".pending")
        try Data([1, 2, 3]).write(to: pending)
        #expect(chmod(pending.path, 0o600) == 0)
        let filler = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024 - before), owner: identity.addonID)
        await #expect(throws: (any Error).self) { try await store.reopen(root: root) }
        #expect(FileManager.default.fileExists(atPath: pending.path))
        #expect(await governor.usage(.diskBytes) == 10 * 1_024 * 1_024)
        try await governor.release(filler.id, owner: filler.owner)
        try await store.reopen(root: root)
        #expect(!FileManager.default.fileExists(atPath: pending.path))
        #expect(await governor.usage(.diskBytes) == before)
        let current = try await store.owner(for: identity)
        #expect(try await store.read(key: "k", owner: current) == Data([1]))
        _ = try await store.close()
    }
}

extension AddonKeyedStorageTests {
    @Test
    func revokingPreparedOwnerWhileAnotherOwnerReadsDrainsTheRevokedStage() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try Self.identity()
        let second = try Self.identity("publisher.two")
        let governor = ResourceGovernor()
        let gate = KeyedResourceGate(governor)
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [first, second].map(KeyedStorageRegistration.init),
            governor: governor,
            resourceAccess: gate
        )
        let owner = try await store.owner(for: first)
        let other = try await store.owner(for: second)
        try await store.write(Data([1]), key: "k", owner: other)
        let before = await governor.usage(.diskBytes)
        _ = try await store.stage(Data([2]), key: "k", owner: other)
        await gate.arm(.temporary)
        let task = Task { try await store.read(key: "k", owner: owner) }
        await gate.wait()
        try await store.revoke(owner: other)
        await gate.resume()
        #expect(try await task.value == nil)
        #expect(await governor.usage(.diskBytes) == before)
        let renewed = try await store.owner(for: second)
        try await store.write(Data([3]), key: "k", owner: renewed)
        #expect(try await store.read(key: "k", owner: renewed) == Data([3]))
        _ = try await store.close()
    }
}

extension AddonKeyedStorageTests {
    @Test
    func cachePurgePreservesPreparedDataAndUserRemovalIsExplicit() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        try await store.write(Data([2]), key: "k", owner: owner, storageClass: .cache)
        let ticket = try await store.stage(Data([3]), key: "k", owner: owner)
        let state = await governor.usage(.diskStateBytes)
        try await store.purgeCache(identity: identity)
        #expect(await governor.usage(.diskStateBytes) == state)
        try await store.commit(ticket, owner: owner)
        #expect(try await store.read(key: "k", owner: owner) == Data([3]))
        try await store.removeUserData(identity: identity)
        await #expect(throws: KeyedStorageFailure.invalidOwner) { try await store.read(key: "k", owner: owner) }
        let renewed = try await store.owner(for: identity)
        #expect(try await store.read(key: "k", owner: renewed) == nil)
        #expect(await governor.usage(.diskStateBytes) == 12_288)
        #expect(await governor.usage(.diskCacheBytes) == 4_096)
        _ = try await store.close()
    }

    @Test
    func writeFailureDropsBuffersButKeepsFailedCleanupChargeUntilRecovery() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let faults = KeyedFileFaults()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            fileOperations: faults
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let disk = await governor.usage(.diskBytes)
        let state = await governor.usage(.retainedStateBytes)
        faults.set(unlink: true, write: true)
        await #expect(throws: KeyedStorageFailure.cleanupRequired) {
            try await store.write(Data(repeating: 2, count: 100), key: "k", owner: owner)
        }
        #expect(await governor.usage(.diskBytes) == disk + 4_096 + 128 + 1 + 100)
        #expect(await governor.usage(.retainedStateBytes) == state)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        await #expect(throws: KeyedStorageFailure.cleanupRequired) { try await store.close() }
        #expect(await governor.usage(.diskBytes) > disk)
        faults.set()
        try await store.reopen(root: root)
        let renewed = try await store.owner(for: identity)
        #expect(try await store.read(key: "k", owner: renewed) == Data([1]))
        #expect(await governor.usage(.diskBytes) == disk)
        _ = try await store.close()
    }

    @Test
    func cancellationAtRealResizeReturnNeverRenamesAndRefundsExactGrowth() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let gate = KeyedResourceGate(governor)
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            resourceAccess: gate
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        await gate.arm(.diskResize)
        let task = Task { try await store.write(Data([2]), key: "k", owner: owner) }
        await gate.wait()
        task.cancel()
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await governor.usage(.diskBytes) == before)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        _ = try await store.close()
    }

    @Test
    func staleLiveFingerprintAndCorruptCandidateCannotCommit() async throws {
        for changesLive in [false, true] {
            let root = try Self.root()
            defer { try? FileManager.default.removeItem(at: root) }
            let identity = try Self.identity()
            let governor = ResourceGovernor()
            let store = try await AddonKeyedStorage.open(
                root: root,
                registrations: [KeyedStorageRegistration(identity: identity)],
                governor: governor
            )
            let owner = try await store.owner(for: identity)
            try await store.write(Data([1]), key: "k", owner: owner)
            let ticket = try await store.stage(Data([2]), key: "k", owner: owner)
            let file = try Self.valueFile(root, identity: identity, key: "k")
            if changesLive {
                let bytes = KeyedStorageRecord.encode(
                    key: Data("k".utf8),
                    value: Data([9]),
                    namespace: KeyedStorageRecord.namespaceDigest(identity),
                    storageClass: .data,
                    revision: 8
                )
                try bytes.write(to: file)
            } else {
                let pending = file.deletingLastPathComponent().appendingPathComponent(".pending")
                var bytes = try Data(contentsOf: pending)
                bytes[127] ^= 1
                try bytes.write(to: pending)
            }
            await #expect(throws: changesLive ? KeyedStorageFailure.staleRevision : .corrupt) {
                try await store.commit(ticket, owner: owner)
            }
            #expect(try await store.read(key: "k", owner: owner) == Data([changesLive ? 9 : 1]))
            #expect(await governor.usage(.diskBytes) == 12_288 + 4_226)
            _ = try await store.close()
        }
    }

    @Test
    func revisionOverflowIsRefusedAndDeleteStartsANewSequence() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: ResourceGovernor()
        )
        var owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        _ = try await store.close()
        let file = try Self.valueFile(root, identity: identity, key: "k")
        try KeyedStorageRecord.encode(
            key: Data("k".utf8),
            value: Data([1]),
            namespace: KeyedStorageRecord.namespaceDigest(identity),
            storageClass: .data,
            revision: UInt64.max
        )
        .write(to: file)
        try await store.reopen(root: root)
        owner = try await store.owner(for: identity)
        await #expect(throws: KeyedStorageFailure.staleRevision) {
            try await store.write(Data([2]), key: "k", owner: owner)
        }
        try await store.remove(key: "k", owner: owner)
        try await store.write(Data([3]), key: "k", owner: owner)
        #expect(try await store.read(key: "k", owner: owner) == Data([3]))
        _ = try await store.close()
    }

    @Test
    func unsupportedMultiplePendingAndOverQuotaScanPreserveAllFiles() async throws {
        for multiple in [false, true] {
            let root = try Self.root()
            defer { try? FileManager.default.removeItem(at: root) }
            let identity = try Self.identity()
            let governor = ResourceGovernor()
            let store = try await AddonKeyedStorage.open(
                root: root,
                registrations: [KeyedStorageRegistration(identity: identity)],
                governor: governor,
                diskBudget: multiple ? 100_000 : 20_000
            )
            let owner = try await store.owner(for: identity)
            try await store.write(Data([1]), key: "k", owner: owner)
            if multiple { try await store.write(Data([1]), key: "k", owner: owner, storageClass: .cache) }
            _ = try await store.close()
            let before = await governor.usage(.diskBytes)
            let dataDirectory = try Self.valueFile(root, identity: identity, key: "k").deletingLastPathComponent()
            let pending = dataDirectory.appendingPathComponent(".pending")
            try Data().write(to: pending)
            #expect(chmod(pending.path, 0o600) == 0)
            if multiple {
                let cacheDirectory = try Self.valueFile(root, identity: identity, key: "k", storageClass: .cache)
                    .deletingLastPathComponent()
                let other = cacheDirectory.appendingPathComponent(".pending")
                try Data().write(to: other)
                #expect(chmod(other.path, 0o600) == 0)
            }
            await #expect(throws: multiple ? KeyedStorageFailure.unrecognizedEntry : .quotaExceeded) {
                try await store.reopen(root: root)
            }
            #expect(FileManager.default.fileExists(atPath: pending.path))
            #expect(await governor.usage(.diskBytes) == before)
        }
    }

    @Test
    func registryMetadataIsAdmittedBeforeDirectoryOrCapabilityPublication() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 11_000))
        await #expect(throws: AddonFailure.self) {
            try await AddonKeyedStorage.open(
                root: root,
                registrations: [KeyedStorageRegistration(identity: identity)],
                governor: governor
            )
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(await governor.usage(.diskBytes) == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        let registrations = try (0..<257)
            .map { KeyedStorageRegistration(identity: try Self.identity("publisher.\($0)")) }
        await #expect(throws: KeyedStorageFailure.invalidConfiguration) {
            try await AddonKeyedStorage.open(root: root, registrations: registrations, governor: ResourceGovernor())
        }
    }
}

extension AddonKeyedStorageTests {
    @Test
    func stageCancellationDuringFinalScratchReleaseCannotReturnATicket() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let gate = KeyedResourceGate(governor)
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor,
            resourceAccess: gate
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        await gate.arm(.release)
        let task = Task { try await store.stage(Data([2]), key: "k", owner: owner) }
        await gate.wait()
        task.cancel()
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await governor.usage(.diskBytes) == before)
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        _ = try await store.close()
    }
}

extension AddonKeyedStorageTests {
    @Test
    func retainedRegistryAllows256IdentitiesWithOnlyRootDiskMetadata() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identities = try (0..<256).map { try Self.identity("publisher.\($0)") }
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: identities.map(KeyedStorageRegistration.init),
            governor: governor
        )
        for identity in identities { _ = try await store.owner(for: identity) }
        #expect(await governor.usage(.diskStateBytes) == 4_096)
        #expect(await governor.usage(.retainedStateBytes) == 256 * 3_072 + 8_192 + 1_024)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        _ = try await store.close()
        #expect(await governor.usage(.diskBytes) == 4_096)
    }

    @Test
    func successfulReadResolvesOnlyTheUncertainCommittedKey() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let faults = KeyedFileFaults()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: ResourceGovernor(),
            fileOperations: faults
        )
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let ticket = try await store.stage(Data([2]), key: "k", owner: owner)
        faults.set(directory: true)
        await #expect(throws: KeyedStorageFailure.committedDurabilityUncertain) {
            try await store.commit(ticket, owner: owner)
        }
        faults.set()
        #expect(try await store.read(key: "unrelated", owner: owner) == nil)
        await #expect(throws: KeyedStorageFailure.committedDurabilityUncertain) {
            try await store.write(Data([3]), key: "k", owner: owner)
        }
        #expect(try await store.read(key: "k", owner: owner) == Data([2]))
        try await store.write(Data([3]), key: "k", owner: owner)
        #expect(try await store.read(key: "k", owner: owner) == Data([3]))
        _ = try await store.close()
    }

    @Test
    func anotherRootAndUnsafeOwnershipDoNotReplaceTheRetainedLedger() async throws {
        let root = try Self.root()
        let otherRoot = try Self.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: otherRoot) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(
            root: root,
            registrations: [KeyedStorageRegistration(identity: identity)],
            governor: governor
        )
        _ = try await store.close()
        await #expect(throws: KeyedStorageFailure.unsafePath) { try await store.reopen(root: otherRoot) }
        #expect(await governor.usage(.diskBytes) == 4_096)
        #expect(chmod(root.path, 0o755) == 0)
        await #expect(throws: KeyedStorageFailure.unsafePath) { try await store.reopen(root: root) }
        #expect(chmod(root.path, 0o700) == 0)
        try await store.reopen(root: root)
        _ = try await store.close()
        // This system directory is root-owned and nonprivate; the final-root check must reject it
        // before locking or scanning it. No filesystem data is modified by this read-only check.
        await #expect(throws: KeyedStorageFailure.unsafePath) {
            try await AddonKeyedStorage.open(
                root: URL(fileURLWithPath: "/private/tmp"),
                registrations: [KeyedStorageRegistration(identity: identity)],
                governor: ResourceGovernor()
            )
        }
    }
}

extension AddonKeyedStorageTests {
    @Test func closeDuringExplicitDeletionStageRefundPreventsLaterLiveUnlinks() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let gate = KeyedResourceGate(governor)
        let store = try await AddonKeyedStorage.open(root: root,
            registrations: [KeyedStorageRegistration(identity: identity)], governor: governor, resourceAccess: gate)
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        _ = try await store.stage(Data([2]), key: "k", owner: owner)
        await gate.arm(.release)
        let task = Task { try await store.removeUserData(identity: identity) }
        await gate.wait()
        #expect(try await store.close() == .draining)
        await gate.resume()
        await #expect(throws: KeyedStorageFailure.closed) { try await task.value }
        #expect(await governor.usage(.diskBytes) == before)
        try await store.reopen(root: root)
        let current = try await store.owner(for: identity)
        #expect(try await store.read(key: "k", owner: current) == Data([1]))
        _ = try await store.close()
    }
}

extension AddonKeyedStorageTests {
    @Test func checkpointAndKeyedWritesCannotSpendTheSameFullGlobalDiskPool() async throws {
        let root = try Self.root()
        let checkpointRoot = try Self.root()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: checkpointRoot)
        }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let checkpoint = try await AddonStateStore.open(root: checkpointRoot,
            registrations: [StateRegistration(identity: identity, maximumSchemaVersion: 1)], governor: governor)
        let checkpointOwner = try await checkpoint.owner(for: identity)
        let store = try await AddonKeyedStorage.open(root: root,
            registrations: [KeyedStorageRegistration(identity: identity)], governor: governor)
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        var fillers: [ResourceReservation] = []
        for index in 0..<10 {
            let other = try #require(AddonID(rawValue: "com.example.global\(index)"))
            fillers.append(try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024 - (index == 0 ? before : 0)), owner: other))
        }
        #expect(await governor.usage(.diskBytes) == 100 * 1_024 * 1_024)
        await #expect(throws: AddonFailure.self) { try await store.write(Data([2]), key: "k", owner: owner) }
        await #expect(throws: AddonFailure.self) {
            try await checkpoint.write(Data([2]), schemaVersion: 1, owner: checkpointOwner)
        }
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        #expect(try await checkpoint.read(owner: checkpointOwner) == nil)
        #expect(await governor.usage(.diskBytes) == 100 * 1_024 * 1_024)
        for filler in fillers { try await governor.release(filler.id, owner: filler.owner) }
        #expect(await governor.usage(.diskBytes) == before)
        _ = try await store.close()
        try await checkpoint.close()
    }

    @Test func laterInventoryAdmissionFailureRollsBackEarlierPoolGrowthOnly() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try Self.identity()
        let second = try Self.identity("publisher.two")
        let governor = ResourceGovernor()
        let store = try await AddonKeyedStorage.open(root: root,
            registrations: [first, second].map(KeyedStorageRegistration.init), governor: governor)
        for identity in [first, second] {
            let owner = try await store.owner(for: identity)
            try await store.write(Data([1]), key: "k", owner: owner)
        }
        _ = try await store.close()
        let before = await governor.usage(.diskBytes)
        for identity in [first, second] {
            let extra = try Self.valueFile(root, identity: identity, key: "extra")
            try Data().write(to: extra)
            #expect(chmod(extra.path, 0o600) == 0)
        }
        let filler = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024 - before - 4_096), owner: first.addonID)
        let full = await governor.usage(.diskBytes)
        await #expect(throws: AddonFailure.self) { try await store.reopen(root: root) }
        #expect(await governor.usage(.diskBytes) == full)
        for identity in [first, second] {
            #expect(FileManager.default.fileExists(atPath: try Self.valueFile(root, identity: identity, key: "extra").path))
        }
        try await governor.release(filler.id, owner: filler.owner)
        try await store.reopen(root: root)
        for identity in [first, second] {
            let owner = try await store.owner(for: identity)
            #expect(try await store.read(key: "k", owner: owner) == Data([1]))
            try await store.remove(key: "extra", owner: owner)
        }
        #expect(await governor.usage(.diskBytes) == before)
        _ = try await store.close()
    }
}

extension AddonKeyedStorageTests {
    @Test func pendingCleanupDirectorySyncFailureRetainsChargeUntilConfirmedCleanup() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let governor = ResourceGovernor()
        let faults = KeyedFileFaults()
        let store = try await AddonKeyedStorage.open(root: root,
            registrations: [KeyedStorageRegistration(identity: identity)], governor: governor, fileOperations: faults)
        let owner = try await store.owner(for: identity)
        try await store.write(Data([1]), key: "k", owner: owner)
        let before = await governor.usage(.diskBytes)
        let ticket = try await store.stage(Data([2]), key: "k", owner: owner)
        faults.set(directory: true)
        await #expect(throws: KeyedStorageFailure.cleanupRequired) { try await store.cancel(ticket, owner: owner) }
        #expect(await governor.usage(.diskBytes) == before + 4_226)
        #expect(try await store.read(key: "k", owner: owner) == Data([1]))
        faults.set()
        _ = try await store.close()
        #expect(await governor.usage(.diskBytes) == before)
    }
}

/// KeyedAncestorSyncFaults records actual directory identities and fails only the chosen managed parent.
/// Successful calls always reach the real POSIX adapter; no successful fsync is fabricated.
private final class KeyedAncestorSyncFaults: KeyedStorageFileOperations, @unchecked Sendable {
    struct Identity: Equatable, Sendable {
        let device: dev_t
        let inode: ino_t
    }

    struct Event: Sendable {
        let identity: Identity
        let succeeded: Bool
    }

    private let lock = NSLock()
    private let real = POSIXKeyedStorageFileOperations()
    private var failingParent: URL?
    private var recorded: [Event] = []

    init(failingParent: URL) { self.failingParent = failingParent }

    func allowSyncs() {
        lock.lock()
        defer { lock.unlock() }
        failingParent = nil
    }

    func events() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    static func identity(of url: URL) throws -> Identity {
        var info = stat()
        guard fstatat(AT_FDCWD, url.path, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw KeyedStorageFailure.io(errno) }
        return Identity(device: info.st_dev, inode: info.st_ino)
    }

    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) -> Int {
        real.write(descriptor, bytes: bytes)
    }

    func unlink(_ directory: Int32, name: String) -> Int32 {
        real.unlink(directory, name: name)
    }

    func syncDirectory(_ descriptor: Int32) -> Int32 {
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return -1 }
        let identity = Identity(device: info.st_dev, inode: info.st_ino)
        lock.lock()
        let target = failingParent
        lock.unlock()
        let mustFail = target.flatMap { try? Self.identity(of: $0) } == identity
        let result: Int32
        if mustFail { errno = EIO; result = -1 }
        else { result = real.syncDirectory(descriptor) }
        lock.lock()
        recorded.append(Event(identity: identity, succeeded: result == 0))
        lock.unlock()
        return result
    }
}

extension AddonKeyedStorageTests {
    private enum AncestorRecovery: CaseIterable {
        case directRetry, reopenLedger, freshOpen
    }

    @Test func failedRootEntrySyncIsRepairedBeforeAnyDurableRetry() async throws {
        for recovery in AncestorRecovery.allCases {
            try await Self.exerciseAncestorSyncFailure(atRoot: true, storageClass: .data, recovery: recovery)
        }
    }

    @Test func failedDataEntryParentSyncIsRepairedBeforeAnyDurableRetry() async throws {
        for recovery in AncestorRecovery.allCases {
            try await Self.exerciseAncestorSyncFailure(atRoot: false, storageClass: .data, recovery: recovery)
        }
    }

    @Test func failedCacheEntryParentSyncIsRepairedBeforeAnyDurableRetry() async throws {
        for recovery in AncestorRecovery.allCases {
            try await Self.exerciseAncestorSyncFailure(atRoot: false, storageClass: .cache, recovery: recovery)
        }
    }

    /// exerciseAncestorSyncFailure verifies causal real-fsync identity/order across all recovery routes.
    private static func exerciseAncestorSyncFailure(
        atRoot: Bool,
        storageClass: KeyedStorageClass,
        recovery: AncestorRecovery
    ) async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = try Self.identity()
        let namespace = root.appendingPathComponent(KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(identity)))
        let parent = atRoot ? root : namespace
        let faults = KeyedAncestorSyncFaults(failingParent: parent)
        let governor = ResourceGovernor()
        let registrations = [KeyedStorageRegistration(identity: identity)]
        var store = try await AddonKeyedStorage.open(root: root, registrations: registrations,
            governor: governor, fileOperations: faults)
        var owner = try await store.owner(for: identity)
        let baseMemory = await governor.usage(.retainedStateBytes)

        await #expect(throws: KeyedStorageFailure.io(EIO)) {
            try await store.write(Data([1]), key: "k", owner: owner, storageClass: storageClass)
        }
        let parentIdentity = try KeyedAncestorSyncFaults.identity(of: parent)
        let expectedData = 8_192 + (!atRoot && storageClass == .data ? 4_096 : 0)
        let expectedCache = !atRoot && storageClass == .cache ? 4_096 : 0
        #expect(await governor.usage(.diskStateBytes) == expectedData)
        #expect(await governor.usage(.diskCacheBytes) == expectedCache)
        #expect(await governor.usage(.diskBytes) == expectedData + expectedCache)
        #expect(await governor.usage(.retainedStateBytes) == baseMemory + (expectedCache > 0 ? 1_024 : 0))
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(faults.events().filter { $0.identity == parentIdentity && !$0.succeeded }.count == 1)

        switch recovery {
        case .directRetry:
            await #expect(throws: KeyedStorageFailure.io(EIO)) {
                try await store.write(Data([1]), key: "k", owner: owner, storageClass: storageClass)
            }
        case .reopenLedger:
            _ = try await store.close()
            await #expect(throws: KeyedStorageFailure.io(EIO)) { try await store.reopen(root: root) }
            // Also closes an unexpectedly successful old implementation, keeping the RED fixture usable.
            _ = try await store.close()
        case .freshOpen:
            _ = try await store.close()
            let freshGovernor = ResourceGovernor()
            do {
                let unexpected = try await AddonKeyedStorage.open(root: root, registrations: registrations,
                    governor: freshGovernor, fileOperations: faults)
                _ = try await unexpected.close()
                Issue.record("Fresh inventory published storage without repairing its failing ancestor")
            } catch let failure as KeyedStorageFailure { #expect(failure == .io(EIO)) }
            #expect(await freshGovernor.usage(.diskBytes) == 0)
            #expect(await freshGovernor.usage(.retainedStateBytes) == 0)
        }
        #expect(faults.events().filter { $0.identity == parentIdentity && !$0.succeeded }.count == 2)
        #expect(await governor.usage(.diskBytes) == expectedData + expectedCache)
        faults.allowSyncs()
        let beforeRepair = faults.events().count

        switch recovery {
        case .directRetry:
            break
        case .reopenLedger:
            try await store.reopen(root: root)
            owner = try await store.owner(for: identity)
        case .freshOpen:
            store = try await AddonKeyedStorage.open(root: root, registrations: registrations,
                governor: ResourceGovernor(), fileOperations: faults)
            owner = try await store.owner(for: identity)
        }
        if recovery != .directRetry {
            #expect(faults.events().dropFirst(beforeRepair).contains { $0.identity == parentIdentity && $0.succeeded })
        }
        try await store.write(Data([1]), key: "k", owner: owner, storageClass: storageClass)
        #expect(try await store.read(key: "k", owner: owner, storageClass: storageClass) == Data([1]))
        let classIdentity = try KeyedAncestorSyncFaults.identity(of: namespace.appendingPathComponent(storageClass.directoryName))
        let repairedEvents = Array(faults.events().dropFirst(beforeRepair))
        if let repairedParent = repairedEvents.firstIndex(where: { $0.identity == parentIdentity && $0.succeeded }),
           let committedClass = repairedEvents.firstIndex(where: { $0.identity == classIdentity && $0.succeeded }) {
            #expect(repairedParent < committedClass)
        } else {
            Issue.record("A durable write returned without a successful ancestor sync preceding class commit")
        }

        let rootIdentity = try KeyedAncestorSyncFaults.identity(of: root)
        let namespaceIdentity = try KeyedAncestorSyncFaults.identity(of: namespace)
        let rootSyncs = faults.events().filter { $0.identity == rootIdentity }.count
        let namespaceSyncs = faults.events().filter { $0.identity == namespaceIdentity }.count
        try await store.write(Data([2]), key: "another", owner: owner, storageClass: storageClass)
        #expect(faults.events().filter { $0.identity == rootIdentity }.count == rootSyncs)
        #expect(faults.events().filter { $0.identity == namespaceIdentity }.count == namespaceSyncs)
        #expect(try await store.read(key: "another", owner: owner, storageClass: storageClass) == Data([2]))
        _ = try await store.close()
    }
}
