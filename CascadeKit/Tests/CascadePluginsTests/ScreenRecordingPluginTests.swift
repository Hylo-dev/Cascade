//
//  ScreenRecordingPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing
@testable import CascadePlugins

struct ScreenRecordingPluginTests {

    @Test
    func aRecordingPublishesAllPresentationsAndASessionBoundStopWithoutWakes() throws {
        let plugin  = ScreenRecordingPlugin()
        let owner   = try #require(PluginID(rawValue: "com.cascade.screen-recording"))
        let session = UUID()
        let start   = Date(timeIntervalSince1970: 1_800_000_000)
        let state   = PluginScreenRecordingState(session: session, startedAt: start)
        let output  = try plugin.handle(.source(state.event()), context: PluginContext(plugin: owner))
        let publication = try #require(output.publications.first)
        let document    = try #require(publication.document)
        let table       = PluginNodeTable(document)

        #expect(publication.surface == .activity)
        #expect(document.root.children.count == 4)
        #expect(output.wake == nil)
        #expect(document.root.children[1].kind == .timer(start: start, end: start.addingTimeInterval(28_800), countsDown: false))
        #expect(document.root.children[1].modifiers.contains(.contentTransition(.numericText(countsDown: false))))
        #expect(table.entries.contains { $0.id.rawValue == "#stop." + session.uuidString + ":button" && $0.kind == .button(action: "recording.stop") })
        #expect(table.entries.contains { $0.kind == .timer(start: start, end: start.addingTimeInterval(28_800), countsDown: false) })
        _ = try PluginOutput(publications: [publication])
    }

    @Test
    func stoppingRetainsTheIndicatorButRemovesItsControlUntilFinalization() throws {
        let plugin  = ScreenRecordingPlugin()
        let owner   = try #require(PluginID(rawValue: "com.cascade.screen-recording"))
        let state   = PluginScreenRecordingState(session: UUID(), startedAt: .now, isStopping: true)
        let output  = try plugin.handle(.source(state.event()), context: PluginContext(plugin: owner))
        let document = try #require(output.publications.first?.document)

        #expect(!PluginNodeTable(document).entries.contains { if case .button = $0.kind { return true }; return false })
        let idle = try plugin.handle(.source(PluginScreenRecordingState().event()), context: PluginContext(plugin: owner))
        #expect(idle.publications.count == 1)
        #expect(idle.publications.first?.document == nil)
    }

    @Test
    func malformedRecordingStateCannotCreateAnActivity() throws {
        let malformed = try PluginSourceEvent(source: "screen.recording", fields: ["session": .string("broken"), "startedAt": .number(0), "isStopping": .bool(false)])

        #expect(PluginScreenRecordingState(malformed) == nil)
        #expect(throws: (any Error).self) { try PluginScreenRecordingState(session: UUID()).event() }
    }
}
