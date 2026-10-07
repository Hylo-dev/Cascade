//
//  CaffeinateOptionsFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateOptionsFace is the page the kernel shows over the grid when the widget's text is
/// pressed. It has the notch's expanded footprint below Cascade's Back control, about 400 by 86
/// points, so it is two rows and fits without scrolling.
///
/// The first row is the disc, the title and the state in words, with one prominent Start pill
/// in the tint while off and a neutral Stop pill while on. The second is the stepper, whose
/// value is always visible beside it, the end time of a running session, and the display
/// switch. While off the value is the next session's length; while a session runs it is the
/// time left in hours and minutes, rounded up, which the kernel draws and keeps current, so the
/// page ticks without waking the plugin. It is not the compact countdown: `1h` for anything
/// between one and two hours would not move when a step takes fifteen minutes off. At the limits the matching button is dimmed, never hidden: it stays a button and the
/// native owner ignores a step off the scale.
enum CaffeinateOptionsFace {

    typealias Node    = CaffeinateStyle.Node
    typealias Action  = CaffeinateStyle.Action
    typealias Palette = CaffeinateStyle.Palette
    typealias Copy    = CaffeinateStyle.Copy

    static func page(
        _ state: PluginCaffeinateState,
        now    : Date
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: 8) {

            header(state)

            controls(state, now: now)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id("options.page")
    }

    // MARK: - First row

    private static func header(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 10) {

            CaffeinateWidgetFace.disc(
                state,
                id      : Node.powerOptions + ".glyph",
                diameter: 32
            )

            VStack(alignment: .leading, spacing: 1) {

                title(state)

                status(state)
            }

            Spacer(minLength: 8)

            Toggle(isOn: state.isActive, action: Action.power(isActive: state.isActive)) {

                pill(isOn: false)

                pill(isOn: true)
            }
            .id(Node.powerOptions)
            .accessibilityLabel(state.isActive ? Copy.stopLabel : Copy.startLabel)
        }
        .frame(height: 32)
    }

    /// status says what the Mac will do, in words: sleep normally, stay awake until a time the
    /// kernel draws in the user's locale, or until stopped; or why it could not start, with the
    /// code. A refused extension leaves the session as it was, so its line stays and the refusal
    /// sits beside the title, in the warning colour.
    private static func status(_ state: PluginCaffeinateState) -> PluginNode {
        if state.refusedToStart, let failure = state.failure {
            return warning(failure)
        }

        return HStack(spacing: 3) {

            if !state.isActive {
                Text(Copy.sleepsNormally)
            } else if let endsAt = state.endsAt {
                Text(Copy.awakeUntil)

                Text(endsAt, style: .time)
            } else {
                Text(Copy.awakeIndefinitely)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(state.isActive ? Palette.amber : Palette.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private static func title(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 6) {

            Text(Copy.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            if state.refusedToExtend, let failure = state.failure {
                warning(failure)
            }
        }
    }

    private static func warning(_ failure: CaffeinateFailure) -> PluginNode {
        HStack(spacing: 4) {

            Image(systemName: "exclamationmark.triangle.fill")

            Text(Copy.refusedWithCode(failure))
        }
        .font(.system(size: 11))
        .foregroundStyle(Palette.warning)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    /// pill is the main switch's label: Start in the tint while off, Stop in neutral while on.
    private static func pill(isOn: Bool) -> PluginNode {
        HStack(spacing: 4) {

            Image(systemName: isOn ? "stop.fill" : "play.fill")
                .font(.system(size: 8, weight: .bold))

            Text(isOn ? Copy.stop : Copy.start)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isOn ? .white : Palette.ink)
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background {
            Capsule()
                .foregroundStyle(isOn ? Palette.button : Palette.amber)
        }
    }

    // MARK: - Second row

    private static func controls(
        _ state: PluginCaffeinateState,
        now    : Date
    ) -> PluginNode {
        HStack(spacing: 12) {

            stepper(state, now: now)

            Spacer(minLength: 8)

            displaySwitch(state)
        }
        .frame(height: 26)
    }

    /// stepper is `− value +` and, while a timed session runs, "until" and its end time. While
    /// off the plus stops at 24 hours and the minus at indefinite; while running the minus stops
    /// at indefinite and the plus dims within fifteen minutes of the cap.
    private static func stepper(
        _ state: PluginCaffeinateState,
        now    : Date
    ) -> PluginNode {
        let remaining = state.remaining(at: now)
        let canGoDown = state.isActive ? state.endsAt != nil : state.nextDuration != .indefinite
        let canGoUp   = state.isActive
            ? remaining.map { $0 <= CaffeinateStyle.nearCap } ?? true
            : state.nextDuration != .minutes(CaffeinateDuration.maximumMinutes)

        return HStack(spacing: 6) {

            stepButton(
                symbol : "minus",
                action : Action.durationDown,
                id     : Node.durationDown,
                label  : Copy.shorter,
                enabled: canGoDown
            )

            value(state)

            stepButton(
                symbol : "plus",
                action : Action.durationUp,
                id     : Node.durationUp,
                label  : Copy.longer,
                enabled: canGoUp
            )

            if state.isActive, let endsAt = state.endsAt {
                HStack(spacing: 3) {

                    Text(Copy.until)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)

                    Text(endsAt, style: .time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                }
                .lineLimit(1)
            }
        }
    }

    /// value is the stepper's number, in rounded digits that keep their width.
    private static func value(_ state: PluginCaffeinateState) -> PluginNode {
        let font = PluginFont.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()

        if state.isActive, let endsAt = state.endsAt {
            return Text(countdownTo: endsAt, style: .hoursMinutes)
                .font(font)
                .foregroundStyle(Palette.amber)
                .frame(width: 58)
        }

        return Text(state.isActive ? "∞" : CaffeinateStyle.Format.duration(state.nextDuration))
            .font(font)
            .foregroundStyle(state.isActive ? Palette.amber : .white)
            .lineLimit(1)
            .frame(width: 58)
    }

    private static func stepButton(
        symbol : String,
        action : String,
        id     : String,
        label  : String,
        enabled: Bool
    ) -> PluginNode {
        Button(action: action) {

            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .background {
                    Circle()
                        .foregroundStyle(Palette.button)
                }
        }
        .id(id)
        .accessibilityLabel(label)
        .opacity(enabled ? 1 : CaffeinateStyle.dimmed)
    }

    /// displaySwitch is the whole row as one switch, so its label is as easy to hit as its track.
    private static func displaySwitch(_ state: PluginCaffeinateState) -> PluginNode {
        Toggle(isOn: state.keepsDisplayAwake, action: Action.display) {

            displayRow(isOn: false)

            displayRow(isOn: true)
        }
        .id(Node.display)
        .accessibilityLabel(Copy.keepDisplayAwake)
    }

    private static func displayRow(isOn: Bool) -> PluginNode {
        HStack(spacing: 6) {

            Image(systemName: isOn ? "display" : "moon.zzz")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Palette.amber : Palette.secondary)
                .frame(width: 16)

            Text(Copy.keepDisplayAwake)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Capsule()
                .foregroundStyle(isOn ? Palette.amber : Palette.track)
                .frame(width: 26, height: 15)
                .overlay(alignment: isOn ? .trailing : .leading) {

                    Circle()
                        .foregroundStyle(isOn ? Palette.ink : .white)
                        .frame(width: 11, height: 11)
                        .padding(.horizontal, 2)
                }
        }
        .frame(height: 20)
    }
}
