//
//  CaffeinateOptionsFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateOptionsFace is the page the kernel shows over the grid when the widget's text is
/// pressed. It has the notch's expanded footprint below Cascade's Back control, about 400 by 86
/// points, and it is two bands.
///
/// The top band has the selector leading: For, Until and ∞, three buttons in one track, the
/// chosen one filled, which pick how the session ends. Trailing are two round switches, the
/// display preference, a moon on grey while the display may sleep and a display on an amber
/// tint while it is kept awake, and the power switch, an amber disc with Play while off, the one
/// prominent action, and a grey disc with Stop while on. State is never colour alone: the
/// symbol changes with the fill, and the selector's accessibility labels say which one is chosen.
///
/// The bottom band has the ruler across most of the width and the big time trailing. The ruler is
/// the kernel's, a slider in the `ruler` style, and measures the length or the end time of the next
/// or the running session (`CaffeinateRuler`); with ∞ there is nothing to measure, and the
/// space says so instead. The time is the next session's length, its end time drawn by the kernel,
/// or the sign, in white, while off; and the kernel's countdown, or the elapsed time of an
/// indefinite session, in amber, while one runs, with the end's clock under the countdown of a
/// timed one. The kernel keeps them current, so the page ticks
/// without waking the plugin.
///
/// A refusal takes the top band's free space, with its sentence and code, in the warning colour:
/// the page has no caption to replace, and the code is for diagnosis.
enum CaffeinateOptionsFace {

    typealias Node    = CaffeinateStyle.Node
    typealias Action  = CaffeinateStyle.Action
    typealias Palette = CaffeinateStyle.Palette
    typealias Copy    = CaffeinateStyle.Copy

    /// The bands' heights and the gap between them: 30 + 6 + 46 is 82 of the page's 86 points.
    private static let topHeight    = 30.0
    private static let rulerHeight  = 46.0
    private static let bandSpacing  = 6.0
    private static let buttonSize   = 30.0

    /// timeWidth holds the big time at a width of its own, so the ruler does not change size as
    /// the digits change length. 124 points hold "10:45 PM" and "23:59:59" at 26 points.
    private static let timeWidth = 124.0

    /// warningWidth is the most the refusal's sentence asks for, about what the top band leaves
    /// between the selector and the round buttons in either language, so the page's natural
    /// width stays inside the notch's and the sentence wraps instead.
    private static let warningWidth = 160.0

    static func page(
        _ state : PluginCaffeinateState,
        now     : Date,
        calendar: Calendar
    ) -> PluginNode {
        let scale = CaffeinateRuler.scale(
            for     : state,
            now     : now,
            calendar: calendar
        )

        return VStack(alignment: .leading, spacing: bandSpacing) {

            topBand(state)

            bottomBand(state, scale: scale)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .id(Node.page)
    }

    // MARK: - Top band

    private static func topBand(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(alignment: .center, spacing: 8) {

            selector(state)

            if let failure = state.failure {
                warning(failure)
            } else {
                Spacer(minLength: 4)
            }

            displayButton(state)

            powerButton(state)
        }
        .frame(height: topHeight)
    }

    // MARK: - Selector

    /// selector is the three segments in one track. A segment is a button of its own: the
    /// native owner maps the action by name, and the chosen one is filled and says so to
    /// VoiceOver.
    private static func selector(_ state: PluginCaffeinateState) -> PluginNode {
        let shown = state.shownKind

        return HStack(spacing: 2) {

            segment(
                .duration,
                title: Copy.forDuration,
                spoken: Copy.forDuration,
                shown : shown
            )

            segment(
                .until,
                title : Copy.untilTime,
                spoken: Copy.untilTime,
                shown : shown
            )

            segment(
                .indefinite,
                title : CaffeinateStyle.Format.sign,
                spoken: Copy.untilYouStopIt,
                shown : shown
            )
        }
        .padding(2)
        .background {

            Capsule()
                .foregroundStyle(Palette.track)
        }
    }

    private static func segment(
        _ kind : CaffeinateTargetKind,
        title  : String,
        spoken : String,
        shown  : CaffeinateTargetKind
    ) -> PluginNode {
        let isChosen = kind == shown
        let label    = Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isChosen ? PluginColor.white : Palette.secondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)

        return Button(action: Action.mode(kind)) {

            if isChosen {
                label.background {

                    Capsule()
                        .foregroundStyle(Palette.selected)
                }
            } else {
                label
            }
        }
        .id(Node.mode(kind))
        .accessibilityLabel(isChosen ? Copy.selected(spoken) : spoken)
    }

    // MARK: - Round buttons

    /// powerButton is the power toggle: Play in the tint while off, Stop in grey while on.
    private static func powerButton(_ state: PluginCaffeinateState) -> PluginNode {
        Toggle(isOn: state.isActive, action: Action.power(isActive: state.isActive)) {

            roundButton(
                symbol: "play.fill",
                fill  : Palette.amber,
                glyph : Palette.ink
            )

            roundButton(
                symbol: "stop.fill",
                fill  : Palette.button,
                glyph : .white
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
                symbol: "moon.zzz",
                fill  : Palette.button,
                glyph : Palette.secondary
            )

            roundButton(
                symbol: "display",
                fill  : Palette.amber.opacity(0.28),
                glyph : Palette.amber
            )
        }
        .id(Node.display)
        .accessibilityLabel(Copy.keepDisplayAwake)
    }

    private static func roundButton(
        symbol: String,
        fill  : PluginColor,
        glyph : PluginColor
    ) -> PluginNode {
        ZStack {

            Circle()
                .foregroundStyle(fill)

            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(glyph)
        }
        .frame(width: buttonSize, height: buttonSize)
    }

    /// warning is a refusal's sentence and code, on up to two lines in the free space between
    /// the selector and the round buttons.
    private static func warning(_ failure: CaffeinateFailure) -> PluginNode {
        HStack(spacing: 4) {

            Image(systemName: "exclamationmark.triangle.fill")

            Text(Copy.refusedWithCode(failure))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 10))
        .foregroundStyle(Palette.warning)
        .frame(maxWidth: .points(warningWidth), alignment: .leading)
    }

    // MARK: - Bottom band

    private static func bottomBand(
        _ state: PluginCaffeinateState,
        scale  : CaffeinateRuler.Scale?
    ) -> PluginNode {
        HStack(alignment: .center, spacing: 8) {

            if let scale {
                ruler(scale)
            } else {
                nothingToMeasure()
            }

            time(state, scale: scale)
        }
        .frame(height: rulerHeight)
    }

    /// ruler is the kernel's ruler slider, tinted by its own foreground colour. It is greedy,
    /// so it takes what the time leaves, and it needs a height of its own.
    private static func ruler(_ scale: CaffeinateRuler.Scale) -> PluginNode {
        Slider(
            value : scale.value,
            in    : scale.lowerBound...scale.upperBound,
            step  : scale.step,
            style : .ruler(labelEvery: CaffeinateRuler.labelEvery, labels: scale.labels),
            action: scale.action
        )
        .foregroundStyle(Palette.amber)
        .frame(height: rulerHeight, maxWidth: .infinity)
        .id(Node.ruler)
        .accessibilityLabel(scale.labels == .duration ? Copy.rulerLength : Copy.rulerEnds)
    }

    /// nothingToMeasure takes the ruler's place with ∞, which has no length to choose.
    private static func nothingToMeasure() -> PluginNode {
        Text(Copy.untilYouStopIt)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Palette.secondary)
            .lineLimit(1)
            .padding(.leading, 6)
            .frame(height: rulerHeight, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Time

    /// endLine says when a running timed session ends, under its countdown: "until" and the
    /// end's clock, which the kernel draws in the user's locale. A time node carries its own
    /// font and colour.
    private static func endLine(_ endsAt: Date) -> PluginNode {
        let font = PluginFont.system(size: 10, weight: .medium)

        return HStack(spacing: 3) {

            Text(Copy.until)
                .font(font)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)

            Text(endsAt, style: .time)
                .font(font)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
        }
    }

    /// time is the big number, in rounded digits that keep their width. Its font and its tint
    /// sit on the node itself, because the kernel reads them from a time node and never from a
    /// parent.
    private static func time(
        _ state: PluginCaffeinateState,
        scale  : CaffeinateRuler.Scale?
    ) -> PluginNode {
        let font = PluginFont.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()

        if state.isActive, let elapsed = state.elapsed, let endsAt = state.endsAt {
            return VStack(alignment: .trailing, spacing: 0) {

                Text(timerInterval: elapsed, countsDown: true)
                    .font(font)
                    .foregroundStyle(Palette.amber)
                    .lineLimit(1)

                endLine(endsAt)
            }
            .frame(width: timeWidth, alignment: .trailing)
        }

        if let countUp = state.countUp {
            return Text(timerInterval: countUp, countsDown: false)
                .font(font)
                .foregroundStyle(Palette.amber)
                .lineLimit(1)
                .frame(width: timeWidth, alignment: .trailing)
        }

        if state.nextTarget.kind == .until, let scale {
            return Text(Date(timeIntervalSince1970: scale.value), style: .time)
                .font(font)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: timeWidth, alignment: .trailing)
        }

        return Text(CaffeinateStyle.Format.target(state.nextTarget))
            .font(font)
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(width: timeWidth, alignment: .trailing)
    }
}
