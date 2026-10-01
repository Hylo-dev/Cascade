//
//  PluginRenderFixtures.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadePluginEngine

/// PluginRenderFixtures produces real kernel changes for the renderer tests: a now-playing face
/// whose title, artist and controls carry explicit ids, run through the engine's own store so
/// every diff is the one the kernel would deliver.
enum PluginRenderFixtures {

    static let key = PluginPublicationKey(
        plugin : PluginID(rawValue: "com.cascade.music")!,
        feature: "now-playing",
        surface: .activity
    )

    static func face(
        title    : String = "One",
        isPlaying: Bool = true,
        volume   : Double = 0.5,
        art      : PluginNodeKind = .text("Art")
    ) throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .hStack(alignment: .center, spacing: 8),
                children: [
                    PluginNode(art),
                    PluginNode(
                        .vStack(alignment: .leading, spacing: nil),
                        children: [
                            PluginNode(.text(title), id: "title"),
                            PluginNode(.text("Artist"), id: "artist"),
                        ]
                    ),
                    PluginNode(.toggle(isOn: isPlaying, action: "togglePlayback"), id: "play"),
                    PluginNode(.slider(value: volume, minimum: 0, maximum: 1, step: nil, action: "setVolume"), id: "volume"),
                    PluginNode(.button(action: "next"), id: "next"),
                ]
            )
        )
    }

    /// Publisher runs documents through the engine's publication store, as the kernel does.
    struct Publisher {

        private var store = PluginPublicationStore()

        mutating func publish(_ document: PluginDocument) -> PluginPublicationChange {
            store.apply(document, staleAfter: nil, for: key, at: Date())
                ?? PluginPublicationChange(key: key, revision: 0, content: nil)
        }

        mutating func withdraw() -> PluginPublicationChange? {
            store.withdraw(key)
        }
    }
}
