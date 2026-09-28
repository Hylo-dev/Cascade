import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AddonStateStoreTests {
    static let identity = VerifiedAddonIdentity(
        publisher: "publisher.one", addonID: AddonID(rawValue: "com.example.state")!
    )

    static func root() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp/cascade-state-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        return url
    }

    @Test func persistsReopensAndSeparatesPublishers() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = VerifiedAddonIdentity(publisher: "publisher.two", addonID: Self.identity.addonID)
        let store = try await Self.openStore(root: root, identities: [Self.identity, other],
            maximumSchemaVersion: 2)
        let owner = try await store.owner(for: Self.identity)
        let otherOwner = try await store.owner(for: other)
        #expect(try await store.read(owner: owner) == nil)
        try await store.write(Data("saved".utf8), schemaVersion: 1, owner: owner)
        #expect(try await store.read(owner: otherOwner) == nil)
        try await store.close()
        let reopened = try await Self.openStore(root: root, identities: [other, Self.identity],
            maximumSchemaVersion: 2)
        let newOwner = try await reopened.owner(for: Self.identity)
        #expect(try await reopened.read(owner: newOwner)?.data == Data("saved".utf8))
        await #expect(throws: StateStoreFailure.invalidOwner) { try await reopened.read(owner: owner) }
        try await reopened.close()
    }

    @Test func stagingSurvivesInterruptionAndRecoveryPreservesOldState() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let governor = ResourceGovernor()
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 2,
                                                 governor: governor)
        let owner = try await store.owner(for: Self.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let before = await governor.usage(.diskStateBytes)
        _ = try await store.stage(Data([2]), schemaVersion: 2, owner: owner)
        #expect(await governor.usage(.diskStateBytes) > before)
        #expect(try await store.read(owner: owner)?.data == Data([1]))
        try await store.close()
        #expect(await governor.usage(.diskStateBytes) == 0)
        let reopened = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 2,
                                                    governor: governor)
        let newOwner = try await reopened.owner(for: Self.identity)
        #expect(try await reopened.read(owner: newOwner)?.data == Data([1]))
        #expect(await governor.usage(.diskStateBytes) == before)
        try await reopened.close()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func quotasIncludeOldAndStagedDataAndReleaseOnFailure() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let governor = ResourceGovernor()
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1,
                                                 governor: governor, diskBudget: 9_000)
        let owner = try await store.owner(for: Self.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let usage = await governor.usage(.diskBytes)
        await #expect(throws: StateStoreFailure.quotaExceeded) {
            try await store.write(Data(repeating: 2, count: 1_000), schemaVersion: 1, owner: owner)
        }
        #expect(try await store.read(owner: owner)?.data == Data([1]))
        #expect(await governor.usage(.diskBytes) == usage)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        try await store.removeUserData(owner: owner)
        #expect(try await store.read(owner: owner) == nil)
        try await store.close()
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func corruptAndFutureStateAreNotOverwritten() async throws {
        for future in [false, true] {
            let root = try Self.root()
            defer { try? FileManager.default.removeItem(at: root) }
            let other = VerifiedAddonIdentity(publisher: "healthy.publisher", addonID: Self.identity.addonID)
            let store = try await Self.openStore(root: root, identities: [Self.identity, other],
                                                     maximumSchemaVersion: 2)
            let owner = try await store.owner(for: Self.identity)
            try await store.write(Data([1]), schemaVersion: 2, owner: owner)
            let file = try #require(FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: nil).first { $0.pathExtension == "state" })
            let healthy = try await store.owner(for: other)
            try await store.write(Data([9]), schemaVersion: 1, owner: healthy)
            try await store.close()
            if !future { try Data([0]).write(to: file) }
            let reopened = try await Self.openStore(root: root, identities: [Self.identity, other],
                                                        maximumSchemaVersion: 1)
            let newOwner = try await reopened.owner(for: Self.identity)
            let failure: StateStoreFailure = future ? .futureSchema(2) : .corrupt
            await #expect(throws: failure) { try await reopened.read(owner: newOwner) }
            await #expect(throws: failure) { try await reopened.write(Data([3]), schemaVersion: 1, owner: newOwner) }
            let healthyOwner = try await reopened.owner(for: other)
            #expect(try await reopened.read(owner: healthyOwner)?.data == Data([9]))
            try await reopened.removeUserData(owner: newOwner)
            try await reopened.close()
        }
    }

    @Test func rejectsTraversalSymlinksHardlinksAndSpecialFiles() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: StateStoreFailure.unsafePath) {
            try await Self.openStore(root: URL(fileURLWithPath: root.path + "/../" + root.lastPathComponent),
                                           identities: [Self.identity], maximumSchemaVersion: 1)
        }
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        await #expect(throws: StateStoreFailure.unsafePath) {
            try await Self.openStore(root: link, identities: [Self.identity], maximumSchemaVersion: 1)
        }
        try FileManager.default.removeItem(at: link)
        for kind in 0..<3 {
            let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
            let owner = try await store.owner(for: Self.identity)
            try await store.write(Data([1]), schemaVersion: 1, owner: owner)
            try await store.close()
            let file = try #require(FileManager.default.contentsOfDirectory(at: root,
                includingPropertiesForKeys: nil).first { $0.pathExtension == "state" })
            let alias = URL(fileURLWithPath: root.path + "-alias")
            defer { try? FileManager.default.removeItem(at: alias) }
            if kind == 0 {
                try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: alias)
            } else if kind == 1 {
                #expect(Darwin.link(file.path, alias.path) == 0)
            } else {
                try FileManager.default.removeItem(at: file)
                #expect(mkfifo(file.path, 0o600) == 0)
            }
            await #expect(throws: StateStoreFailure.unsafePath) {
                try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
            }
            try FileManager.default.removeItem(at: file)
        }
    }

    @Test func rejectsOversizedBeforeReadingAndUnknownRootEntries() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
        let owner = try await store.owner(for: Self.identity)
        await #expect(throws: StateStoreFailure.oversized) {
            try await store.write(Data(repeating: 1, count: 65_537), schemaVersion: 1, owner: owner)
        }
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        try await store.close()
        let file = try #require(FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "state" })
        #expect(truncate(file.path, 100_000_000) == 0)
        let governor = ResourceGovernor()
        await #expect(throws: StateStoreFailure.oversized) {
            try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1,
                                          governor: governor)
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        try FileManager.default.removeItem(at: file)
        try Data().write(to: root.appendingPathComponent("unknown"))
        await #expect(throws: StateStoreFailure.unrecognizedEntry) {
            try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
        }
    }

    @Test func revocationCancelsAuthorityButPreservesUserData() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
        let owner = try await store.owner(for: Self.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let staged = try await store.stage(Data([2]), schemaVersion: 1, owner: owner)
        try await store.revoke(owner: owner)
        await #expect(throws: StateStoreFailure.invalidOwner) { try await store.commit(staged, owner: owner) }
        let reconnected = try await store.owner(for: Self.identity)
        #expect(try await store.read(owner: reconnected)?.data == Data([1]))
        try await store.close()
    }

    @Test func unchangedWritesAvoidStagingAndRevisionChanges() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1,
                                                 diskBudget: 9_000)
        let owner = try await store.owner(for: Self.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let original = try await store.read(owner: owner)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        #expect(try await store.read(owner: owner) == original)
        try await store.close()
    }

    @Test func checkpointCannotBeMovedAcrossPublisherNamespaces() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = VerifiedAddonIdentity(publisher: "publisher.two", addonID: Self.identity.addonID)
        let store = try await Self.openStore(root: root, identities: [Self.identity, other],
            maximumSchemaVersion: 1)
        let owner = try await store.owner(for: Self.identity)
        let otherOwner = try await store.owner(for: other)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let firstFile = try #require(FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "state" })
        try await store.write(Data([2]), schemaVersion: 1, owner: otherOwner)
        let secondFile = try #require(FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "state" && $0 != firstFile })
        try await store.close()
        try FileManager.default.removeItem(at: secondFile)
        try FileManager.default.copyItem(at: firstFile, to: secondFile)
        let reopened = try await Self.openStore(root: root, identities: [Self.identity, other],
            maximumSchemaVersion: 1)
        let newOwner = try await reopened.owner(for: other)
        await #expect(throws: StateStoreFailure.corrupt) { try await reopened.read(owner: newOwner) }
        try await reopened.close()
    }

    @Test func reopeningAccountsAbandonedStageBeforeCleanupAndRetainsItOnQuotaFailure() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
        let owner = try await store.owner(for: Self.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        _ = try await store.stage(Data([2]), schemaVersion: 1, owner: owner)
        try await store.close()
        let governor = ResourceGovernor()
        await #expect(throws: StateStoreFailure.quotaExceeded) {
            try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1,
                                          governor: governor, diskBudget: 9_000)
        }
        #expect(await governor.usage(.diskBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "stage" }.count == 1)
    }

    @Test func cancellationReleasesReservationsAndAnExclusiveRootRejectsAnotherStore() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let governor = ResourceGovernor()
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1,
                                                 governor: governor)
        let owner = try await store.owner(for: Self.identity)
        let usage = await governor.usage(.retainedStateBytes)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == usage)
        await #expect(throws: StateStoreFailure.busy) {
            try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
        }
        try await store.close()
        let opening = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let cancelled = try await Self.openStore(root: root, identities: [Self.identity],
                maximumSchemaVersion: 1,
                                                          governor: governor)
            try await cancelled.close()
        }
        await #expect(throws: CancellationError.self) { try await opening.value }
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }


    @Test func revocationInvalidatesAuthorityEvenWhenStageCleanupFails() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await Self.openStore(root: root, identities: [Self.identity], maximumSchemaVersion: 1)
        let owner = try await store.owner(for: Self.identity)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        let ticket = try await store.stage(Data([2]), schemaVersion: 1, owner: owner)
        let stage = try #require(FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "stage" })
        let alias = root.appendingPathComponent("alias")
        #expect(Darwin.link(stage.path, alias.path) == 0)
        await #expect(throws: StateStoreFailure.unsafePath) { try await store.revoke(owner: owner) }
        await #expect(throws: StateStoreFailure.invalidOwner) { try await store.read(owner: owner) }
        try FileManager.default.removeItem(at: alias)
        let fresh = try await store.owner(for: Self.identity)
        #expect(try await store.read(owner: fresh)?.data == Data([1]))
        await #expect(throws: StateStoreFailure.invalidTicket) { try await store.commit(ticket, owner: fresh) }
        try await store.revoke(owner: fresh)
        try await store.close()
    }


    @Test func heterogeneousSchemaCeilingsPreserveFutureOwnerAndAllowHealthyOwner() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = VerifiedAddonIdentity(publisher: "publisher.three", addonID: Self.identity.addonID)
        let store = try await Self.openRegistered(root: root, schemas: [(Self.identity, 2), (other, 3)])
        let owner = try await store.owner(for: Self.identity)
        let healthy = try await store.owner(for: other)
        try await store.write(Data([2]), schemaVersion: 2, owner: owner)
        let futureFile = try #require(FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).first { $0.pathExtension == "state" })
        let preservedBytes = try Data(contentsOf: futureFile)
        try await store.write(Data([3]), schemaVersion: 3, owner: healthy)
        try await store.close()
        let governor = ResourceGovernor()
        let reopened = try await Self.openRegistered(root: root, schemas: [(Self.identity, 1), (other, 3)],
                                                    governor: governor)
        let future = try await reopened.owner(for: Self.identity)
        let healthyAgain = try await reopened.owner(for: other)
        let disk = await governor.usage(.diskBytes)
        await #expect(throws: StateStoreFailure.futureSchema(2)) { try await reopened.read(owner: future) }
        await #expect(throws: StateStoreFailure.futureSchema(2)) {
            try await reopened.write(Data([1]), schemaVersion: 1, owner: future)
        }
        #expect(await governor.usage(.diskBytes) == disk)
        #expect(try Data(contentsOf: futureFile) == preservedBytes)
        #expect(try await reopened.read(owner: healthyAgain)?.data == Data([3]))
        try await reopened.write(Data([4]), schemaVersion: 3, owner: healthyAgain)
        #expect(try await reopened.read(owner: healthyAgain)?.data == Data([4]))
        try await reopened.removeUserData(owner: future)
        try await reopened.write(Data([1]), schemaVersion: 1, owner: future)
        await #expect(throws: StateStoreFailure.invalidConfiguration) {
            try await reopened.stage(Data([2]), schemaVersion: 2, owner: future)
        }
        await #expect(throws: StateStoreFailure.invalidConfiguration) {
            try await reopened.beginMigration(to: 2, owner: future)
        }
        try await reopened.close()
    }

    @Test func hundredInactiveNamespacesLeaveSharedCapacityForRealStateAdmission() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let schemas = (0..<100).map {
            (VerifiedAddonIdentity(publisher: "inactive", addonID: AddonID(rawValue: "com.example.inactive\($0)")!),
             UInt32(1))
        }
        let governor = ResourceGovernor()
        let store = try await Self.openRegistered(root: root, schemas: schemas, governor: governor)
        let unrelated = try await governor.admit(.state(bytes: 7 * 1_024 * 1_024), owner: Self.identity.addonID)
        let lastOwner = try await store.owner(for: schemas[99].0)
        #expect(try await store.read(owner: lastOwner) == nil)
        try await store.close()
        #expect(await governor.usage(.retainedStateBytes) == 7 * 1_024 * 1_024 + 1_024)
        try await governor.release(unrelated.id, owner: unrelated.owner)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test func boundsRetainedRegistryAt256AndHonorsATighterHostLimit() async throws {
        let root = try Self.root()
        defer { try? FileManager.default.removeItem(at: root) }
        let schemas = (0..<256).map {
            (VerifiedAddonIdentity(publisher: "retained", addonID: AddonID(rawValue: "com.example.retained\($0)")!),
             UInt32(1))
        }
        let store = try await Self.openRegistered(root: root, schemas: schemas)
        let owner = try await store.owner(for: schemas[255].0)
        try await store.write(Data([1]), schemaVersion: 1, owner: owner)
        #expect(try await store.read(owner: owner)?.data == Data([1]))
        try await store.close()
        await #expect(throws: StateStoreFailure.invalidConfiguration) {
            try await Self.openRegistered(root: root, schemas: schemas + [(Self.identity, 1)])
        }
        await #expect(throws: StateStoreFailure.invalidConfiguration) {
            try await Self.openRegistered(root: root, schemas: schemas, namespaceLimit: 100)
        }
    }

    static func openRegistered(
        root: URL, schemas: [(VerifiedAddonIdentity, UInt32)], governor: ResourceGovernor = ResourceGovernor(),
        namespaceLimit: Int = 256
    ) async throws -> AddonStateStore {
        try await AddonStateStore.open(root: root, registrations: schemas.map {
            StateRegistration(identity: $0.0, maximumSchemaVersion: $0.1)
        }, namespaceLimit: namespaceLimit, governor: governor)
    }

    static func openStore(
        root: URL, identities: [VerifiedAddonIdentity], maximumSchemaVersion: UInt32,
        governor: ResourceGovernor = ResourceGovernor(), diskBudget: Int = 100 * 1_024 * 1_024
    ) async throws -> AddonStateStore {
        try await AddonStateStore.open(root: root, registrations: identities.map {
            StateRegistration(identity: $0, maximumSchemaVersion: maximumSchemaVersion)
        }, governor: governor, diskBudget: diskBudget)
    }

}
