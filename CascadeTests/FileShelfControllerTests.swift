import CascadeContracts
import CascadeRuntime
import Foundation
import AppKit
import SwiftUI
import Testing
@testable import Cascade

@Suite
struct FileShelfControllerTests {
    @MainActor
    @Test
    func restoreAdmissionAndPaginationStayBounded() async throws {
        let fixture = try FileShelfFixture()
        var preferences: [Bool] = []
        let controller = FileShelfController(
            host: fixture.host,
            preferenceChanged: { preferences.append($0) }
        )

        await controller.start()
        #expect(controller.presentation.snapshot.entries.isEmpty)
        #expect(preferences == [false])

        let files = try (0..<25).map {
            try fixture.file(name: "item-\($0).txt", contents: "\($0)")
        }
        await controller.acceptRegularFiles(files)

        #expect(controller.isOccupied)
        #expect(controller.admissionSequence == 1)
        #expect(!controller.keepsExpandedPresentation)
        #expect(controller.contentHeight == 144)
        #expect(controller.presentation.snapshot.entries.count == 12)
        #expect(controller.presentation.snapshot.totalCount == 25)
        #expect(controller.presentation.actions.count <= 64)
        #expect(controller.preparedFiles.count == 12)
        #expect(preferences.last == true)

        let open = try #require(controller.presentation.action(for: .openList))
        let updateCount = preferences.count
        await controller.perform(open)
        #expect(preferences.count == updateCount + 1)
        let selected = controller.presentation.snapshot.entries.prefix(2).map(\.id)
        for id in selected {
            let action = try #require(controller.presentation.action(for: .select, entryID: id))
            await controller.perform(action)
        }
        #expect(controller.presentation.selectedEntryIDs == selected)

        let next = try #require(controller.presentation.action(for: .nextPage))
        await controller.perform(next)
        #expect(controller.presentation.snapshot.entries.count == 12)
        #expect(controller.presentation.snapshot.entries.first?.name == "item-12.txt")
        #expect(controller.presentation.selectedEntryIDs.isEmpty)

        let close = try #require(controller.presentation.action(for: .closeList))
        await controller.perform(close)
        #expect(controller.presentation.mode == .deck)
        #expect(controller.presentation.snapshot.entries.first?.name == "item-0.txt")
    }

    @MainActor
    @Test
    func hoverIsTransientAndNilClearingIsIdempotent() async throws {
        let fixture = try FileShelfFixture()
        let controller = FileShelfController(host: fixture.host, preferenceChanged: { _ in })
        await controller.start()
        let files = try (0..<5).map {
            try fixture.file(name: "hover-\($0).png", contents: "image")
        }

        controller.showHover(files)
        #expect(controller.presentation.snapshot.entries.count == 5)
        #expect(controller.presentation.snapshot.totalCount == 5)
        #expect(controller.presentation.actions.isEmpty)
        #expect(controller.statusMessage == "Rilascia per aggiungere")

        controller.showHover(nil)
        let clearedRevision = controller.contentRevision
        #expect(controller.presentation.snapshot.entries.isEmpty)
        controller.showHover(nil)
        #expect(controller.contentRevision == clearedRevision)
    }

    @MainActor
    @Test
    func admissionAcknowledgementIsMonotonicAndRejectsAStaleCallback() async throws {
        let fixture = try FileShelfFixture()
        let controller = FileShelfController(host: fixture.host, preferenceChanged: { _ in })
        await controller.start()

        await controller.acceptRegularFiles([
            try fixture.file(name: "first.txt", contents: "first")
        ])
        #expect(controller.admissionSequence == 1)
        #expect(controller.pendingAdmissionSequence == 1)
        controller.consumeAdmissionAnimation(1)
        #expect(controller.pendingAdmissionSequence == 0)

        await controller.acceptRegularFiles([
            try fixture.file(name: "second.txt", contents: "second")
        ])
        #expect(controller.admissionSequence == 2)
        #expect(controller.pendingAdmissionSequence == 2)
        controller.consumeAdmissionAnimation(1)
        #expect(controller.pendingAdmissionSequence == 2)
        controller.consumeAdmissionAnimation(2)
        #expect(controller.pendingAdmissionSequence == 0)
    }

    @MainActor
    @Test
    func unsupportedDropShowsOneHonestMessage() async throws {
        let fixture = try FileShelfFixture()
        let controller = FileShelfController(host: fixture.host, preferenceChanged: { _ in })
        await controller.start()

        controller.showUnsupportedDrop()

        #expect(controller.statusMessage == "Sono accettati solo file locali regolari, non cartelle o file promessi.")
        #expect(!controller.isOccupied)
        #expect(!controller.keepsExpandedPresentation)
    }

    @MainActor
    @Test
    func removingAnExternalReferenceKeepsTheOriginal() async throws {
        let fixture = try FileShelfFixture()
        let controller = FileShelfController(host: fixture.host, preferenceChanged: { _ in })
        await controller.start()
        let source = try fixture.file(name: "originale.txt", contents: "resta")
        await controller.acceptRegularFiles([source])
        let id = try #require(controller.presentation.snapshot.entries.first?.id)
        await controller.perform(try #require(controller.presentation.action(for: .openList)))
        await controller.perform(try #require(
            controller.presentation.action(for: .remove, entryID: id)
        ))

        #expect(controller.presentation.snapshot.entries.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "resta")
    }

    @MainActor
    @Test
    func clearingEveryPageKeepsOriginalsAndStopsPreferringTheShelf() async throws {
        let fixture = try FileShelfFixture()
        var preferences: [Bool] = []
        let controller = FileShelfController(
            host: fixture.host,
            preferenceChanged: { preferences.append($0) }
        )
        await controller.start()
        let sources = try (0..<25).map {
            try fixture.file(name: "clear-\($0).txt", contents: "original-\($0)")
        }
        await controller.acceptRegularFiles(sources)
        #expect(controller.presentation.snapshot.totalCount == 25)

        await controller.clearAll()

        #expect(controller.presentation.snapshot.entries.isEmpty)
        #expect(controller.presentation.snapshot.totalCount == 0)
        #expect(!controller.isOccupied)
        #expect(!controller.isClearing)
        #expect(controller.statusMessage == nil)
        #expect(preferences.last == false)
        for (index, source) in sources.enumerated() {
            #expect(try String(contentsOf: source, encoding: .utf8) == "original-\(index)")
        }
    }

    @MainActor
    @Test
    func promiseDelegateOutlivesVisualDragAndReceiptsStayPerItem() async throws {
        let fixture = try FileShelfFixture()
        try await fixture.host.restore()
        let first = try fixture.file(name: "primo.txt", contents: "primo")
        let second = try fixture.file(name: "secondo.txt", contents: "secondo")
        let ids = try await fixture.host.addOriginals([first, second])
        let prepared = try await fixture.host.prepareItems(ids: ids)
        let providers = prepared.map { item in
            FileShelfPromiseProvider.make(file: item) { file, destination in
                try await fixture.host.copy(file, to: destination)
            }
        }
        let retainedDelegate = WeakObjectReference(providers[0].delegate as AnyObject?)
        #expect(retainedDelegate.value != nil)

        let collision = fixture.output.appendingPathComponent("primo.txt")
        try Data("esiste".utf8).write(to: collision)
        let firstError = await write(providers[0], to: collision)
        #expect(firstError != nil)

        await Task.yield() // The promise remains valid after the visual drag session has ended.
        let destination = fixture.output.appendingPathComponent("secondo.txt")
        let secondError = await write(providers[1], to: destination)
        #expect(secondError == nil)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "secondo")
        #expect(try await fixture.host.snapshot().entries.map(\.id) == [ids[0]])

        providers[0].userInfo = nil
        #expect(retainedDelegate.value == nil)
    }

    @MainActor
    @Test
    func dragViewHitTestingUsesSuperviewCoordinates() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        let view = FileShelfDragView(
            content: AnyView(Color.clear.frame(width: 80, height: 40)),
            files: [],
            accessibilityName: "File",
            activate: {},
            copy: { _, _ in }
        )
        view.frame = CGRect(x: 90, y: 70, width: 80, height: 40)
        parent.addSubview(view)

        #expect(view.hitTest(CGPoint(x: 100, y: 80)) === view)
        #expect(view.hitTest(CGPoint(x: 20, y: 20)) == nil)
    }

    @Test
    func deckScrollExpansionAcceptsEitherTrackpadAxisAfterIntentThreshold() {
        #expect(!FileShelfDragView.shouldExpand(for: CGSize(width: 2, height: 2)))
        #expect(FileShelfDragView.shouldExpand(for: CGSize(width: 4, height: 0)))
        #expect(FileShelfDragView.shouldExpand(for: CGSize(width: 0, height: -4)))
    }

    private func write(_ provider: NSFilePromiseProvider, to url: URL) async -> (any Error)? {
        await withCheckedContinuation { continuation in
            provider.delegate?.filePromiseProvider(
                provider,
                writePromiseTo: url,
                completionHandler: { continuation.resume(returning: $0) }
            )
        }
    }
}

private final class WeakObjectReference {
    weak var value: AnyObject?

    init(_ value: AnyObject?) { self.value = value }
}

private struct FileShelfFixture {
    let root : URL
    let shelf: URL
    let input: URL
    let output: URL
    let host : FileWorkspaceHost

    init() throws {
        root  = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        shelf = root.appendingPathComponent("shelf")
        input = root.appendingPathComponent("input")
        output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shelf.path)
        host = try FileWorkspaceHost(directory: shelf, governor: ResourceGovernor())
    }

    func file(name: String, contents: String) throws -> URL {
        let url = input.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
