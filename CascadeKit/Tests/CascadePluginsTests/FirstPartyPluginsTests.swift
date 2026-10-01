//
//  FirstPartyPluginsTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Testing

@testable import CascadePlugins

@Suite
struct FirstPartyPluginsTests {

    @Test
    func everyManifestValidatesAndHasAProvider() {
        let manifests = FirstPartyPlugins.manifests()

        #expect(manifests.map(\.id.rawValue) == ["com.cascade.clock"])
        #expect(manifests.allSatisfy { FirstPartyPlugins.providers[$0.execution.entryPoint] != nil })
    }

    @Test
    func theClockAnswersEveryEventWithTheSameFaceAndNoWake() throws {
        let clock   = ClockPlugin()
        let context = PluginContext(plugin: PluginID(rawValue: "com.cascade.clock")!)
        let face    = try ClockPlugin.face()
        let events: [PluginEvent] = [.refresh, .wake]

        for event in events {
            let output = try clock.handle(event, context: context)

            #expect(output.publications == [try PluginPublication(feature: "time", surface: .widget, document: face)])
            #expect(output.wake == nil)
        }
    }

    @Test
    func theClockFaceIsTheKernelDrawnTime() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first)
        let face     = try ClockPlugin.face()

        #expect(face.root.kind == .clock)
        #expect(manifest.features.first?.surfaces.declares(.widget) == true)
        #expect(face.componentReferences.isEmpty)
    }
}
