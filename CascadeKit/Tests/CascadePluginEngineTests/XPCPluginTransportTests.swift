//
//  XPCPluginTransportTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginHost
import CascadePluginSDK
import Dispatch
import Foundation
import Testing

@testable import CascadePluginEngine

/// XPCPluginTransportTests run both ends of the real XPC code inside the test process, through
/// an anonymous listener. The handshake then names this process, which the incarnation refuses
/// to signal, so a slow dispatch that trips the watchdog cannot kill the test runner; killing a
/// real PluginHost belongs to the integration check of the next plan.
@Suite(.timeLimit(.minutes(1)))
struct XPCPluginTransportTests {

    /// Host is an anonymous listener serving the given plugins, kept alive by the test.
    private final class Host {

        let listener: NSXPCListener
        let delegate: PluginHostListener

        init(
            _ providers: [String: any PluginProvider],
            sources    : [String: any PluginCatalogSource] = [:]
        ) {
            delegate = PluginHostListener(
                service    : PluginHostService(runner: PluginRunner(providers: providers), sources: PluginSourceRuntime(sources: sources)),
                requirement: nil
            )
            listener = NSXPCListener.anonymous()
            listener.delegate = delegate
            listener.resume()
        }

        var transport: XPCPluginTransport {
            XPCPluginTransport(endpoint: listener.endpoint)
        }
    }

    private let clock = PluginEngineFixtures.clockID

    @Test
    func theHandshakeNamesThisProcess() async {
        let host = Host([:])
        let link = host.transport.connect(onLoss: {}, onSourceEvent: { _ in })
        defer { link.invalidate() }

        let incarnation = await withCheckedContinuation { continuation in
            link.hello { continuation.resume(returning: $0) }
        }

        #expect(incarnation?.pid == getpid())
    }

    @Test
    func anEventRoundTripsThroughTheHost() async throws {
        let output = try PluginEngineFixtures.output("time", .widget, PluginEngineFixtures.text("12:00"))
        let host   = Host(["ClockPlugin": ScriptedProvider { _ in output }])
        let link   = host.transport.connect(onLoss: {}, onSourceEvent: { _ in })
        defer { link.invalidate() }

        link.start(clock, entryPoint: "ClockPlugin")
        let result = await withCheckedContinuation { continuation in
            link.handle(.refresh, for: clock) { continuation.resume(returning: $0) }
        }

        #expect(result?.output == output)
    }

    @Test
    func aThrowingPluginAnswersWithAFailure() async {
        let host = Host(["ClockPlugin": ScriptedProvider { _ in throw CancellationError() }])
        let link = host.transport.connect(onLoss: {}, onSourceEvent: { _ in })
        defer { link.invalidate() }

        link.start(clock, entryPoint: "ClockPlugin")
        let result = await withCheckedContinuation { continuation in
            link.handle(.refresh, for: clock) { continuation.resume(returning: $0) }
        }

        #expect(result?.outcome == .failed)
    }

    @Test
    func aBrokenConnectionAnswersNothingAndReportsTheLoss() async throws {
        let gate   = DispatchSemaphore(value: 0)
        let losses = Recorder<Bool>()
        let host   = Host([
            "ClockPlugin": ScriptedProvider { _ in
                _ = gate.wait(timeout: .now() + 5)
                return try PluginOutput()
            },
        ])
        let link = host.transport.connect(onLoss: { losses.record(true) }, onSourceEvent: { _ in })
        link.start(clock, entryPoint: "ClockPlugin")

        async let result = withCheckedContinuation { continuation in
            link.handle(.refresh, for: clock) { continuation.resume(returning: $0) }
        }
        try await Task.sleep(for: .milliseconds(50))
        link.invalidate()

        #expect(await result == nil)
        #expect(try await eventually { !losses.values.isEmpty })
        gate.signal()
    }

    @Test
    func theEngineRunsAPluginThroughTheXPCHost() async throws {
        let face   = try PluginEngineFixtures.text("12:00")
        let output = try PluginEngineFixtures.output("time", .widget, face)
        let host   = Host(["ClockPlugin": ScriptedProvider { _ in output }])
        let sink   = RecordingSink()
        let engine = PluginEngine(
            executor: SharedHostExecutor(transport: host.transport),
            sources : [:],
            sink    : sink
        )

        engine.register(try PluginEngineFixtures.clock(), grants: [])

        #expect(try await eventually { sink.changes.count == 1 })
        #expect(sink.changes.first?.content?.document == face)
    }

    @Test
    func aHostSourceSendsItsStatesToTheKernel() async throws {
        let charging = try PluginEngineFixtures.power(charging: true)
        let source   = FakeCatalogSource(charging)
        let host     = Host([:], sources: ["power": source])
        let received = Recorder<PluginSourceEvent>()
        let link     = host.transport.connect(onLoss: {}, onSourceEvent: { received.record($0) })
        defer { link.invalidate() }

        link.startSource("power")

        #expect(try await eventually { received.values == [charging] })

        link.stopSource("power")

        #expect(try await eventually { source.stops == 1 })
    }

    @Test
    func aMalformedOrOversizedStateIsDropped() throws {
        let received = Recorder<PluginSourceEvent>()
        let client   = PluginHostClient { received.record($0) }

        client.sourceChanged(event: Data(#"{"source":"teleport"}"#.utf8))
        client.sourceChanged(event: Data(repeating: 0x20, count: PluginHostClient.maximumEventBytes + 1))
        client.sourceChanged(event: try JSONEncoder().encode(PluginEngineFixtures.power(charging: true)))

        #expect(received.values == [try PluginEngineFixtures.power(charging: true)])
    }

    @Test
    func aClosedConnectionStopsItsSources() async throws {
        let source = FakeCatalogSource(try PluginEngineFixtures.power(charging: true))
        let host   = Host([:], sources: ["power": source])
        let link   = host.transport.connect(onLoss: {}, onSourceEvent: { _ in })
        link.startSource("power")
        _ = try await eventually { source.starts == 1 }

        link.invalidate()

        #expect(try await eventually { source.stops == 1 })
    }
}
