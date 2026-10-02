//
//  SoundPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct SoundPluginTests {

    private let context = PluginContext(plugin: SoundPlugin.id)

    private func volume(
        _ percentage: Int?,
        muted       : Bool = false,
        announcement: UInt64 = 0
    ) throws -> PluginEvent {
        .source(try PluginVolumeState(percentage: percentage, isMuted: muted, announcement: announcement).event())
    }

    private func root(of output: PluginOutput) throws -> PluginNode {
        let publication = try #require(output.publications.first)

        #expect(output.publications.count == 1)
        #expect(output.wake == nil)
        #expect(publication.feature == SoundPlugin.feature)
        #expect(publication.surface == .widget)

        return try #require(publication.document).root
    }

    private func levels(in node: PluginNode) -> [PluginValue?] {
        PluginNodeSearch.kinds(in: node).compactMap { kind in
            if case .component("volume.level", 1, let parameters) = kind { return parameters["level"] }

            return nil
        }
    }

    // MARK: - The plugin

    @Test
    func aLevelShowsItsPercentageAndTheKernelsBarOnEveryFace() throws {
        let root = try root(of: SoundPlugin().handle(try volume(40), context: context))

        #expect(root.kind == .viewThatFits(axes: .horizontal))
        #expect(root.children.count == 2)
        for face in root.children {
            #expect(PluginNodeSearch.texts(in: face) == ["40%"])
            #expect(levels(in: face) == [.number(40)])
            #expect(PluginNodeSearch.kinds(in: face).contains(.symbol(name: "speaker.wave.2.fill")))
        }
        #expect(PluginNodeSearch.accessibilityLabel(of: root) == "Volume, 40 percent")
    }

    /// A muted output draws an empty bar, whatever level it would play at. The 1x1 face has no
    /// room for the word, which would shrink past reading, so its struck speaker says it alone.
    @Test
    func aMutedOutputShowsTheStruckSpeakerAndSaysMuted() throws {
        let root = try root(of: SoundPlugin().handle(try volume(45, muted: true), context: context))

        for face in root.children {
            #expect(PluginNodeSearch.kinds(in: face).contains(.symbol(name: "speaker.slash.fill")))
            #expect(levels(in: face) == [.number(0)])
        }
        #expect(PluginNodeSearch.texts(in: root.children[0]) == ["Muted"])
        #expect(PluginNodeSearch.texts(in: root.children[1]).isEmpty)
        #expect(PluginNodeSearch.accessibilityLabel(of: root) == "Audio muted")
        #expect(try ItalianStrings.value(of: "Muted") == "Silenzioso")
    }

    /// The source's baseline knows no level yet; the widget waits for one rather than draw a
    /// level it does not know.
    @Test
    func anUnknownLevelPublishesNothing() throws {
        let plugin = SoundPlugin()

        let baseline = try plugin.handle(try volume(nil), context: context)
        let refresh  = try plugin.handle(.refresh, context: context)

        #expect(baseline.publications.isEmpty)
        #expect(refresh.publications.isEmpty)
    }

    /// The announcement counter is the volume alerts' business: a state that moves only the
    /// counter changes nothing the widget shows.
    @Test
    func anUnchangedLevelPublishesNothing() throws {
        let plugin = SoundPlugin()

        let first   = try plugin.handle(try volume(40, announcement: 1), context: context)
        let counted = try plugin.handle(try volume(40, announcement: 2), context: context)
        let unknown = try plugin.handle(try volume(nil), context: context)
        let louder  = try plugin.handle(try volume(45, announcement: 3), context: context)
        let muted   = try plugin.handle(try volume(45, muted: true, announcement: 3), context: context)

        #expect(first.publications.count == 1)
        #expect(counted.publications.isEmpty)
        #expect(unknown.publications.isEmpty)
        #expect(louder.publications.count == 1)
        #expect(muted.publications.count == 1)
    }

    @Test
    func aRefreshRepublishesTheLastLevel() throws {
        let plugin = SoundPlugin()

        let first   = try plugin.handle(try volume(70), context: context)
        let refresh = try plugin.handle(.refresh, context: context)

        #expect(refresh.publications == first.publications)
        #expect(try plugin.handle(.wake, context: context).publications.isEmpty)
    }

    // MARK: - The faces and the manifest

    @Test
    func theWiderFaceIsChosenByItsFixedWidth() throws {
        let root   = try #require(try SoundFace.publication(for: PluginVolumeState(percentage: 40, isMuted: false, announcement: 0)).document).root
        let medium = try #require(root.children.first)

        #expect(medium.modifiers.contains { modifier in
            if case .frame(SoundFace.mediumWidth?, _, _, _, _) = modifier { return true }

            return false
        })
    }

    @Test
    func theManifestDeclaresBothTilesTheSourceAndTheBar() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == SoundPlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "SoundPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == SoundPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == [try PluginWidgetSize(columns: 1, rows: 1), try PluginWidgetSize(columns: 2, rows: 1)])
        #expect(feature.sources == [PluginVolumeState.source])
        #expect(feature.components == [try PluginComponentReference(id: "volume.level", version: 1)])
        #expect(feature.actions.isEmpty)
        #expect(!FirstPartyPlugins.placedByDefault.contains(SoundPlugin.id))
        #expect(FirstPartyPlugins.name(of: SoundPlugin.id) == "Volume")
        #expect(try ItalianStrings.value(of: "Volume") == "Volume")
    }
}
