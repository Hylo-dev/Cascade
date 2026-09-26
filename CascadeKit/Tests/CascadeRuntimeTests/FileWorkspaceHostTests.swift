import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct FileWorkspaceHostTests {
    @Test
    func snapshotPagesTwelveEntriesWithoutSkipping() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let sources = try (0..<25).map {
            try fixture.file(name: "item-\($0).txt", contents: "\($0)")
        }
        _ = try await host.addOriginals(sources)

        let first  = try await host.snapshot()
        let second = try await host.snapshot(cursor: try #require(first.nextCursor))
        let third  = try await host.snapshot(cursor: try #require(second.nextCursor))

        #expect(first.entries.count == 12)
        #expect(second.entries.count == 12)
        #expect(third.entries.count == 1)
        #expect((first.entries + second.entries + third.entries).map(\.name) == sources.map(\.lastPathComponent))
    }

    @Test
    func copyUsesPreparedLifetimeAndRemovesOnlyAfterDurableSuccess() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "original")
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("copied.txt")

        try await host.copy(prepared, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "original")
        #expect(try String(contentsOf: source, encoding: .utf8) == "original")
        #expect(try await host.snapshot().entries.isEmpty)
    }

    @Test
    func collisionNeverOverwritesAndKeepsTheEntry() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "source")
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("existing.txt")
        try Data("existing".utf8).write(to: destination)

        await #expect(throws: FileWorkspaceError.ioFailure) {
            try await host.copy(prepared, to: destination)
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "existing")
        #expect(try await host.snapshot().entries.map(\.id) == [id])
    }

    @Test
    func relinkPreservesIdentityAndOrderButInvalidatesPreparedLifetime() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let first = try fixture.file(name: "first.txt", contents: "first")
        let second = try fixture.file(name: "second.txt", contents: "second")
        let ids = try await host.addOriginals([first, second])
        let before = try await host.snapshot()
        let prepared = try #require(try await host.prepareItems(ids: [ids[0]]).first)
        try FileManager.default.removeItem(at: first)
        let replacement = try fixture.file(name: "replacement.txt", contents: "replacement")

        try await host.relinkExternalReference(
            id      : ids[0],
            to      : replacement,
            revision: before.revision
        )

        let after = try await host.snapshot()
        #expect(after.entries.map(\.id) == ids)
        #expect(after.entries.map(\.name) == ["replacement.txt", "second.txt"])
        #expect(after.revision == before.revision + 1)
        await #expect(throws: FileWorkspaceError.unavailable) {
            try await host.copy(
                prepared,
                to: fixture.output.appendingPathComponent("stale.txt")
            )
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.output.appendingPathComponent("stale.txt").path))
    }

    @Test
    func removingReferencePersistsWithoutDeletingTheOriginal() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "kept.txt", contents: "kept")
        let id = try #require(try await host.addOriginals([source]).first)
        let revision = try await host.snapshot().revision

        try await host.removeExternalReference(id: id, revision: revision)
        try await host.close()

        let reopened = try fixture.host()
        try await reopened.restore()
        #expect(try await reopened.snapshot().entries.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "kept")
    }

    @Test
    func concurrentPromiseCopiesAndRefreshAreSerializedWithoutLosingReceipts() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let first  = try fixture.file(name: "first.txt", contents: "first")
        let second = try fixture.file(name: "second.txt", contents: "second")
        let ids = try await host.addOriginals([first, second])
        let prepared = try await host.prepareItems(ids: ids)

        async let firstCopy: Void = host.copy(
            prepared[0],
            to: fixture.output.appendingPathComponent("first.txt")
        )
        async let secondCopy: Void = host.copy(
            prepared[1],
            to: fixture.output.appendingPathComponent("second.txt")
        )
        async let refresh = host.snapshot()
        _ = try await (firstCopy, secondCopy, refresh)

        #expect(try await host.snapshot().entries.isEmpty)
        #expect(try String(
            contentsOf: fixture.output.appendingPathComponent("first.txt"),
            encoding  : .utf8
        ) == "first")
        #expect(try String(
            contentsOf: fixture.output.appendingPathComponent("second.txt"),
            encoding  : .utf8
        ) == "second")
    }

    @Test
    func copyPreservesModeAndExtendedAttributes() async throws {
        let fixture = try HostFixture()
        let host    = try fixture.host()
        try await host.restore()
        let source = try fixture.file(name: "tool", contents: "executable")
        #expect(chmod(source.path, 0o751) == 0)
        let attribute = Data("shelf-metadata".utf8)
        let attributeName = "com.example.cascade-shelf-test"
        let setResult = attribute.withUnsafeBytes { bytes in
            setxattr(source.path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
        }
        #expect(setResult == 0)
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("tool")

        try await host.copy(prepared, to: destination)

        var info = stat()
        #expect(stat(destination.path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o751)
        let size = getxattr(destination.path, attributeName, nil, 0, 0, 0)
        #expect(size == attribute.count)
        var copiedAttribute = Data(count: max(0, size))
        let read = copiedAttribute.withUnsafeMutableBytes { bytes in
            getxattr(destination.path, attributeName, bytes.baseAddress, bytes.count, 0, 0)
        }
        #expect(read == attribute.count)
        #expect(copiedAttribute == attribute)
    }

    @Test
    func cancellationAfterLeaseSettlesDeliveryAndHostCanReopen() async throws {
        let fixture = try HostFixture()
        let barrier = DeliveryLeaseBarrier()
        let host = try FileWorkspaceHost(
            directory        : fixture.workspace,
            governor         : fixture.governor,
            afterDeliveryLease: { await barrier.suspend() }
        )
        try await host.restore()
        let source = try fixture.file(name: "source.txt", contents: "source")
        let id = try #require(try await host.addOriginals([source]).first)
        let prepared = try #require(try await host.prepareItems(ids: [id]).first)
        let destination = fixture.output.appendingPathComponent("cancelled.txt")

        let copy = Task { try await host.copy(prepared, to: destination) }
        await barrier.waitUntilSuspended()
        copy.cancel()
        await barrier.resume()

        await #expect(throws: FileWorkspaceError.interrupted) { try await copy.value }
        #expect(try await host.snapshot().entries.map(\.id) == [id])
        try await host.close()
        let reopened = try fixture.host()
        try await reopened.restore()
        #expect(try await reopened.snapshot().entries.map(\.id) == [id])
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}

private actor DeliveryLeaseBarrier {
    private var suspended = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspended = true
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters = []
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func resume() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private struct HostFixture {
    let base     : URL
    let workspace: URL
    let inputs   : URL
    let output   : URL
    let governor = ResourceGovernor()

    init() throws {
        base      = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        workspace = base.appendingPathComponent("workspace")
        inputs    = base.appendingPathComponent("inputs")
        output    = base.appendingPathComponent("output")
        for directory in [workspace, inputs, output] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workspace.path)
    }

    func host() throws -> FileWorkspaceHost {
        try FileWorkspaceHost(
            directory: workspace,
            governor : governor
        )
    }

    func file(name: String, contents: String) throws -> URL {
        let url = inputs.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
