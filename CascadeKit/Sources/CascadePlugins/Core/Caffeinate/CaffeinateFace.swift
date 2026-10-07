//
//  CaffeinateFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateFace is the Caffeinate widget's document: a face for each size the widget comes in,
/// and the options page the kernel shows over the grid when the title is pressed.
///
/// The large face is laid out like a Control Center module, without its pill: the cup in its
/// disc on the leading edge, the title and the state beside it, and a chevron saying the title
/// opens more. The small face is the cup alone. The cup and the title are siblings, so starting
/// a session never opens the options page and opening it never starts one.
///
/// The 2x1 tile is 110 by 40 points in the default notch, the 1x1 tile 52 by 40. The large face
/// is held at 100 points, as the battery's medium face is, because `ViewThatFits` measures a
/// face's ideal width against the tile: a face wider than the tile never fits, and the widget
/// would show only its cup in every size.
///
/// The options page has the notch's expanded footprint below Cascade's Back control, about 400
/// by 86 points, so it is three rows: the state in words beside the main switch, the duration
/// picker, and the display option. Only the active state and the selected duration use amber.
/// A timed session's countdown and end time are drawn by the kernel from fixed dates, so the
/// page ticks while visible without waking the plugin.
///
/// Every control keeps a stable explicit identity whatever the state, so a publication updates
/// it in place; `CaffeinateCommand` decodes the same identities. While the native owner is
/// busy the controls stay where they are, dimmed, and the owner ignores them.
enum CaffeinateFace {

    static let largeWidth = 100.0

    static func publication(for state: PluginCaffeinateState) throws -> PluginPublication {
        try PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .horizontal) {

                    large(state)

                    small(state)
                }
                .foregroundStyle(.white),
                optionsRoot  : options(state),
                optionsAction: Action.options
            )
        )
    }

    // MARK: - Widget faces

    /// large is the 2x1 face: the cup on the leading edge, then the title and the state, which
    /// open the options page.
    private static func large(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 6) {

            cupSwitch(state, id: Node.power[0], diameter: 28)

            Button(action: Action.options) {

                HStack(spacing: 3) {

                    VStack(alignment: .leading, spacing: 1) {

                        Text(Copy.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        shortStatus(state)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .id(Node.opener)
            .accessibilityLabel(Copy.options)
        }
        .padding(.horizontal, 2)
        .frame(
            width    : largeWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the cup alone, still the power switch.
    private static func small(_ state: PluginCaffeinateState) -> PluginNode {
        cupSwitch(state, id: Node.power[1], diameter: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// shortStatus is the tile's second line: off, on, or the time left of a timed session.
    private static func shortStatus(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 3) {

            if state.isActive, !state.isBusy, state.error == nil, let interval = interval(of: state) {
                Image(systemName: "hourglass")
                    .font(.system(size: 8, weight: .semibold))

                Text(timerInterval: interval)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
            } else {
                Text(shortStatusText(of: state))
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(state.isActive ? Palette.amber : Palette.secondary)
        .lineLimit(1)
    }

    // MARK: - Options page

    /// options is the fullscreen page, three rows tall.
    private static func options(_ state: PluginCaffeinateState) -> PluginNode {
        VStack(alignment: .leading, spacing: 5) {

            header(state)

            durations(state)

            displaySwitch(state)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .id("options.page")
    }

    /// header is the cup and the state in words, with the main switch on the trailing edge: an
    /// amber Start pill while off, a quiet Stop pill while on.
    private static func header(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 10) {

            cup(state, id: "options.cup", diameter: 32)

            VStack(alignment: .leading, spacing: 1) {

                Text(Copy.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                longStatus(state)
            }

            Spacer(minLength: 8)

            Toggle(isOn: state.isActive, action: Action.toggle) {

                pill(isOn: false)

                pill(isOn: true)
            }
            .id(Node.power[2])
            .accessibilityLabel(Copy.toggle)
            .opacity(controlOpacity(of: state))
        }
        .frame(height: 32)
    }

    /// longStatus says what the Mac will do: sleep normally, stay awake until stopped, or stay
    /// awake until a time the kernel formats in the user's locale, with the time left beside it.
    private static func longStatus(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 4) {

            if let error = state.error {
                Image(systemName: "exclamationmark.triangle.fill")

                Text(error)
            } else if state.isBusy {
                Text(Copy.updating)
            } else if !state.isActive {
                Text(Copy.sleepsNormally)
            } else if let until = state.until {
                Text(Copy.awakeUntil)

                Text(until, style: .time)

                if let interval = interval(of: state) {
                    Text("·")

                    Text(timerInterval: interval)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .accessibilityLabel(Copy.remaining)
                }
            } else {
                Text(Copy.awakeIndefinitely)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(state.error != nil ? Palette.warning : state.isActive ? Palette.amber : Palette.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    /// durations is a segmented row of the supported lengths. Picking one while a session runs
    /// restarts it with the new length; while off it only becomes the next session's length.
    private static func durations(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 4) {

            for minutes in CaffeinateCommand.durations {
                Button(action: Action.duration(minutes)) {

                    segment(minutes, isSelected: minutes == state.minutes)
                }
                .id(Node.duration(minutes))
                .accessibilityLabel(Copy.durationLabel(minutes))
            }
        }
        .frame(height: 22)
        .opacity(controlOpacity(of: state))
    }

    private static func segment(
        _ minutes : Int,
        isSelected: Bool
    ) -> PluginNode {
        Text(Copy.durationShort(minutes))
            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? Palette.ink : .white)
            .lineLimit(1)
            .frame(height: 22, maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .foregroundStyle(isSelected ? Palette.amber : Palette.fill)
            }
    }

    /// displaySwitch is the whole row as one switch, so its label is as easy to hit as its track.
    private static func displaySwitch(_ state: PluginCaffeinateState) -> PluginNode {
        Toggle(isOn: state.keepDisplayAwake, action: Action.display) {

            displayRow(isOn: false)

            displayRow(isOn: true)
        }
        .id(Node.display)
        .accessibilityLabel(Copy.keepDisplayAwake)
        .opacity(controlOpacity(of: state))
    }

    private static func displayRow(isOn: Bool) -> PluginNode {
        HStack(spacing: 8) {

            Image(systemName: isOn ? "display" : "moon.zzz")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Palette.amber : Palette.secondary)
                .frame(width: 16)

            Text(Copy.keepDisplayAwake)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)

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

    // MARK: - Shared pieces

    /// cupSwitch is the cup with a transparent power switch over it. The glyph lives outside the
    /// switch, so its symbol transition survives the switch's value changing.
    private static func cupSwitch(
        _ state : PluginCaffeinateState,
        id      : String,
        diameter: Double
    ) -> PluginNode {
        ZStack {

            cup(state, id: id + ".cup", diameter: diameter)

            Toggle(isOn: state.isActive, action: Action.toggle) {

                Circle()
                    .opacity(0)
                    .frame(width: diameter, height: diameter)
            }
            .id(id)
            .accessibilityLabel(Copy.toggle)
        }
        .frame(width: diameter, height: diameter)
        .opacity(controlOpacity(of: state))
    }

    /// cup is the disc and the glyph: amber with a full cup while a session runs.
    private static func cup(
        _ state : PluginCaffeinateState,
        id      : String,
        diameter: Double
    ) -> PluginNode {
        ZStack {

            Circle()
                .foregroundStyle(state.isActive ? Palette.amber : Palette.cupRest)

            Image(systemName: state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: (diameter * 0.5).rounded(), weight: .semibold))
                .foregroundStyle(state.isActive ? Palette.ink : .white)
                .contentTransition(.symbolEffect)
                .id(id)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel(shortStatusText(of: state))
    }

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
                .foregroundStyle(isOn ? Palette.fillStrong : Palette.amber)
        }
    }

    private static func interval(of state: PluginCaffeinateState) -> ClosedRange<Date>? {
        guard let until = state.until, state.minutes > 0 else { return nil }

        let start = until.addingTimeInterval(-Double(state.minutes * 60))
        return start < until ? start...until : nil
    }

    private static func controlOpacity(of state: PluginCaffeinateState) -> Double {
        state.isBusy ? 0.5 : 1
    }

    private static func shortStatusText(of state: PluginCaffeinateState) -> String {
        if state.error != nil { return Copy.error }
        if state.isBusy { return Copy.updating }

        return state.isActive ? Copy.on : Copy.off
    }
}

extension CaffeinateFace {

    /// Node holds the explicit identities `CaffeinateCommand` decodes. The three power switches
    /// are the large face's, the small face's and the options page's.
    enum Node {

        static let power   = ["power.large", "power.small", "power.options"]
        static let display = "display"
        static let opener  = "options"

        static func duration(_ minutes: Int) -> String { "duration.\(minutes)" }

        /// reference is the identity `PluginNodeTable` gives a node with an explicit id.
        static func reference(
            _ id: String,
            kind: String
        ) -> String {
            "#" + id + ":" + kind
        }
    }

    enum Action {

        static let toggle  = "caffeinate.toggle"
        static let options = "caffeinate.options"
        static let display = "caffeinate.display"

        static func duration(_ minutes: Int) -> String { "caffeinate.duration.\(minutes)" }
    }

    enum Palette {

        static let amber      = PluginColor(red: 1, green: 0.77, blue: 0.33)
        static let ink        = PluginColor(red: 0.15, green: 0.13, blue: 0.10)
        static let warning    = PluginColor(red: 1, green: 0.55, blue: 0.45)
        static let secondary  = PluginColor(red: 0.70, green: 0.70, blue: 0.74)
        static let tertiary   = PluginColor(red: 0.50, green: 0.50, blue: 0.54)
        static let cupRest    = PluginColor.white.opacity(0.14)
        static let fill       = PluginColor.white.opacity(0.08)
        static let fillStrong = PluginColor.white.opacity(0.16)
        static let track      = PluginColor.white.opacity(0.22)
    }

    enum Copy {

        static var title            : String { String(localized: "Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var options          : String { String(localized: "Caffeinate Options", table: "CaffeinateWidget", bundle: .module) }
        static var toggle           : String { String(localized: "Toggle Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var on               : String { String(localized: "On", table: "CaffeinateWidget", bundle: .module) }
        static var off              : String { String(localized: "Off", table: "CaffeinateWidget", bundle: .module) }
        static var error            : String { String(localized: "Error", table: "CaffeinateWidget", bundle: .module) }
        static var updating         : String { String(localized: "Updating…", table: "CaffeinateWidget", bundle: .module) }
        static var start            : String { String(localized: "Start", table: "CaffeinateWidget", bundle: .module) }
        static var stop             : String { String(localized: "Stop", table: "CaffeinateWidget", bundle: .module) }
        static var sleepsNormally   : String { String(localized: "Your Mac sleeps normally", table: "CaffeinateWidget", bundle: .module) }
        static var awakeIndefinitely: String { String(localized: "Awake until you stop it", table: "CaffeinateWidget", bundle: .module) }
        static var awakeUntil       : String { String(localized: "Awake until", table: "CaffeinateWidget", bundle: .module) }
        static var remaining        : String { String(localized: "Time left", table: "CaffeinateWidget", bundle: .module) }
        static var keepDisplayAwake : String { String(localized: "Keep display awake", table: "CaffeinateWidget", bundle: .module) }

        static func durationShort(_ minutes: Int) -> String {
            minutes == 0 ? "∞" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
        }

        static func durationLabel(_ minutes: Int) -> String {
            minutes == 0
                ? String(localized: "Duration: Indefinite", table: "CaffeinateWidget", bundle: .module)
                : String(localized: "Duration: \(minutes) min", table: "CaffeinateWidget", bundle: .module)
        }
    }
}
