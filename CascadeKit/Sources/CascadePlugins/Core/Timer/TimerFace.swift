//
//  TimerFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// TimerFace is the timer widget's document, a face for each size, largest first, the kernel
/// showing the first that fits. Every face shows the time and a row of buttons in fixed slots;
/// the 2x2 and 2x1 faces add the bar. Idle, the time is the length set so far; running, it is
/// the kernel's countdown and bar, which tick without the plugin; paused, it is what was left on
/// a bar that stands still. An idle bar is an empty track, so starting the timer fills it rather
/// than moving the face.
///
/// A press changes the face within milliseconds, before a second press can come, so every
/// control keeps its slot across the presses that change it: start becomes pause and pause
/// resume in the last slot, +1 and +5 stay put as the length grows, and an empty space holds a
/// slot with nothing to offer. Reset never takes the slot of start, pause or +1. The 2x2 face has
/// a slot of its own for it, so a length set by mistake can be cleared while idle; the 2x1 face
/// shows it in the slot +5 leaves while paused, and the 1x1 face, which has room for only two
/// buttons, in the one +1 leaves, so a second press there only adds to the idle timer.
///
/// Under a 38-point notch a 2x2 tile is 110 by 68 points, a 2x1 tile 110 by 31 and a 1x1 tile 52
/// by 31, and every button is 20 points. The 2x2 face is 66 points tall: a 22-point time, the bar
/// and four slots. The 2x1 face is 108 points wide: three slots beside a 13-point time, over the
/// bar. The 1x1 face is a 9-point time over two slots, 31 points, the most a 1x1 tile holds with
/// buttons of 20 points. In the two smaller faces the time has a fixed width, what the slots
/// leave of the row, and shrinks into it, so an hour still fits. The fixed height and width are
/// also what choose the face: ViewThatFits measures a face with the tile's other side given.
enum TimerFace {

    static let largeHeight = 66.0
    static let mediumWidth = 108.0
    static let smallWidth  = 48.0

    private static let largePadding     = 10.0
    private static let largeSpacing     = 5.0
    private static let mediumPadding    = 4.0
    private static let mediumSpacing    = 3.0
    private static let mediumGap        = 4.0
    private static let slotSpacing      = 3.0
    private static let smallSlotSpacing = 4.0

    static func publication(for state: TimerState) throws -> PluginPublication {
        try PluginPublication(
            feature : TimerPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .vertical) {

                    large(state)

                    ViewThatFits(in: .horizontal) {

                        medium(state)

                        small(state)
                    }
                }
            )
        )
    }

    /// large is the 2x2 face: the time above the bar and four slots, +1, +5, reset and start.
    private static func large(_ state: TimerState) -> PluginNode {
        VStack(alignment: .leading, spacing: largeSpacing) {

            time(state, size: 22)

            bar(state)

            controlRow(largeSlots(for: state), spacing: slotSpacing)
        }
        .padding(.horizontal, largePadding)
        .frame(
            height   : largeHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// medium is the 2x1 face: the time beside three slots, +1, +5 or reset, and start, over the
    /// bar.
    private static func medium(_ state: TimerState) -> PluginNode {
        let slots     = mediumSlots(for: state)
        let timeWidth = mediumWidth - 2 * mediumPadding - mediumGap - controlRowWidth(slots.count, spacing: slotSpacing)

        return VStack(alignment: .leading, spacing: mediumSpacing) {

            HStack(spacing: mediumGap) {

                time(state, size: 13)
                    .frame(width: timeWidth, alignment: .leading)

                controlRow(slots, spacing: slotSpacing)
            }

            bar(state)
        }
        .padding(.horizontal, mediumPadding)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the time above two slots, +1 or reset, and start.
    private static func small(_ state: TimerState) -> PluginNode {
        VStack(spacing: 0) {

            time(state, size: 9)
                .frame(width: smallWidth)

            controlRow(smallSlots(for: state), spacing: smallSlotSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func largeSlots(for state: TimerState) -> [WidgetControl?] {
        switch state {
            case .idle(let duration) where duration > 0:
                [.addOneMinute, .addFiveMinutes, .reset, .start]

            case .idle:
                [.addOneMinute, .addFiveMinutes, nil, nil]

            case .running:
                [.addOneMinute, nil, nil, .pause]

            case .paused:
                [nil, nil, .reset, .resume]
        }
    }

    private static func mediumSlots(for state: TimerState) -> [WidgetControl?] {
        switch state {
            case .idle(let duration) where duration > 0:
                [.addOneMinute, .addFiveMinutes, .start]

            case .idle:
                [.addOneMinute, .addFiveMinutes, nil]

            case .running:
                [.addOneMinute, nil, .pause]

            case .paused:
                [nil, .reset, .resume]
        }
    }

    private static func smallSlots(for state: TimerState) -> [WidgetControl?] {
        switch state {
            case .idle(let duration) where duration > 0:
                [.addOneMinute, .start]

            case .idle:
                [.addOneMinute, nil]

            case .running:
                [.addOneMinute, .pause]

            case .paused:
                [.reset, .resume]
        }
    }

    /// time is the length set while idle, the kernel's countdown while running, and what was
    /// left while paused, rounded up as a countdown shows it, in white rounded digits that keep
    /// their width.
    private static func time(
        _ state: TimerState,
        size   : Double
    ) -> PluginNode {
        let time = switch state {
            case .idle(let duration):
                Text(durationText(duration))

            case .running(let end, let duration):
                Text(timerInterval: end.addingTimeInterval(-duration)...end, countsDown: true)

            case .paused(let remaining, _):
                Text(durationText(remaining.rounded(.up)))
        }

        return time
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// bar fills over the whole run: the kernel's moving bar while running, a still one at what
    /// has gone while paused, an empty one while idle. What has gone is never below nothing,
    /// which a pause in the instant of a start could otherwise make by a rounding error.
    private static func bar(_ state: TimerState) -> PluginNode {
        let bar = switch state {
            case .idle:
                ProgressView(value: 0)

            case .running(let end, let duration):
                ProgressView(timerInterval: end.addingTimeInterval(-duration)...end)

            case .paused(let remaining, let duration):
                ProgressView(value: max(0, duration - remaining), total: duration)
        }

        return bar
            .foregroundStyle(.white)
    }
}
