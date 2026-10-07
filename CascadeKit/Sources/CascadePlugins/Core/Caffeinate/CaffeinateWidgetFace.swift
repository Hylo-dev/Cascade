//
//  CaffeinateWidgetFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateWidgetFace is the widget's document: a face for each size it comes in, and the
/// options page the kernel shows over the grid when the text is pressed.
///
/// The disc is the switch and the text opens the options page, as in Control Center's modules.
/// They are siblings, so starting a session never opens the page and opening it never starts a
/// session. Off, the disc is grey with the outline glyph and the second line is the duration the
/// next session will last, with a chevron saying the text opens more; on, the disc is tinted
/// with the filled glyph and the second line is the time left, drawn by the kernel. State is
/// never colour alone: the glyph's fill and the text change with it.
///
/// The 2x1 tile is 110 by 40 points in the default notch, the 1x1 tile 52 by 40. The large face
/// is held at 100 points because `ViewThatFits` measures a face's ideal width against the tile:
/// a face wider than the tile never fits, and the widget would show only its disc in every size.
enum CaffeinateWidgetFace {

    typealias Node    = CaffeinateStyle.Node
    typealias Palette = CaffeinateStyle.Palette
    typealias Copy    = CaffeinateStyle.Copy

    static let largeWidth = 100.0

    static func publication(
        for state: PluginCaffeinateState,
        now      : Date
    ) throws -> PluginPublication {
        try PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .horizontal) {

                    large(state)

                    small(state)
                }
                .foregroundStyle(.white),
                optionsRoot  : CaffeinateOptionsFace.page(state, now: now),
                optionsAction: CaffeinateStyle.Action.options
            )
        )
    }

    // MARK: - Faces

    /// large is the 2x1 face: the disc, then the title and the second line, which open the page.
    private static func large(_ state: PluginCaffeinateState) -> PluginNode {
        HStack(spacing: 6) {

            powerSwitch(
                state,
                id      : Node.powerLarge,
                diameter: 28
            )

            Button(action: CaffeinateStyle.Action.options) {

                VStack(alignment: .leading, spacing: 1) {

                    Text(Copy.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    caption(state)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    /// small is the 1x1 face: the disc alone, still the switch.
    private static func small(_ state: PluginCaffeinateState) -> PluginNode {
        powerSwitch(
            state,
            id      : Node.powerSmall,
            diameter: 30
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// caption is the second line: a refusal, the time left, the elapsed time of an indefinite
    /// session, or the next session's length. Each time node carries its own font and colour,
    /// because the kernel reads them from the node and never from a parent.
    private static func caption(_ state: PluginCaffeinateState) -> PluginNode {
        if state.failure != nil {
            return HStack(spacing: 2) {

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8, weight: .semibold))

                Text(Copy.refused)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(Palette.warning)
        }

        if state.isActive, let endsAt = state.endsAt {
            return Text(countdownTo: endsAt)
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.amber)
        }

        if let countUp = state.countUp {
            return HStack(spacing: 3) {

                Text("∞")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.amber)

                Text(timerInterval: countUp, countsDown: false)
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.amber)
            }
        }

        return HStack(spacing: 2) {

            Text(CaffeinateStyle.Format.duration(state.nextDuration))
                .font(.system(size: 10, weight: .medium))

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(Palette.secondary)
    }

    // MARK: - The disc

    /// disc is the glyph in its circle: tinted with the filled glyph in ink while a session runs,
    /// grey with the outline in white while off. The glyph carries an explicit identity, so the
    /// symbol effect morphs it in place when the state, or the user's pick, changes.
    static func disc(
        _ state  : PluginCaffeinateState,
        id       : String,
        diameter : Double
    ) -> PluginNode {
        ZStack {

            Circle()
                .foregroundStyle(state.isActive ? Palette.amber : Palette.disc)

            Image(systemName: state.symbol)
                .font(.system(size: (diameter * 0.5).rounded(), weight: .semibold))
                .foregroundStyle(state.isActive ? Palette.ink : .white)
                .contentTransition(.symbolEffect)
                .id(id)
        }
        .frame(width: diameter, height: diameter)
    }

    /// powerSwitch is the disc with a transparent switch over it. The disc lives outside the
    /// toggle, because a toggle with one child draws it dimmed while off and its glyph must
    /// keep its identity as the toggle's value flips.
    static func powerSwitch(
        _ state  : PluginCaffeinateState,
        id       : String,
        diameter : Double
    ) -> PluginNode {
        ZStack {

            disc(
                state,
                id      : id + ".glyph",
                diameter: diameter
            )

            Toggle(isOn: state.isActive, action: CaffeinateStyle.Action.power(isActive: state.isActive)) {

                Circle()
                    .opacity(0)
                    .frame(width: diameter, height: diameter)
            }
            .id(id)
            .accessibilityLabel(state.isActive ? Copy.stopLabel : Copy.startLabel)
        }
        .frame(width: diameter, height: diameter)
    }
}
