//
//  CaffeinateControllerTests.swift
//  Cascade
//

import CascadeContracts
import CascadePlugins
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

    @Test
    func wideAndIconFacesFitTheirGridTilesWithoutOverflow() throws {
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let output = try CaffeinatePlugin().handle(
            .source(PluginCaffeinateState().event()),
            context: PluginContext(plugin: owner)
        )
        let document = try #require(output.publications.first?.document)
        let key = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)
        var publisher = PluginPublicationStore()
        let store = PluginNodeStore(key: key, submit: { _ in })
        let change = publisher.apply(document, staleAfter: nil, for: key, at: .now)
        store.apply(try #require(change))

        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == owner })
        let host = SurfaceFixture()
        let router = PluginSurfaceRouter(host: host, manifests: [manifest], submit: { _ in }, visibility: { _, _ in })
        router.apply([try #require(change)], rejected: [])
        let widget = try #require(host.widget)
        #expect(widget.size == GridSpan(columns: 4, rows: 2))
        #expect(widget.sizes.allSatisfy { $0.columns <= 4 && $0.rows <= 2 })

        // Resolve the routed spans, not the manifest's units: its columns are doubled.
        for span in widget.sizes {
            let layout = NotchLayoutResolver().resolve(
                interior: CGRect(x: 0, y: 0, width: 400, height: 112),
                notchWidth: 0,
                topBandHeight: 32,
                placements: [widget.id: WidgetPlacement(position: GridPosition(column: 0, row: 1), span: span)]
            )
            let frame = try #require(layout.frames[widget.id])
            let width = frame.width
            let height = frame.height
            let name = span.rows == 2 ? "wide" : "icon"
            let renderer = ImageRenderer(content: PluginDocumentView(store: store).environment(\.colorScheme, .dark))
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            renderer.scale = 2
            let image = try #require(renderer.nsImage)
            #expect(image.size.width <= width)
            #expect(image.size.height <= height)
            let representation = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try #require(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/cascade-caffeinate-\(name)-preview.png"))
        }

        let glyphID = PluginNodeID(rawValue: "#full.cup:symbol")
        let glyph = try #require(store.model(glyphID))
        for state in [PluginCaffeinateState(isBusy: true), PluginCaffeinateState(isActive: true)] {
            let update = try CaffeinatePlugin().handle(.source(state.event()), context: PluginContext(plugin: owner))
            let face = try #require(update.publications.first?.document)
            let change = publisher.apply(face, staleAfter: nil, for: key, at: .now)
            store.apply(try #require(change))
            #expect(store.model(glyphID) === glyph)
        }
    }

    @MainActor
    private final class SurfaceFixture: PluginSurfaceHosting {

        var widget: (any NotchWidget)?

        func register(_ widget: any NotchWidget) { self.widget = widget }
        func unregisterWidget(id: WidgetIdentifier) { widget = nil }
        func present(_ activity: any NotchLiveActivity) {}
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
        func request(_ prefix: String, kind: String = "button", value: PluginValue? = nil) -> PluginActionRequest {
            PluginActionRequest(key: key, node: PluginNodeID(rawValue: "#" + prefix + "." + source.state.token.uuidString + ":" + kind), revision: 1, value: value)
        }

        controller.handleAction(request("duration.15"))
        try #require(controller.minutes == 15)
        #expect(!source.state.isActive)
        _ = try #require(await events.next())
        controller.toggle()
        _ = try #require(await events.next())
        let active = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        let until = try #require(active.until)
        let nativeUntil = try #require((await session.snapshot()).until)
        let stale = request("display", kind: "toggle", value: .bool(false))
        controller.handleAction(stale)
        _ = try #require(await events.next())
        let updated = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        #expect(updated.isActive && !updated.keepDisplayAwake)
        #expect(updated.until == until)
        #expect((await session.snapshot()).until == nativeUntil)
        #expect(backend.storage.withLock { $0.owned.count } == 1)
        controller.handleAction(stale)
        #expect(source.state.token == updated.token)
        controller.handleAction(request("duration.30"))
        _ = try #require(await events.next())
        let extended = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        #expect(try #require(extended.until).timeIntervalSince(until) > 850)
        #expect(controller.minutes == 30)
        controller.handleAction(request("credits"))
        _ = try #require(await events.next())
        #expect(source.state.showsCredits)
        controller.handleAction(request("stop"))
        _ = try #require(await events.next())
        _ = try #require(await events.next())
        #expect(!source.state.isActive)
        #expect(backend.storage.withLock { $0.owned.isEmpty })
        await controller.shutdown()
        channel.continuation.finish()
    }

    @Test(arguments: [false, true])
    func anOldAcceptedControlCannotToggleAReplacementSession(compact: Bool) async throws {
        let source = CaffeinatePluginSource()
        let backend = CaffeinateBackendFixture()
        let session = CaffeinateSession(backend: backend)
        let controller = CaffeinateController(source: source, session: session)
        let channel = AsyncStream<PluginSourceEvent>.makeStream()
        source.start { channel.continuation.yield($0) }
        var events = channel.stream.makeAsyncIterator()
        let baseline = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let key = PluginPublicationKey(plugin: owner, feature: "awake", surface: .widget)
        let prefix = compact ? "#toggle.compact." : "#toggle."
        let stale = PluginActionRequest(key: key, node: PluginNodeID(rawValue: prefix + baseline.token.uuidString + ":button"), revision: 1)

        controller.handleAction(stale)
        _ = await events.next() // Busy replaces the native token before acquisition.
        let active = try #require(await events.next().flatMap(PluginCaffeinateState.init))
        #expect(active.isActive)
        controller.handleAction(stale)
        #expect(source.state.token == active.token)
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
