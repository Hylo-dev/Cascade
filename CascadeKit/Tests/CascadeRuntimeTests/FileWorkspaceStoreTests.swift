import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct FileWorkspaceStoreTests {
    private let owner: AddonID

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.file-workspace"))
    }

    @Test
    func reopenPreservesOrderIDsAndDeduplicatesOnlyTheSameOriginal() async throws {
        let fixture = try Fixture(owner: owner)
        let first   = try fixture.file(name: "same.txt", contents: "first")
        let folder  = try fixture.folder(name: "other")
        let second  = try fixture.file(in: folder, name: "same.txt", contents: "second")
        let initial = try await fixture.store()

        let ids = try await initial.addOriginals([first, first, second])
        #expect(ids.count == 2)
        try await initial.close()

        let reopened = try await fixture.store(lifetime: initial.namespaceLifetime)
        try await reopened.restore()
        let snapshot = try await reopened.snapshot(cursor: nil)
        #expect(snapshot.entries.map(\.id) == ids)
        #expect(snapshot.entries.map(\.name) == ["same.txt", "same.txt"])
        #expect(snapshot.entries.allSatisfy { $0.ownership == .externalReference })
    }

    @Test
    func unavailableOrReplacedOriginalRemainsVisibleWithoutFollowingSymlinks() async throws {
        let fixture = try Fixture(owner: owner)
        let source  = try fixture.file(name: "source.txt", contents: "one")
        let store   = try await fixture.store()
        let id      = try #require(try await store.addOriginals([source]).first)

        try FileManager.default.removeItem(at: source)
        try FileManager.default.createSymbolicLink(
            at        : source,
            withDestinationURL: try fixture.file(name: "replacement.txt", contents: "two")
        )

        let snapshot = try await store.snapshot(cursor: nil)
        #expect(snapshot.entries.map(\.id) == [id])
        #expect(snapshot.entries.first?.availability == .unavailable)
    }

    @Test
    func corruptOrFutureManifestBlocksMutationWithoutBeingOverwritten() async throws {
        for data in [Data("not-json".utf8), Data("{\"version\":2,\"revision\":0,\"entries\":[]}".utf8)] {
            let fixture = try Fixture(owner: owner)
            try data.write(to: fixture.manifestURL)
            let original = try Data(contentsOf: fixture.manifestURL)
            let store    = try await fixture.store(restore: false)

            await #expect(throws: FileWorkspaceError.ioFailure) {
                try await store.restore()
            }
            await #expect(throws: FileWorkspaceError.self) {
                _ = try await store.addOriginals([try fixture.file(name: "new.txt", contents: "new")])
            }
            #expect(try Data(contentsOf: fixture.manifestURL) == original)
        }
    }

    @Test
    func persistenceRejectsASymlinkNamespaceLeaf() async throws {
        let fixture = try Fixture(owner: owner)
        let alias = fixture.root.deletingLastPathComponent().appendingPathComponent("workspace-link")
        try FileManager.default.createSymbolicLink(
            at        : alias,
            withDestinationURL: fixture.root
        )
        let persistence = FoundationFileWorkspacePersistence(directory: alias)

        await #expect(throws: (any Error).self) {
            try await persistence.save(Data("owned".utf8))
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.manifestURL.path))
    }

    @Test
    func failedSavePublishesNeitherEntriesNorRevision() async throws {
        let fixture    = try Fixture(owner: owner)
        let persistent = FailingFileWorkspacePersistence(base: fixture.persistence)
        let store      = try await fixture.store(persistence: persistent)
        let before     = try await store.snapshot(cursor: nil)
        await persistent.failNextSave()

        await #expect(throws: FileWorkspaceError.ioFailure) {
            _ = try await store.addOriginals([try fixture.file(name: "nope.txt", contents: "nope")])
        }
        let after = try await store.snapshot(cursor: nil)
        #expect(after.entries.isEmpty)
        #expect(after.revision == before.revision)
    }

    @Test
    func paginationIsBoundedByCountAndBytesAndRejectsStaleCursor() async throws {
        let fixture = try Fixture(owner: owner)
        let store   = try await fixture.store()
        let urls = try (0..<40).map { index in
            try fixture.file(
                name    : String(repeating: "n", count: 200) + "-\(index).txt",
                contents: "\(index)"
            )
        }
        _ = try await store.addOriginals(urls)
        let first = try await store.snapshot(cursor: nil)
        #expect(first.entries.count <= 32)
        #expect(try first.encode().count <= 65_536)
        let cursor = try #require(first.nextCursor)

        _ = try await store.addOriginals([try fixture.file(name: "new.txt", contents: "new")])
        await #expect(throws: FileWorkspaceError.staleRevision) {
            _ = try await store.snapshot(cursor: cursor)
        }
    }

    @Test
    func deliveryRemovesOnlySucceededItemsAndLateReceiptsCannotRemoveReopenedEntries() async throws {
        let fixture = try Fixture(owner: owner)
        let first   = try fixture.file(name: "first.txt", contents: "first")
        let second  = try fixture.file(name: "second.txt", contents: "second")
        let store   = try await fixture.store()
        let ids     = try await store.addOriginals([first, second])
        let delivery = try await store.beginDelivery(ids: ids)

        try await store.finishDelivery(delivery, itemID: ids[0], result: .success(()))
        try await store.finishDelivery(delivery, itemID: ids[1], result: .failure(.interrupted))
        #expect(try await store.snapshot(cursor: nil).entries.map(\.id) == [ids[1]])
        try await store.close()

        let reopened = try await fixture.store(lifetime: store.namespaceLifetime)
        try await reopened.restore()
        try await reopened.finishDelivery(delivery, itemID: ids[1], result: .success(()))
        #expect(try await reopened.snapshot(cursor: nil).entries.map(\.id) == [ids[1]])
    }

    @Test
    func managedCopyUsesRealQuotaAndStaysChargedWhenCleanupFails() async throws {
        let governor = ResourceGovernor()
        _ = try await governor.admit(
            .diskState(bytes: 9 * 1_024 * 1_024),
            owner: owner
        )
        let fixture  = try Fixture(owner: owner, governor: governor)
        let store    = try await fixture.store()
        let accepted = try fixture.file(name: "accepted.bin", data: Data(repeating: 1, count: 65_536))
        _ = try await store.importPromisedFile(accepted)
        let charged = await governor.usage(.diskStateBytes, owner: owner)
        #expect(charged >= 65_536)

        let denied = try fixture.file(name: "denied.bin", data: Data(repeating: 2, count: 2 * 1_024 * 1_024))
        await #expect(throws: FileWorkspaceError.quotaExceeded) {
            _ = try await store.importPromisedFile(denied)
        }
        #expect(await governor.usage(.diskStateBytes, owner: owner) >= charged)
    }

    @Test
    func overlappingDeliveriesPinManagedBytesUntilEveryReceiptFinishes() async throws {
        let fixture = try Fixture(owner: owner)
        let store   = try await fixture.store()
        let id = try await store.importPromisedFile(
            try fixture.file(name: "managed.bin", data: Data(repeating: 7, count: 4_096))
        )
        let path = fixture.root.appendingPathComponent("managed/\(id.uuidString)").path
        let first  = try await store.beginDelivery(ids: [id])
        let second = try await store.beginDelivery(ids: [id])

        try await store.finishDelivery(first, itemID: id, result: .success(()))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try await store.snapshot(cursor: nil).entries.isEmpty)

        let reopened = try await fixture.store(lifetime: store.namespaceLifetime)
        await #expect(throws: FileWorkspaceError.interrupted) {
            try await reopened.restore()
        }
        try await store.finishDelivery(second, itemID: id, result: .failure(.interrupted))
        #expect(!FileManager.default.fileExists(atPath: path))
        try await store.close()
        try await reopened.restore()
    }

    @Test
    func blockedStoreCanSettleFailureReceiptAndReleaseEveryDeliveryPin() async throws {
        let fixture  = try Fixture(owner: owner)
        let resources = GatedRuntimeResourceAccess(target: fixture.governor)
        let lifetime = FileWorkspaceNamespaceLifetime(
            directory: fixture.root,
            owner    : owner,
            resources: resources
        )
        let store = FileWorkspaceStore(
            directory  : fixture.root,
            owner      : owner,
            resources  : resources,
            persistence: fixture.persistence,
            references : FoundationFileReferenceResolver(),
            lifetime   : lifetime
        )
        try await store.restore()
        let id = try await store.importPromisedFile(
            try fixture.file(name: "settled.bin", data: Data(repeating: 5, count: 4_096))
        )
        let first  = try await store.beginDelivery(ids: [id])
        let second = try await store.beginDelivery(ids: [id])

        await resources.armWorkspaceReconcile()
        let finishing = Task {
            try await store.finishDelivery(first, itemID: id, result: .success(()))
        }
        await resources.waitForArrival()
        finishing.cancel()
        try await finishing.value

        await #expect(throws: FileWorkspaceError.ioFailure) {
            _ = try await store.snapshot(cursor: nil)
        }
        try await store.finishDelivery(second, itemID: id, result: .failure(.interrupted))
        try await store.close()

        let reopened = FileWorkspaceStore(
            directory  : fixture.root,
            owner      : owner,
            resources  : resources,
            persistence: fixture.persistence,
            references : FoundationFileReferenceResolver(),
            lifetime   : lifetime
        )
        try await reopened.restore()
        #expect(try await reopened.snapshot(cursor: nil).entries.isEmpty)
    }

    @Test
    func failedManagedCleanupKeepsBytesAndGovernorCharge() async throws {
        let fixture = try Fixture(owner: owner)
        let store   = try await fixture.store()
        let id = try await store.importPromisedFile(
            try fixture.file(name: "retained.bin", data: Data(repeating: 9, count: 4_096))
        )
        let managed = fixture.root.appendingPathComponent("managed")
        let path    = managed.appendingPathComponent(id.uuidString).path
        let delivery = try await store.beginDelivery(ids: [id])
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: managed.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: managed.path)
        }

        try await store.finishDelivery(delivery, itemID: id, result: .success(()))
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(await fixture.governor.usage(.diskStateBytes, owner: owner) >= 4_096)
    }

    @Test
    func sharedNamespaceLifetimeSerializesAcrossSuspensionAndAvoidsDoubleAccounting() async throws {
        let fixture = try Fixture(owner: owner)
        let gate    = SuspendingFileWorkspacePersistence(base: fixture.persistence)
        let first   = try await fixture.store(persistence: gate)
        let second  = try await fixture.store(persistence: gate, lifetime: first.namespaceLifetime)
        let source  = try fixture.file(name: "race.txt", contents: "race")

        await gate.suspendNextSave()
        let task = Task { try await first.addOriginals([source]) }
        await gate.waitUntilSuspended()
        await #expect(throws: FileWorkspaceError.interrupted) {
            _ = try await second.addOriginals([source])
        }
        await gate.resumeSave()
        _ = try await task.value

        let before = await fixture.governor.usage(.diskStateBytes, owner: owner)
        try await first.close()
        try await second.restore()
        let after = await fixture.governor.usage(.diskStateBytes, owner: owner)
        #expect(after == before)
    }

    @Test
    func memoryReservationResizePreservesAuthorityKindAndAccounting() async throws {
        let governor = ResourceGovernor()
        let foreign  = try #require(AddonID(rawValue: "com.example.foreign"))
        let memory = try await governor.admit(
            .temporaryMemory(bytes: 100),
            owner: owner
        )
        let state = try await governor.admit(
            .state(bytes: 100),
            owner: owner
        )
        await #expect(throws: AddonFailure.self) {
            try await governor.resizeMemoryReservation(
                memory.id,
                owner    : foreign,
                fromBytes: 100,
                toBytes  : 50
            )
        }
        #expect(try await !governor.resizeMemoryReservation(
            memory.id,
            owner    : owner,
            fromBytes: 99,
            toBytes  : 50
        ))
        #expect(try await !governor.resizeMemoryReservation(
            state.id,
            owner    : owner,
            fromBytes: 100,
            toBytes  : 50
        ))
        #expect(try await governor.resizeMemoryReservation(
            memory.id,
            owner    : owner,
            fromBytes: 100,
            toBytes  : 40
        ))
        #expect(await governor.usage(.admittedMemoryBytes, owner: owner) == 40)

        _ = try await governor.admit(.provider, owner: owner)
        let before = await governor.usage(.admittedMemoryBytes, owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await governor.resizeMemoryReservation(
                memory.id,
                owner    : owner,
                fromBytes: 40,
                toBytes  : 65 * 1_024 * 1_024
            )
        }
        #expect(await governor.usage(.admittedMemoryBytes, owner: owner) == before)
    }

    @Test
    func cancellationAfterManifestCommitPreservesCommittedEntryForReopen() async throws {
        let fixture  = try Fixture(owner: owner)
        let resources = GatedRuntimeResourceAccess(target: fixture.governor)
        let lifetime = FileWorkspaceNamespaceLifetime(
            directory: fixture.root,
            owner    : owner,
            resources: resources
        )
        let store = FileWorkspaceStore(
            directory  : fixture.root,
            owner      : owner,
            resources  : resources,
            persistence: fixture.persistence,
            references : FoundationFileReferenceResolver(),
            lifetime   : lifetime
        )
        try await store.restore()
        let source = try fixture.file(name: "committed.txt", contents: "committed")
        await resources.armWorkspaceReconcile()
        let insertion = Task { try await store.addOriginals([source]) }
        await resources.waitForArrival()
        insertion.cancel()
        let ids = try await insertion.value
        await #expect(throws: FileWorkspaceError.ioFailure) {
            _ = try await store.snapshot(cursor: nil)
        }
        try await store.close()

        let reopened = FileWorkspaceStore(
            directory  : fixture.root,
            owner      : owner,
            resources  : resources,
            persistence: fixture.persistence,
            references : FoundationFileReferenceResolver(),
            lifetime   : lifetime
        )
        try await reopened.restore()
        #expect(try await reopened.snapshot(cursor: nil).entries.map(\.id) == ids)
    }

    @Test
    func deliveryLeaseKeepsTheCheckedOriginalReadableAfterItsPathDisappears() async throws {
        let fixture = try Fixture(owner: owner)
        let source  = try fixture.file(name: "leased.txt", contents: "leased")
        let store   = try await fixture.store()
        let id      = try #require(try await store.addOriginals([source]).first)
        let delivery = try await store.beginDelivery(ids: [id])
        let lease    = try await store.leaseForDelivery(delivery, itemID: id)
        try FileManager.default.removeItem(at: source)
        var bytes = [UInt8](repeating: 0, count: 6)
        let count = bytes.withUnsafeMutableBytes {
            Darwin.read(lease.descriptor, $0.baseAddress, $0.count)
        }
        lease.close()

        #expect(count == 6)
        #expect(String(decoding: bytes, as: UTF8.self) == "leased")
        try await store.finishDelivery(delivery, itemID: id, result: .failure(.interrupted))
    }

    @Test
    func uncertainManifestCommitPreservesManagedBytesAndBlocksUntilReopen() async throws {
        let fixture = try Fixture(owner: owner)
        let persistence = UncertainFileWorkspacePersistence(base: fixture.persistence)
        let store = try await fixture.store(persistence: persistence)
        await persistence.makeNextSaveUncertain()
        await #expect(throws: FileWorkspaceError.ioFailure) {
            _ = try await store.importPromisedFile(
                try fixture.file(name: "uncertain.bin", data: Data(repeating: 4, count: 4_096))
            )
        }
        let managed = fixture.root.appendingPathComponent("managed")
        let files = try FileManager.default.contentsOfDirectory(atPath: managed.path)
        #expect(files.count == 1)
        await #expect(throws: FileWorkspaceError.ioFailure) {
            _ = try await store.snapshot(cursor: nil)
        }
        try await store.close()

        let reopened = try await fixture.store(lifetime: store.namespaceLifetime)
        try await reopened.restore()
        let entry = try #require(try await reopened.snapshot(cursor: nil).entries.first)
        #expect(files == [entry.id.uuidString])
    }
}

private struct Fixture {
    let root       : URL
    let inputs     : URL
    let persistence: FoundationFileWorkspacePersistence
    let owner      : AddonID
    let governor   : ResourceGovernor
    let lifetime   : FileWorkspaceNamespaceLifetime

    var manifestURL: URL { root.appendingPathComponent("manifest.json") }

    init(
        owner   : AddonID,
        governor: ResourceGovernor = ResourceGovernor()
    ) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root     = base.appendingPathComponent("workspace")
        inputs   = base.appendingPathComponent("inputs")
        self.owner    = owner
        self.governor = governor
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        persistence = FoundationFileWorkspacePersistence(directory: root)
        lifetime = FileWorkspaceNamespaceLifetime(
            directory: root,
            owner    : owner,
            resources: governor
        )
    }

    func folder(name: String) throws -> URL {
        let url = inputs.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func file(
        in directory: URL? = nil,
        name        : String,
        contents    : String
    ) throws -> URL {
        try file(in: directory, name: name, data: Data(contents.utf8))
    }

    func file(
        in directory: URL? = nil,
        name        : String,
        data        : Data
    ) throws -> URL {
        let url = (directory ?? inputs).appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func store(
        persistence: (any FileWorkspacePersisting)? = nil,
        lifetime   : FileWorkspaceNamespaceLifetime? = nil,
        restore    : Bool = true
    ) async throws -> FileWorkspaceStore {
        let store = FileWorkspaceStore(
            directory  : root,
            owner      : owner,
            resources  : governor,
            persistence: persistence ?? self.persistence,
            references : FoundationFileReferenceResolver(),
            lifetime   : lifetime ?? self.lifetime
        )
        if lifetime == nil, restore { try await store.restore() }
        return store
    }
}

private actor FailingFileWorkspacePersistence: FileWorkspacePersisting {
    let base: FoundationFileWorkspacePersistence
    private var shouldFail = false

    init(base: FoundationFileWorkspacePersistence) { self.base = base }

    func failNextSave() { shouldFail = true }
    func load() async throws -> Data? { try await base.load() }
    func save(_ data: Data) async throws {
        if shouldFail {
            shouldFail = false
            throw CocoaError(.fileWriteUnknown)
        }
        try await base.save(data)
    }
}

private actor SuspendingFileWorkspacePersistence: FileWorkspacePersisting {
    let base: FoundationFileWorkspacePersistence
    private var shouldSuspend = false
    private var suspended = false
    private var waiter   : CheckedContinuation<Void, Never>?
    private var resume   : CheckedContinuation<Void, Never>?

    init(base: FoundationFileWorkspacePersistence) { self.base = base }

    func suspendNextSave() { shouldSuspend = true }
    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resumeSave() { resume?.resume(); resume = nil; suspended = false }
    func load() async throws -> Data? { try await base.load() }
    func save(_ data: Data) async throws {
        if shouldSuspend {
            shouldSuspend = false
            suspended = true
            waiter?.resume()
            waiter = nil
            await withCheckedContinuation { resume = $0 }
        }
        try await base.save(data)
    }
}

private actor UncertainFileWorkspacePersistence: FileWorkspacePersisting {
    let base: FoundationFileWorkspacePersistence
    private var uncertain = false

    init(base: FoundationFileWorkspacePersistence) { self.base = base }

    func makeNextSaveUncertain() { uncertain = true }
    func load() async throws -> Data? { try await base.load() }
    func save(_ data: Data) async throws {
        try await base.save(data)
        if uncertain {
            uncertain = false
            throw FileWorkspacePersistenceFailure.commitUncertain
        }
    }
}
