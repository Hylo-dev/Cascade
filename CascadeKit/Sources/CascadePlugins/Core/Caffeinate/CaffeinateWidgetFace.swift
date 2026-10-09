//
//  CaffeinateWidgetFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateWidgetFace is the widget's document: a face for each size it comes in, largest
/// first, and the options page the kernel shows over the grid when the text is pressed.
///
/// The disc is the switch and the text opens the options page, as in Control Center's modules.
/// The 2x2 face stacks them, as that tile is tall: the disc above, the title and the second
/// line below, all of them still inside the opener.
/// They are siblings, so starting a session never opens the page and opening it never starts a
/// session. Off, the disc is grey with the outline glyph and the second line is how the next
/// session will end, with a chevron saying the text opens more: the sign, a length such as
/// "1h 30m", or "until" and the end's clock, which the kernel draws. On, the disc is tinted with
/// the filled glyph and the second line is the time left, drawn by the kernel. State is never
/// colour alone: the glyph's fill and the text change with it.
///
/// The 2x2 tile is 110 by 86 points in the default notch, the 2x1 tile 110 by 40 and the 1x1
/// tile 52 by 40. The tall face is held at 68 points high and the large one at 100 wide because
/// `ViewThatFits` measures a face's ideal size against the tile: a face bigger than the tile
/// never fits, and one that could shrink would pass for a smaller tile's. The tall face is
/// tried on the height alone, so a 2x1 tile, as wide, still falls through to the large face.
/// The 2x1 tile leaves its text about 60 points, which "until 10:45 PM" does not fit at its size:
/// the words scale down to 60 % before the system cuts them.
enum CaffeinateWidgetFace {

    typealias Node    = CaffeinateStyle.Node
    typealias Palette = CaffeinateStyle.Palette
    typealias Copy    = CaffeinateStyle.Copy

    static let tallHeight = 68.0
    static let largeWidth = 100.0

    static func publication(
        for state: PluginCaffeinateState,
        now      : Date,
        calendar : Calendar
    ) throws -> PluginPublication {
        try PluginPublication(
            feature : CaffeinatePlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .vertical) {

                    tall(state, now: now, calendar: calendar)

                    ViewThatFits(in: .horizontal) {

                        large(state, now: now, calendar: calendar)

                        small(state)
                    }
                }
                .foregroundStyle(.white),
                optionsRoot  : CaffeinateOptionsFace.page(
                    state,
                    now     : now,
                    calendar: calendar
                ),
                optionsAction: CaffeinateStyle.Action.options
            )
        )
    }

    // MARK: - Faces

    /// tall is the 2x2 face: the disc on top, the title and the second line below it.
    private static func tall(
        _ state : PluginCaffeinateState,
        now     : Date,
        calendar: Calendar
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: 0) {

            powerSwitch(
                state,
                id      : Node.powerMedium,
                diameter: 32
            )

            Spacer(minLength: 2)

            Button(action: CaffeinateStyle.Action.options) {

                VStack(alignment: .leading, spacing: 1) {

                    Text(Copy.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    caption(state, size: 12, now: now, calendar: calendar)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(Node.opener)
            .accessibilityLabel(Copy.options)
        }
        .padding(.horizontal, 4)
        .frame(
            height   : tallHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    /// large is the 2x1 face: the disc, then the title and the second line, which open the page.
    private static func large(
        _ state : PluginCaffeinateState,
        now     : Date,
        calendar: Calendar
    ) -> PluginNode {
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

                    caption(state, size: 11, now: now, calendar: calendar)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(Node.openerLarge)
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

    /// caption is the second line. A refusal to start says "Error" in the warning colour, a
    /// word that fits the tile at its natural size, and the options page carries the sentence
    /// and the code. A refused extension leaves the session as it was, so the normal line stays
    /// and a small warning symbol sits beside it.
    private static func caption(
        _ state : PluginCaffeinateState,
        size    : Double,
        now     : Date,
        calendar: Calendar
    ) -> PluginNode {
        if state.refusedToStart {
            return HStack(spacing: 2) {

                warningSymbol()

                Text(Copy.error)
                    .font(.system(size: size - 1, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Palette.warning)
        }

        guard state.refusedToExtend else {
            return status(state, size: size, now: now, calendar: calendar)
        }

        return HStack(spacing: 3) {

            status(state, size: size, now: now, calendar: calendar)

            warningSymbol()
                .foregroundStyle(Palette.warning)
        }
    }

    private static func warningSymbol() -> PluginNode {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 8, weight: .semibold))
    }

    /// status is the time left, the elapsed time of an indefinite session, or how the next
    /// session will end. Each time node carries its own font and colour, because the kernel
    /// reads them from the node and never from a parent.
    private static func status(
        _ state : PluginCaffeinateState,
        size    : Double,
        now     : Date,
        calendar: Calendar
    ) -> PluginNode {
        if state.isActive, let endsAt = state.endsAt {
            return Text(countdownTo: endsAt)
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Palette.amber)
        }

        if let countUp = state.countUp {
            return HStack(spacing: 3) {

                Text("∞")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(Palette.amber)

                Text(timerInterval: countUp, countsDown: false)
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.amber)
            }
        }

        let font = PluginFont.system(size: size - 1, weight: .medium)

        if let end = CaffeinateRuler.nextEnd(of: state, now: now, calendar: calendar) {
            return HStack(spacing: 2) {

                Text(Copy.until)
                    .font(font)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(end, style: .time)
                    .font(font)
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                chevron(size: size)
            }
            .foregroundStyle(Palette.secondary)
        }

        return HStack(spacing: 2) {

            Text(CaffeinateStyle.Format.target(state.nextTarget))
                .font(font)

            chevron(size: size)
        }
        .foregroundStyle(Palette.secondary)
    }

    private static func chevron(size: Double) -> PluginNode {
        Image(systemName: "chevron.right")
            .font(.system(size: size - 3, weight: .semibold))
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
