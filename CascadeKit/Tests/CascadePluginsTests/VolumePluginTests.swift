//
//  VolumePluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Testing

@testable import CascadePlugins

@Suite
struct VolumePluginTests {

    private let context = PluginContext(plugin: VolumePlugin.id)

    private func volume(
        _ percentage : Int?,
        muted        : Bool = false,
        announcement : UInt64
    ) throws -> PluginEvent {
        .source(try PluginVolumeState(percentage: percentage, isMuted: muted, announcement: announcement).event())
    }

    private func publications(
        _ plugin: VolumePlugin,
        _ event : PluginEvent
    ) throws -> [PluginPublication] {
        try plugin.handle(event, context: context).publications
    }

    @Test
    func theFirstStateIsASilentBaseline() throws {
        let plugin = VolumePlugin()

        #expect(try publications(plugin, volume(40, announcement: 7)).isEmpty)
    }

    @Test
    func everyAnnouncementShowsTheNoticeAgain() throws {
        let plugin = VolumePlugin()
        _ = try publications(plugin, volume(nil, announcement: 0))

        let first  = try #require(try publications(plugin, volume(65, announcement: 1)).first)
        let second = try #require(try publications(plugin, volume(65, announcement: 2)).first?.notice)
        let notice = try #require(first.notice)

        #expect(first.surface == .notice)
        #expect(notice.delivery == .show)
        #expect(notice.duration == 1.8)
        #expect(notice.compactWidth == 116)
        #expect(notice.border == nil)
        #expect(second.delivery == .show)
        #expect(first.document?.componentReferences == [try PluginComponentReference(id: "volume.level", version: 1)])
    }

    @Test
    func aLevelThatWasNotAnnouncedShowsNothing() throws {
        let plugin = VolumePlugin()
        _ = try publications(plugin, volume(nil, announcement: 0))
        _ = try publications(plugin, volume(65, announcement: 1))

        #expect(try publications(plugin, volume(65, muted: true, announcement: 1)).isEmpty)
    }

    @Test
    func aNewSessionsBaselineResetsTheCounter() throws {
        let plugin = VolumePlugin()
        _ = try publications(plugin, volume(nil, announcement: 0))
        _ = try publications(plugin, volume(65, announcement: 1))

        #expect(try publications(plugin, volume(nil, announcement: 0)).isEmpty)
        #expect(try publications(plugin, volume(30, announcement: 1)).count == 1)
    }

    @Test
    func aMutedOutputSaysSo() throws {
        let plugin = VolumePlugin()
        _ = try publications(plugin, volume(nil, announcement: 0))

        let notice = try #require(try publications(plugin, volume(0, muted: true, announcement: 1)).first?.notice)

        #expect(notice.accessibilityLabel == "Audio muted")
    }

    @Test
    func aPreviewShowsASampleWithoutMovingTheBaseline() throws {
        let plugin  = VolumePlugin()
        let preview = try PluginActionEvent(feature: VolumePlugin.feature, action: VolumePlugin.preview)

        #expect(try publications(plugin, .action(preview)).first?.notice?.accessibilityLabel == "Volume, 65 percent")
        #expect(try publications(plugin, volume(40, announcement: 3)).isEmpty)
    }

    @Test
    func theManifestDeclaresWhatTheNoticeUses() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == VolumePlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "VolumePlugin")
        #expect(feature.id == VolumePlugin.feature)
        #expect(feature.surfaces.declares(.notice))
        #expect(feature.sources == [PluginVolumeState.source])
        #expect(feature.components == [try PluginComponentReference(id: "volume.level", version: 1)])
        #expect(feature.actions == [VolumePlugin.preview])
    }
}
