//
//  AudioPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Testing

@testable import CascadePlugins

@Suite
struct AudioPluginTests {

    private let context = PluginContext(plugin: AudioPlugin.id)

    @Test
    func refreshPublishesTheBarAndTheMixer() throws {
        let output = try AudioPlugin().handle(.refresh, context: context)

        #expect(output.publications.map(\.surface) == [.widget, .detail])
        #expect(output.publications.allSatisfy { $0.feature == AudioPlugin.feature })
        #expect(output.publications.first?.document?.componentReferences == [try PluginComponentReference(id: "audio.volumeBar", version: 1)])
        #expect(output.publications.last?.document?.componentReferences == [try PluginComponentReference(id: "audio.mixer", version: 1)])
    }

    @Test
    func otherEventsPublishNothing() throws {
        let plugin = AudioPlugin()

        #expect(try plugin.handle(.wake, context: context).publications.isEmpty)
    }
}
