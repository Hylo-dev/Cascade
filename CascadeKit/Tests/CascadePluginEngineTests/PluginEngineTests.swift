//
//  PluginEngineTests.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginEngineTests {

    @Test
    func aPluginsFirstPublicationReachesTheSink() async throws {
        let face   = try PluginEngineFixtures.text("12:00")
        let output = try PluginEngineFixtures.output("time", .widget, face)
        let sink   = RecordingSink()
        let engine = PluginEngine(
            executor: InProcessExecutor(providers: ["ClockPlugin": ScriptedProvider { _ in output }]),
            sources : [:],
            sink    : sink
        )

        engine.register(try PluginEngineFixtures.clock(), grants: [])

        #expect(try await eventually { sink.changes.count == 1 })
        #expect(sink.changes.first?.content?.document == face)
    }

    @Test
    func sourceEventsReachThePluginThatDeclaredThem() async throws {
        let source = FakeSource()
        let log    = EventLog()
        let engine = PluginEngine(
            executor  : InProcessExecutor(providers: [
                "MusicPlugin": ScriptedProvider { event in
                    log.append(event)
                    return try PluginOutput()
                },
            ]),
            sources   : ["media.nowPlaying": source],
            components: ["media.scrubber"],
            sink      : RecordingSink()
        )
        engine.register(try PluginEngineFixtures.music(), grants: ["automation.music"])
        #expect(try await eventually { source.isRunning })

        let song = try PluginEngineFixtures.nowPlaying("Song")
        source.emit(song)

        #expect(try await eventually { log.events.contains(.source(song)) })
    }

    @Test
    func aHungPluginIsDisabledAndItsSourceStops() async throws {
        let gate   = DispatchSemaphore(value: 0)
        let source = FakeSource()
        let engine = PluginEngine(
            executor  : InProcessExecutor(providers: [
                "MusicPlugin": ScriptedProvider { _ in
                    _ = gate.wait(timeout: .now() + 5)
                    return try PluginOutput()
                },
            ]),
            sources   : ["media.nowPlaying": source],
            components: ["media.scrubber"],
            sink      : RecordingSink()
        )

        engine.register(try PluginEngineFixtures.music(), grants: ["automation.music"])

        #expect(try await eventually { engine.state(of: PluginEngineFixtures.musicID) == .disabledAfterHang })
        #expect(!source.isRunning)
        gate.signal()
    }
}
