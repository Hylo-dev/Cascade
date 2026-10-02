//
//  TimerFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// TimerFace is the timer widget's document, a face for each size, largest first, the kernel
/// showing the first that fits. Every face shows the time and the buttons the state offers; the
/// 2x2 and 2x1 faces add the bar. Idle, the time is the length set so far beside the two
/// additions, and start once there is something to start; running, it is the kernel's countdown
/// and bar, which tick without the plugin, with pause and one more minute; paused, it is what
/// was left on a bar that stands still, with resume and reset. An idle bar is an empty track, so
/// starting the timer fills it rather than moving the face.
///
/// Under a 38-point notch a 2x2 tile is 110 by 68 points, a 2x1 tile 110 by 31 and a 1x1 tile 52
/// by 31. The 2x2 face is 66 points tall: a 22-point time, the bar and 22-point buttons. The 2x1
/// face is 100 points wide, 18-point buttons beside the time over the bar, about 26 points tall;
/// the 1x1 face is the time over 15-point buttons, 31 points. In the two smaller faces the time
/// has a fixed width, what the buttons leave of the row, and shrinks into it, so three buttons
/// and an hour-long time still fit. The fixed height and width are also what choose the face:
/// ViewThatFits measures a face with the tile's other side already given.
enum TimerFace {

    static let largeHeight = 66.0
    static let mediumWidth = 100.0
    static let smallWidth  = 48.0

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

    /// large is the 2x2 face: the time above the bar and the buttons.
    private static func large(_ state: TimerState) -> PluginNode {
        VStack(alignment: .leading, spacing: 5) {

            time(state, size: 22)

            bar(state)

            controlRow(controls(for: state), diameter: 22, spacing: 6)
        }
        .padding(.horizontal, 10)
        .frame(
            height   : largeHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// medium is the 2x1 face: the time beside the buttons, over the bar.
    private static func medium(_ state: TimerState) -> PluginNode {
        let controls  = controls(for: state)
        let timeWidth = mediumWidth - 2 * 5 - 4 - controlRowWidth(controls.count, diameter: 18, spacing: 3)

        return VStack(alignment: .leading, spacing: 3) {

            HStack(spacing: 4) {

                time(state, size: 14)
                    .frame(width: timeWidth, alignment: .leading)

                controlRow(controls, diameter: 18, spacing: 3)
            }

            bar(state)
        }
        .padding(.horizontal, 5)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the time above the buttons.
    private static func small(_ state: TimerState) -> PluginNode {
        VStack(spacing: 1) {

            time(state, size: 12)
                .frame(width: smallWidth)

            controlRow(controls(for: state), diameter: 15, spacing: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// controls are the buttons a state offers, the same on every face.
    private static func controls(for state: TimerState) -> [WidgetControl] {
        switch state {
            case .idle(let duration):
                duration > 0 ? [.addOneMinute, .addFiveMinutes, .start] : [.addOneMinute, .addFiveMinutes]

            case .running:
                [.pause, .addOneMinute]

            case .paused:
                [.start, .reset]
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
