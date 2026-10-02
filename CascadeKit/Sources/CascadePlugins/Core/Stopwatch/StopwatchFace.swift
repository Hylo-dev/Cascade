//
//  StopwatchFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// StopwatchFace is the stopwatch widget's document, a face for the 2x1 tile and one for the 1x1
/// tile, the wider first. Idle, it shows 0:00; running, the kernel's timer counting up from when
/// the stopwatch would have started had it never paused; paused, what it counted. The kernel
/// keeps the running count current, so the plugin never runs while it counts.
///
/// Both faces have two slots of 20-point buttons, and each control keeps its slot across the
/// presses that change it: start, pause and resume share the second, so the press that resumes
/// a paused stopwatch lands where pause was, and reset has the first, empty until there is
/// something to reset, so it is never where start or pause was.
///
/// The 2x1 face is 108 points wide, a 15-point time beside the slots; the 1x1 face is a 9-point
/// time over them, 31 points tall, which a 1x1 tile under a 38-point notch holds. In both the
/// time has a fixed width, what the slots leave of the row, and shrinks into it, so an hour-long
/// count still fits. The fixed width is also what chooses the face: ViewThatFits measures a face
/// with the tile's height already given.
enum StopwatchFace {

    static let mediumWidth = 108.0
    static let smallWidth  = 48.0

    private static let mediumPadding    = 6.0
    private static let mediumGap        = 6.0
    private static let slotSpacing      = 3.0
    private static let smallSlotSpacing = 4.0

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

    /// medium is the 2x1 face: the time beside the slots.
    private static func medium(_ state: StopwatchState) -> PluginNode {
        let slots     = slots(for: state)
        let timeWidth = mediumWidth - 2 * mediumPadding - mediumGap - controlRowWidth(slots.count, spacing: slotSpacing)

        return HStack(spacing: mediumGap) {

            time(state, size: 15)
                .frame(width: timeWidth, alignment: .leading)

            controlRow(slots, spacing: slotSpacing)
        }
        .padding(.horizontal, mediumPadding)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the time above the slots.
    private static func small(_ state: StopwatchState) -> PluginNode {
        VStack(spacing: 0) {

            time(state, size: 9)
                .frame(width: smallWidth)

            controlRow(slots(for: state), spacing: smallSlotSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// slots are reset and then start, pause or resume, the same on both faces.
    private static func slots(for state: StopwatchState) -> [WidgetControl?] {
        switch state {
            case .idle   : [nil, .start]
            case .running: [nil, .pause]
            case .paused : [.reset, .resume]
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
