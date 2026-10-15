//
//  CaffeinateActivityFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateActivityFace is the live activity of a running session, in the Dynamic Island's
/// own grammar: a glyph in the key tint leading, the value trailing in rounded digits that keep
/// their width, the glyph alone when the island is shared.
///
/// The compact trailing region is the time left, drawn by the kernel as `2h`, `24m` or `4:59`
/// and kept current without waking the plugin; an indefinite session has no time to show, so
/// that region is an empty spacer and the compact activity is the glyph alone. It has three
/// regions and no expanded one: a status that never takes over the opened notch, where the
/// widget and its options page already hold the controls.
enum CaffeinateActivityFace {

    typealias Palette = CaffeinateStyle.Palette
    typealias Copy    = CaffeinateStyle.Copy

    /// relevance is low on purpose: a playing song takes the compact slot and Caffeinate drops
    /// to the minimal presentation, as on the island.
    static let relevance = 0.3

    static func publication(
        for state: PluginCaffeinateState,
        now      : Date
    ) throws -> PluginPublication {
        try PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .activity,
            document: PluginDocument(
                root: Regions {

                    glyph(state, size: 14)

                    compactTrailing(state)

                    glyph(state, size: 14)
                }
            ),
            activity: PluginActivityAttributes(
                startedAt         : state.activityStartedAt ?? state.startedAt ?? now,
                relevance         : relevance,
                accessibilityLabel: Copy.activityLabel(endsAt: state.endsAt)
            )
        )
    }

    /// withdrawal ends the activity: a publication with no document.
    static func withdrawal() throws -> PluginPublication {
        try PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .activity,
            document: nil
        )
    }

    private static func glyph(
        _ state: PluginCaffeinateState,
        size   : Double
    ) -> PluginNode {
        Image(systemName: state.glyph.filledSymbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Palette.amber)
    }

    private static func compactTrailing(_ state: PluginCaffeinateState) -> PluginNode {
        guard let endsAt = state.endsAt else { return Spacer(minLength: 0) }

        return Text(countdownTo: endsAt)
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Palette.amber)
    }
}
