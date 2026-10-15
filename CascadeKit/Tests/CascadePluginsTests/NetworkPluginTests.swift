//
//  NetworkPluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct NetworkPluginTests {

    private let context = PluginContext(plugin: NetworkPlugin.id)

    private func network(
        _ interface  : PluginNetworkInterface,
        isConnected  : Bool = true,
        isExpensive  : Bool = false,
        isConstrained: Bool = false
    ) throws -> PluginEvent {
        .source(
            try PluginNetworkState(
                isConnected  : isConnected,
                interface    : interface,
                isExpensive  : isExpensive,
                isConstrained: isConstrained
            )
            .event()
        )
    }

    private func root(of output: PluginOutput) throws -> PluginNode {
        let publication = try #require(output.publications.first)

        #expect(output.publications.count == 1)
        #expect(output.wake == nil)
        #expect(publication.feature == NetworkPlugin.feature)
        #expect(publication.surface == .widget)

        return try #require(publication.document).root
    }

    /// expectLink holds every face to the symbol and the word of a link, and the 2x1 face to them
    /// alone, so a mark only ever appears where a test asks for one.
    private func expectLink(
        _ event: PluginEvent,
        symbol : String,
        word   : String
    ) throws {
        let root   = try root(of: NetworkPlugin().handle(event, context: context))
        let medium = try #require(root.children.first)

        #expect(root.kind == .viewThatFits(axes: .horizontal))
        #expect(root.children.count == 2)
        #expect(root.children.allSatisfy { PluginNodeSearch.kinds(in: $0).contains(.symbol(name: symbol)) })
        #expect(root.children.allSatisfy { PluginNodeSearch.texts(in: $0) == [word] })
        #expect(PluginNodeSearch.texts(in: medium) == [word])
        #expect(PluginNodeSearch.accessibilityLabel(of: root) == word)
    }

    // MARK: - The plugin

    @Test
    func anOfflineMacSaysSo() throws {
        try expectLink(try network(.none, isConnected: false), symbol: "wifi.slash", word: "Offline")
        try expectLink(try network(.wifi, isConnected: false), symbol: "wifi.slash", word: "Offline")
    }

    @Test
    func eachLinkHasItsSymbolAndItsWord() throws {
        try expectLink(try network(.wifi), symbol: "wifi", word: "Wi-Fi")
        try expectLink(try network(.ethernet), symbol: "cable.connector", word: "Ethernet")
        try expectLink(try network(.cellular), symbol: "antenna.radiowaves.left.and.right", word: "Cellular")
        try expectLink(try network(.other), symbol: "network", word: "Connected")
        #expect(try ItalianStrings.value(of: "Cellular") == "Cellulare")
        #expect(try ItalianStrings.value(of: "Connected") == "Connessa")
    }

    /// A constrained path is Low Data Mode and an expensive one a hotspot or a cellular plan: the
    /// short face adds the mark below the word, and the small face, with room for one word, shows
    /// the mark in place of the link's name, which its symbol already gives.
    @Test
    func aConstrainedOrExpensivePathCarriesItsMark() throws {
        let limited = try root(of: NetworkPlugin().handle(try network(.wifi, isConstrained: true), context: context))
        let metered = try root(of: NetworkPlugin().handle(try network(.cellular, isExpensive: true), context: context))
        let both    = try root(of: NetworkPlugin().handle(try network(.wifi, isExpensive: true, isConstrained: true), context: context))

        #expect(PluginNodeSearch.texts(in: limited.children[0]) == ["Wi-Fi", "Limited"])
        #expect(PluginNodeSearch.texts(in: limited.children[1]) == ["Limited"])
        #expect(PluginNodeSearch.texts(in: metered.children[0]) == ["Cellular", "Metered"])
        #expect(PluginNodeSearch.texts(in: metered.children[1]) == ["Metered"])
        #expect(PluginNodeSearch.texts(in: both.children[0]) == ["Wi-Fi", "Limited"])
        #expect(PluginNodeSearch.accessibilityLabel(of: both) == "Wi-Fi, Limited, Metered")
        #expect(try ItalianStrings.value(of: "Limited") == "Limitata")
        #expect(try ItalianStrings.value(of: "Metered") == "A consumo")
    }

    @Test
    func anUnchangedPathPublishesNothing() throws {
        let plugin = NetworkPlugin()

        let first   = try plugin.handle(try network(.wifi), context: context)
        let again   = try plugin.handle(try network(.wifi), context: context)
        let limited = try plugin.handle(try network(.wifi, isConstrained: true), context: context)

        #expect(first.publications.count == 1)
        #expect(again.publications.isEmpty)
        #expect(limited.publications.count == 1)
    }

    @Test
    func aRefreshRepublishesTheLastPathAndNothingBeforeOne() throws {
        let plugin = NetworkPlugin()

        let early   = try plugin.handle(.refresh, context: context)
        let first   = try plugin.handle(try network(.ethernet), context: context)
        let refresh = try plugin.handle(.refresh, context: context)

        #expect(early.publications.isEmpty)
        #expect(refresh.publications == first.publications)
        #expect(try plugin.handle(.wake, context: context).publications.isEmpty)
    }

    // MARK: - The faces and the manifest

    @Test
    func theWiderFaceIsChosenByItsFixedWidth() throws {
        let state  = PluginNetworkState(isConnected: true, interface: .wifi, isExpensive: false, isConstrained: false)
        let root   = try #require(try NetworkFace.publication(for: state).document).root
        let medium = try #require(root.children.first)

        #expect(medium.modifiers.contains { modifier in
            if case .frame(NetworkFace.mediumWidth?, _, _, _, _) = modifier { return true }

            return false
        })
    }

    @Test
    func theManifestDeclaresBothTilesAndTheSource() throws {
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == NetworkPlugin.id })
        let feature  = try #require(manifest.features.first)

        #expect(manifest.execution.entryPoint == "NetworkPlugin")
        #expect(manifest.features.count == 1)
        #expect(feature.id == NetworkPlugin.feature)
        #expect(feature.surfaces.widget?.sizes == [try PluginWidgetSize(columns: 1, rows: 1), try PluginWidgetSize(columns: 2, rows: 1)])
        #expect(feature.sources == [PluginNetworkState.source])
        #expect(feature.components.isEmpty)
        #expect(feature.permissions.isEmpty)
        #expect(!FirstPartyPlugins.placedByDefault.contains(NetworkPlugin.id))
        #expect(FirstPartyPlugins.name(of: NetworkPlugin.id) == "Network")
        #expect(try ItalianStrings.value(of: "Network") == "Rete")
    }
}
