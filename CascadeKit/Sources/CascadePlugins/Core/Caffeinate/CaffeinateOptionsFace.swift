//
//  CaffeinateOptionsFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateOptionsFace is the page the kernel shows over the grid when the widget's text is
/// pressed. It has the notch's expanded footprint below Cascade's Back control, about 400 by 86
/// points, and it is one row, as the iOS Timer's: two round buttons leading, a stepper trailing.
///
/// The leading buttons are the power switch, an amber disc with Play while off, the one
/// prominent action, and a grey disc with Stop while on, and the display switch, a moon on a
/// grey disc while off and a display on an amber-tinted one while on. Each has a small caption
/// under it, and the whole column is the switch, so its label is as easy to hit as its disc.
/// State is never colour alone: the symbol changes with the fill.
///
/// The trailing group is the time with a caption under it (Task 3 of the ruler plan puts the
/// ruler and the selector there; the step buttons are gone). While off the time is the
/// next session's length, in white, and the caption says "Next session". While a session runs
/// the time is the kernel's timer, counting down to the end, or up for an indefinite session,
/// in amber, and the caption says "until" and the end time, or "active for". The kernel draws
/// and keeps them current, so the page ticks without waking the plugin. A refusal replaces the
/// caption with its sentence and the code, in the warning colour.
enum CaffeinateOptionsFace {

    typealias Node    = CaffeinateStyle.Node
    typealias Action  = CaffeinateStyle.Action
    typealias Palette = CaffeinateStyle.Palette
    typealias Copy    = CaffeinateStyle.Copy

    /// timeWidth holds the big time at a width of its own, so the stepper's buttons do not
    /// move as its digits change length.
    private static let timeWidth = 124.0

    static func page(
        _ state: PluginCaffeinateState,
        now    : Date
    ) -> PluginNode {
        HStack(alignment: .center, spacing: 14) {

            powerButton(state)

            displayButton(state)

            Spacer(minLength: 8)

            timeAndCaption(state)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .id("options.page")
    }

    // MARK: - Round buttons

    /// powerButton is the power toggle: Play in the tint while off, Stop in grey while on.
    private static func powerButton(_ state: PluginCaffeinateState) -> PluginNode {
        Toggle(isOn: state.isActive, action: Action.power(isActive: state.isActive)) {

            roundButton(
                symbol : "play.fill",
                fill   : Palette.amber,
                glyph  : Palette.ink,
                caption: Copy.start
            )

            roundButton(
                symbol : "stop.fill",
                fill   : Palette.button,
                glyph  : .white,
                caption: Copy.stop
            )
        }
        .id(Node.powerOptions)
        .accessibilityLabel(state.isActive ? Copy.stopLabel : Copy.startLabel)
    }

    /// displayButton is the display preference: a moon on grey while the display may sleep, a
    /// display on the tint while it is kept awake.
    private static func displayButton(_ state: PluginCaffeinateState) -> PluginNode {
        Toggle(isOn: state.keepsDisplayAwake, action: Action.display) {

            roundButton(
                symbol : "moon.zzz",
                fill   : Palette.button,
                glyph  : Palette.secondary,
                caption: Copy.display
            )

            roundButton(
                symbol : "display",
                fill   : Palette.amber.opacity(0.28),
                glyph  : Palette.amber,
                caption: Copy.display
            )
        }
        .id(Node.display)
        .accessibilityLabel(Copy.keepDisplayAwake)
    }

    private static func roundButton(
        symbol : String,
        fill   : PluginColor,
        glyph  : PluginColor,
        caption: String
    ) -> PluginNode {
        VStack(spacing: 3) {

            ZStack {

                Circle()
                    .foregroundStyle(fill)

                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(glyph)
            }
            .frame(width: 40, height: 40)

            Text(caption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Time

    /// timeAndCaption is the time and, under it, what the time means. The ruler redesign puts
    /// the controls that choose it here.
    private static func timeAndCaption(_ state: PluginCaffeinateState) -> PluginNode {
        VStack(spacing: 3) {

            time(state)

            caption(state)
        }
        .frame(height: 40 + 3 + 14)
    }

    /// time is the big number, in rounded digits that keep their width. Its font and its tint
    /// sit on the node itself, because the kernel reads them from a time node and never from a
    /// parent.
    private static func time(_ state: PluginCaffeinateState) -> PluginNode {
        let font = PluginFont.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()

        if state.isActive, let elapsed = state.elapsed {
            return Text(timerInterval: elapsed, countsDown: true)
                .font(font)
                .foregroundStyle(Palette.amber)
                .lineLimit(1)
                .frame(width: timeWidth)
        }

        if let countUp = state.countUp {
            return Text(timerInterval: countUp, countsDown: false)
                .font(font)
                .foregroundStyle(Palette.amber)
                .lineLimit(1)
                .frame(width: timeWidth)
        }

        return Text(CaffeinateStyle.Format.target(state.nextTarget))
            .font(font)
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: timeWidth)
    }

    /// caption says what the time is: the next session, the end of this one, or how long an
    /// indefinite one has run. A refusal says so instead, with its code, because the code is
    /// for diagnosis and this is the one place with the room for it.
    private static func caption(_ state: PluginCaffeinateState) -> PluginNode {
        if let failure = state.failure {
            return warning(failure)
        }

        return HStack(spacing: 3) {

            if !state.isActive {
                Text(Copy.nextSession)
            } else if let endsAt = state.endsAt {
                Text(Copy.until)

                Text(endsAt, style: .time)
            } else {
                Text(Copy.activeFor)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.secondary)
        .lineLimit(1)
    }

    private static func warning(_ failure: CaffeinateFailure) -> PluginNode {
        HStack(spacing: 4) {

            Image(systemName: "exclamationmark.triangle.fill")

            Text(Copy.refusedWithCode(failure))
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.warning)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
