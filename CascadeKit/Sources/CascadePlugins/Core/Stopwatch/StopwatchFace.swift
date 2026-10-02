//
//  StopwatchFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// StopwatchFace is the stopwatch widget's document, a face for the 2x1 tile and one for the 1x1
/// tile, the wider first. Idle, it shows 0:00 with start; running, the kernel's timer counting up
/// from when the stopwatch would have started had it never paused, with pause; paused, what it
/// counted, with resume and reset. The kernel keeps the running count current, so the plugin
/// never runs while it counts.
///
/// The 2x1 face is 100 points wide, the time beside 18-point buttons; the 1x1 face is the time
/// over 15-point buttons, 31 points tall, which a 1x1 tile under a 38-point notch holds. In both
/// the time has a fixed width, what the buttons leave of the row, and shrinks into it, so an
/// hour-long count still fits. The fixed width is also what chooses the face: ViewThatFits
/// measures a face with the tile's height already given.
enum StopwatchFace {

    static let mediumWidth = 100.0
    static let smallWidth  = 48.0

    static func publication(for state: StopwatchState) throws -> PluginPublication {
        try PluginPublication(
            feature : StopwatchPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .horizontal) {

                    medium(state)

                    small(state)
                }
            )
        )
    }

    /// medium is the 2x1 face: the time beside the buttons.
    private static func medium(_ state: StopwatchState) -> PluginNode {
        let controls  = controls(for: state)
        let timeWidth = mediumWidth - 2 * 6 - 6 - controlRowWidth(controls.count, diameter: 18, spacing: 3)

        return HStack(spacing: 6) {

            time(state, size: 15)
                .frame(width: timeWidth, alignment: .leading)

            controlRow(controls, diameter: 18, spacing: 3)
        }
        .padding(.horizontal, 6)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the time above the buttons.
    private static func small(_ state: StopwatchState) -> PluginNode {
        VStack(spacing: 1) {

            time(state, size: 12)
                .frame(width: smallWidth)

            controlRow(controls(for: state), diameter: 15, spacing: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func controls(for state: StopwatchState) -> [WidgetControl] {
        switch state {
            case .idle   : [.start]
            case .running: [.pause]
            case .paused : [.start, .reset]
        }
    }

    /// time is 0:00 while idle, the kernel's count while running, and what was counted while
    /// paused, in white rounded digits that keep their width.
    private static func time(
        _ state: StopwatchState,
        size   : Double
    ) -> PluginNode {
        let time = switch state {
            case .idle:
                Text(durationText(0))

            case .running(let since, let before):
                Text(timerInterval: since.addingTimeInterval(-before)...Date.distantFuture, countsDown: false)

            case .paused(let elapsed):
                Text(durationText(elapsed))
        }

        return time
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
