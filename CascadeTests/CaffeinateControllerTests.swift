//
//  CaffeinateControllerTests.swift
//  Cascade
//

import CascadeContracts
@testable import CascadePlugins
import CascadePluginSDK
import Foundation
import SwiftUI
import Synchronization
import Testing
@testable import Cascade
@testable import CascadeKit
@testable import CascadePluginEngine

@MainActor
struct CaffeinateControllerTests {

    /// The widget's tiles and options page in the default notch: 400 points of interior width,
    /// and the expanded height less Back's header band and the bottom inset.
    private static let interior     = CGRect(x: 0, y: 0, width: 400, height: 124)
    private static let optionsFrame = CGSize(width: 400, height: 86)

    /// ViewThatFits picks the first face whose ideal width fits the tile. Each face is measured
    /// on its own, the way ViewThatFits measures it, against the tile it must be chosen for, so a
    /// face that never fits, and leaves the widget showing only its cup, fails here.
    @Test
    func eachFaceFitsTheTileItIsChosenFor() throws {
        let document = try publish(PluginCaffeinateState())
        let faces    = document.root.children
        #expect(document.root.kind == .viewThatFits(axes: .horizontal))
        #expect(faces.count == 2)

        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == Self.owner })
        let host     = SurfaceFixture()
        let router   = PluginSurfaceRouter(host: host, manifests: [manifest], submit: { _ in }, visibility: { _, _ in })
        var store    = PluginPublicationStore()
        let change   = store.apply(document, staleAfter: nil, for: Self.key, at: .now)
        router.apply([try #require(change)], rejected: [])
        let widget = try #require(host.widget)
        #expect(widget.sizes == [GridSpan(columns: 4, rows: 1), GridSpan(columns: 2, rows: 1)])

        let large = try tile(widget.sizes[0], of: widget.id)
        let small = try tile(widget.sizes[1], of: widget.id)
        let largeFace = idealSize(of: try PluginDocument(root: faces[0]))
        let smallFace = idealSize(of: try PluginDocument(root: faces[1]))

        #expect(largeFace.width <= large.width, "The large face is wider than its 2x1 tile")
        #expect(largeFace.height <= large.height, "The large face is taller than its 2x1 tile")
        #expect(largeFace.width > small.width, "The 1x1 tile would show the large face")
        #expect(smallFace.width <= small.width)
        #expect(smallFace.height <= small.height)

        try snapshot(PluginDocumentView(store: try nodeStore(document)), size: large.size, name: "large")
        try snapshot(PluginDocumentView(store: try nodeStore(document)), size: small.size, name: "small")
    }

    /// The options page has the expanded footprint below Back, about 400 by 86 points; it must
    /// fit without scrolling in every state.
    @Test
    func theOptionsPageFitsTheExpandedNotchInEveryState() throws {
        let states = [
            ("off", PluginCaffeinateState(minutes: 60)),
            ("timed", PluginCaffeinateState(isActive: true, keepDisplayAwake: false, until: .now.addingTimeInterval(2_700), minutes: 60)),
            ("indefinite", PluginCaffeinateState(isActive: true)),
            ("failed", PluginCaffeinateState(error: "The power assertion could not be created.")),
        ]
        for (name, state) in states {
            let document = try publish(state)
            let options  = try #require(document.optionsRoot)
            let page     = PluginDocumentView(store: try nodeStore(document), showsOptions: true)
            let size     = idealSize(of: try PluginDocument(root: options), width: Self.optionsFrame.width)

            #expect(size.height <= Self.optionsFrame.height, "The \(name) options page needs \(size.height) points")
            try snapshot(page, size: Self.optionsFrame, name: "options-\(name)")
        }
    }

    /// A publication must update the cup in place, so its symbol transition plays.
    @Test
    func theCupKeepsItsIdentityAcrossSessionChanges() throws {
        var publisher = PluginPublicationStore()
        let store     = PluginNodeStore(key: Self.key, submit: { _ in })
        let first     = publisher.apply(try publish(PluginCaffeinateState()), staleAfter: nil, for: Self.key, at: .now)
        store.apply(try #require(first))
        let glyphID = PluginNodeID(rawValue: "#power.large.cup:symbol")
        let glyph   = try #require(store.model(glyphID))

        for state in [PluginCaffeinateState(isBusy: true), PluginCaffeinateState(isActive: true)] {
            let change = publisher.apply(try publish(state), staleAfter: nil, for: Self.key, at: .now)
            store.apply(try #require(change))
            #expect(store.model(glyphID) === glyph)
        }
    }

    private static let owner = PluginID(rawValue: "com.cascade.caffeinate")!
    private static let key   = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)

    private func publish(_ state: PluginCaffeinateState) throws -> PluginDocument {
        let output = try CaffeinatePlugin().handle(.source(state.event()), context: PluginContext(plugin: Self.owner))
        return try #require(output.publications.first?.document)
    }

    private func nodeStore(_ document: PluginDocument) throws -> PluginNodeStore {
        var publisher = PluginPublicationStore()
        let store     = PluginNodeStore(key: Self.key, submit: { _ in })
        let change    = publisher.apply(document, staleAfter: nil, for: Self.key, at: .now)
        store.apply(try #require(change))
        return store
    }

    /// idealSize is the size a document asks for when nothing constrains it, or only its width.
    private func idealSize(
        of document: PluginDocument,
        width      : CGFloat? = nil
    ) -> CGSize {
        // An unspecified proposal is the one ViewThatFits measures a face with: a flexible frame
        // then reports its content's ideal size instead of whatever it is offered.
        let store    = (try? nodeStore(document)) ?? PluginNodeStore(key: Self.key, submit: { _ in })
        let renderer = ImageRenderer(content: PluginDocumentView(store: store).environment(\.colorScheme, .dark))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale        = 1
        return renderer.nsImage?.size ?? CGSize(width: CGFloat.infinity, height: .infinity)
    }

    private func tile(
        _ span: GridSpan,
        of id : WidgetIdentifier
    ) throws -> CGRect {
        let layout = NotchLayoutResolver().resolve(
            interior     : Self.interior,
            notchWidth   : 0,
            topBandHeight: 32,
            placements   : [id: WidgetPlacement(position: GridPosition(column: 0, row: 1), span: span)]
        )
        return try #require(layout.frames[id])
    }

    /// snapshot writes the view at `size` on the notch's black, for visual review.
    private func snapshot(
        _ view: some View,
        size  : CGSize,
        name  : String
    ) throws {
        let renderer = ImageRenderer(content: view
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image          = try #require(renderer.nsImage)
        let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let png            = try #require(representation.representation(using: .png, properties: [:]))
        try png.write(to: URL(filePath: "/tmp/cascade-caffeinate-\(name).png"))
    }

    @MainActor
    private final class SurfaceFixture: PluginSurfaceHosting {

        var widget: (any NotchWidget)?

        func register(_ widget: any NotchWidget) { self.widget = widget }
        func unregisterWidget(id: WidgetIdentifier) { widget = nil }
        func showNotice(_ notice: any NotchTransientNotice) {}
        func updateNotice(_ notice: any NotchTransientNotice) {}
        func dismissActivity(id: String) {}
    }

    @Test
    func noSessionCanStartWithoutItsPluginLease() async {
        let source = CaffeinatePluginSource()
        let backend = CaffeinateBackendFixture()
        let session = CaffeinateSession(backend: backend)
        let controller = CaffeinateController(source: source, session: session)
        controller.toggle()
        #expect(!(await session.snapshot()).hasResources)
        #expect(!controller.needsShutdown)
    }

    @Test
    func optionsChangePreferencesAndActiveResourcesThroughFreshControls() async throws {
        let source = CaffeinatePluginSource()
        let backend = CaffeinateBackendFixture()
        let session = CaffeinateSession(backend: backend)
        let suite = "cascade.caffeinate.options." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = CaffeinateController(source: source, session: session, preferences: preferences)
        let channel = AsyncStream<PluginSourceEvent>.makeStream()
        source.start { channel.continuation.yield($0) }
        defer { channel.continuation.finish() }
        let timeout = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            channel.continuation.finish()
        }
        defer { timeout.cancel() }
        var events = channel.stream.makeAsyncIterator()
        _ = try #require(await events.next())
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let key = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)
        func request(_ node: String, value: PluginValue? = nil) -> PluginActionRequest {
            PluginActionRequest(key: key, node: PluginNodeID(rawValue: node), revision: 1, value: value)
        }

        controller.handleAction(request("#duration.15:button"))
        try #require(controller.minutes == 15)
        #expect(!source.state.isActive)
        _ = try #require(await events.next())
        controller.toggle()
        _ = try #require(await events.next())
        let active = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        let until = try #require(active.until)
        let nativeUntil = try #require((await session.snapshot()).until)
        let repeated = request("#display:toggle", value: .bool(false))
        controller.handleAction(repeated)
        _ = try #require(await events.next())
        let updated = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        #expect(updated.isActive && !updated.keepDisplayAwake)
        #expect(updated.until == until)
        #expect((await session.snapshot()).until == nativeUntil)
        #expect(backend.storage.withLock { $0.owned.count } == 1)
        controller.handleAction(repeated)
        // A repeated request changes nothing. The state is compared as the plugin receives it,
        // after the event's seconds, which drop the date's sub-millisecond part.
        #expect(PluginCaffeinateState(try source.state.event()) == updated)
        controller.handleAction(request("#duration.30:button"))
        _ = try #require(await events.next())
        let extended = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        #expect(try #require(extended.until).timeIntervalSince(until) > 850)
        #expect(controller.minutes == 30)
        controller.handleAction(request("#power.options:toggle", value: .bool(false)))
        _ = try #require(await events.next())
        _ = try #require(await events.next())
        #expect(!source.state.isActive)
        #expect(backend.storage.withLock { $0.owned.isEmpty })
        await controller.shutdown()
        channel.continuation.finish()
    }

    @Test(arguments: [false, true])
    func aRepeatedStartRequestCannotStopTheSessionItStarted(compact: Bool) async throws {
        let source = CaffeinatePluginSource()
        let backend = CaffeinateBackendFixture()
        let session = CaffeinateSession(backend: backend)
        let controller = CaffeinateController(source: source, session: session)
        let channel = AsyncStream<PluginSourceEvent>.makeStream()
        source.start { channel.continuation.yield($0) }
        var events = channel.stream.makeAsyncIterator()
        _ = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let key = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)
        let node  = compact ? "#power.small:toggle" : "#power.large:toggle"
        let start = PluginActionRequest(key: key, node: PluginNodeID(rawValue: node), revision: 1, value: .bool(true))

        controller.handleAction(start)
        _ = await events.next() // Busy, before acquisition.
        let active = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        #expect(active.isActive)
        controller.handleAction(start)
        #expect(PluginCaffeinateState(try source.state.event()) == active)
        #expect(source.state.isActive)
        await controller.shutdown()
        #expect(!(await session.snapshot()).hasResources)
        channel.continuation.finish()
    }

    @Test
    func disablingThePluginDuringAcquisitionReleasesTheLateAssertion() async throws {
        let source = CaffeinatePluginSource()
        let backend = CaffeinateBackendFixture(holdsAcquisition: true)
        let session = CaffeinateSession(backend: backend)
        let controller = CaffeinateController(source: source, session: session)
        let channel = AsyncStream<PluginSourceEvent>.makeStream()
        source.start { channel.continuation.yield($0) }
        var events = channel.stream.makeAsyncIterator()
        _ = await events.next()
        controller.toggle()
        var acquired = backend.requested.makeAsyncIterator()
        _ = await acquired.next()

        let release = source.onReleased
        await withCheckedContinuation { continuation in
            source.onReleased = {
                release()
                continuation.resume()
            }
            source.stop()
        }
        backend.gate.signal()
        await controller.shutdown()
        #expect(!source.isAvailable)
        #expect(!source.state.isActive)
        #expect(!(await session.snapshot()).hasResources)
        #expect(backend.storage.withLock { $0.owned.isEmpty })
        channel.continuation.finish()
    }
}

/// CaffeinateBackendFixture gates only the blocking system boundary, off the UI thread.
/// A five-second timeout prevents a failing test from hanging the test runner indefinitely.
nonisolated private final class CaffeinateBackendFixture: CaffeinateAssertionManaging, Sendable {

    struct Storage: Sendable {
        var next: UInt32 = 1
        var owned: Set<UInt32> = []
    }

    let storage = Mutex(Storage())
    let gate = DispatchSemaphore(value: 0)
    let requested: AsyncStream<Void>
    private let requests: AsyncStream<Void>.Continuation
    private let holdsAcquisition: Bool

    init(holdsAcquisition: Bool = false) {
        let channel = AsyncStream<Void>.makeStream()
        requested = channel.stream
        requests = channel.continuation
        self.holdsAcquisition = holdsAcquisition
    }

    func acquire(keepDisplayAwake: Bool, until: Date?) throws -> UInt32 {
        if holdsAcquisition && !keepDisplayAwake {
            requests.yield(())
            guard gate.wait(timeout: .now() + 5) == .success else {
                throw CaffeinateFailure.native(-1)
            }
        }
        return storage.withLock { state in
            let identifier = state.next
            state.next += 1
            state.owned.insert(identifier)
            return identifier
        }
    }

    func release(_ identifier: UInt32) {
        storage.withLock { state in _ = state.owned.remove(identifier) }
    }
}
