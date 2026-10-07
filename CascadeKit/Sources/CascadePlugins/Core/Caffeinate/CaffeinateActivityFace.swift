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
/// that region is an empty spacer and the compact activity is the glyph alone. The expanded
/// region follows the iOS Timer: a round Stop in the tint and a grey +15m on the leading edge,
/// the large time on the trailing one with "until" and the end time, or, for an indefinite
/// session, the elapsed time counting up with "active for". At most two actions, both about the
/// session. The +15m dims within fifteen minutes of the 24-hour cap and is absent when the
/// session has no end to move.
enum CaffeinateActivityFace {

    typealias Node    = CaffeinateStyle.Node
    typealias Action  = CaffeinateStyle.Action
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

                    expanded(state, now: now)
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

    // MARK: - Compact and minimal

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

    // MARK: - Expanded

    private static func expanded(
        _ state: PluginCaffeinateState,
        now    : Date
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: 6) {

            HStack(spacing: 5) {

                glyph(state, size: 12)

                Text(Copy.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {

                stopButton(state)

                if let remaining = state.remaining(at: now) {
                    extendButton(isDimmed: remaining >= CaffeinateStyle.nearCap)
                }

                Spacer(minLength: 8)

                largeTime(state)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// stopButton is the round tinted Stop. It is only drawn while a session runs, so it is the
    /// power toggle in its on state and its action is always the stop.
    private static func stopButton(_ state: PluginCaffeinateState) -> PluginNode {
        Toggle(isOn: state.isActive, action: Action.power(isActive: state.isActive)) {

            ZStack {

                Circle()
                    .foregroundStyle(Palette.amber)

                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 40, height: 40)
        }
        .id(Node.powerActivity)
        .accessibilityLabel(Copy.stopLabel)
    }

    private static func extendButton(isDimmed: Bool) -> PluginNode {
        Button(action: Action.extend) {

            ZStack {

                Circle()
                    .foregroundStyle(Palette.button)

                Text("+" + CaffeinateStyle.Format.minutes(900))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 40, height: 40)
        }
        .id(Node.extend)
        .accessibilityLabel(Copy.addFifteen)
        .opacity(isDimmed ? CaffeinateStyle.dimmed : 1)
    }

    /// largeTime is the big number: the time left with the end time under it, or the elapsed
    /// time of an indefinite session with "active for" above it. Both are kernel-drawn, and the
    /// big font and the tint sit on the time node itself, where the kernel reads them.
    private static func largeTime(_ state: PluginCaffeinateState) -> PluginNode {
        let font = PluginFont.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()

        return VStack(alignment: .trailing, spacing: 1) {

            if let elapsed = state.elapsed, let endsAt = state.endsAt {
                Text(timerInterval: elapsed, countsDown: true)
                    .font(font)
                    .foregroundStyle(Palette.amber)

                HStack(spacing: 3) {

                    Text(Copy.until)

                    Text(endsAt, style: .time)
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
            } else if let countUp = state.countUp {
                Text(Copy.activeFor)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)

                Text(timerInterval: countUp, countsDown: false)
                    .font(font)
                    .foregroundStyle(Palette.amber)
            }
        }
    }
}
