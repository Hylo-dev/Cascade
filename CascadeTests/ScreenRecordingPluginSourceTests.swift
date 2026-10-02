//
//  ScreenRecordingPluginSourceTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing
@testable import Cascade

@MainActor
struct ScreenRecordingPluginSourceTests {

    @Test
    func theSourceReplaysNativeStateAndReleasesTheCaptureOwner() async throws {
        let source = ScreenRecordingPluginSource()
        #expect(!source.isAvailable)
        let state  = PluginScreenRecordingState(session: UUID(), startedAt: .now)
        source.update(state)
        let channel = AsyncStream<PluginSourceEvent>.makeStream()
        source.start { channel.continuation.yield($0) }
        var events = channel.stream.makeAsyncIterator()
        let baseline = await events.next()
        let decoded = try #require(baseline.flatMap(PluginScreenRecordingState.init))
        #expect(source.isAvailable)
        #expect(decoded.session == state.session)
        #expect(decoded.isStopping == false)
        let receivedStart = try #require(decoded.startedAt)
        let nativeStart = try #require(state.startedAt)
        #expect(abs(receivedStart.timeIntervalSince(nativeStart)) < 0.000_001)

        source.update(PluginScreenRecordingState())
        let idle = await events.next()
        #expect(idle.flatMap(PluginScreenRecordingState.init)?.session == nil)

        await withCheckedContinuation { continuation in
            source.onReleased = { continuation.resume() }
            source.stop()
        }
        #expect(!source.isAvailable)
        channel.continuation.finish()
    }
}
