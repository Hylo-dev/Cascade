//
//  FirstPartyPluginsTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct FirstPartyPluginsTests {

    /// everyBundledManifestValidates decodes each bundled JSON with the validation the loader
    /// uses, so a broken manifest fails here instead of being left out at run time.
    @Test
    func everyBundledManifestValidates() throws {
        let files = try #require(Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil))

        for file in files {
            _ = try PluginManifest.decode(Data(contentsOf: file))
        }
        #expect(FirstPartyPlugins.manifests().count == files.count)
    }

    @Test
    func everyManifestHasAProvider() {
        let manifests = FirstPartyPlugins.manifests()

        #expect(manifests.map(\.id.rawValue) == ["com.cascade.clock", "com.cascade.power", "com.cascade.volume"])
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
    func theClockFaceIsTheKernelDrawnDateAboveTheTime() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first)
        let face     = try ClockPlugin.face()
        let time     = try #require(face.root.children.last)

        #expect(face.root.children.map(\.kind) == [.today, .clock])
        #expect(time.modifiers.contains(.contentTransition(.numericText(countsDown: false))))
        #expect(manifest.features.first?.surfaces.widget?.sizes == [try PluginWidgetSize(columns: 2, rows: 2)])
        #expect(face.componentReferences.isEmpty)
    }
}
