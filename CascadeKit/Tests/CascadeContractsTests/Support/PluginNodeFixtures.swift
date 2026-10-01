//
//  PluginNodeFixtures.swift
//  CascadeKit
//

import Foundation

@testable import CascadeContracts

/// PluginNodeFixtures builds the documents the plugin contract tests share: today's clock face
/// and a compact Music row, written the way the SDK builder will produce them.
enum PluginNodeFixtures {

    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    static func clock() -> PluginNode {
        PluginNode(
            .date(now, style: .time),
            modifiers: [
                .font(PluginFont(size: 18, weight: .semibold, design: .rounded, monospacedDigit: true)),
                .foregroundStyle(.color(.white)),
                .minimumScaleFactor(0.5),
                .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .center),
            ]
        )
    }

    static func musicRow(
        title    : String = "Song",
        artist   : String = "Artist",
        isPlaying: Bool = true
    ) -> PluginNode {
        PluginNode(
            .hStack(alignment: .center, spacing: 8),
            children: [
                PluginNode(
                    .asset(id: "artwork"),
                    modifiers: [
                        .frame(width: 32, height: 32, maxWidth: nil, maxHeight: nil, alignment: .center),
                        .clipShape(.roundedRectangle(cornerRadius: 6)),
                    ]
                ),
                PluginNode(
                    .vStack(alignment: .leading, spacing: nil),
                    children: [
                        PluginNode(.text(title), modifiers: [.font(PluginFont(style: .headline)), .lineLimit(1)]),
                        PluginNode(.text(artist), modifiers: [.font(PluginFont(style: .caption)), .foregroundStyle(.hierarchical(.secondary))]),
                    ]
                ),
                PluginNode(.spacer(minLength: nil)),
                PluginNode(
                    .toggle(isOn: isPlaying, action: "togglePlayback"),
                    modifiers: [.contentTransition(.symbolEffect)],
                    children : [PluginNode(.symbol(name: isPlaying ? "pause.fill" : "play.fill"))]
                ),
            ]
        )
    }

    /// stack returns a vertical stack of `count` text leaves under one root: `count + 1` nodes.
    static func stack(of count: Int) -> PluginNode {
        PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: (0..<count).map { index in PluginNode(.text("\(index)")) }
        )
    }

    /// nested returns a chain of `depth` vertical stacks, the innermost holding one text.
    static func nested(depth: Int) -> PluginNode {
        (1..<depth).reduce(PluginNode(.text("leaf"))) { inner, _ in
            PluginNode(.vStack(alignment: .center, spacing: nil), children: [inner])
        }
    }
}
