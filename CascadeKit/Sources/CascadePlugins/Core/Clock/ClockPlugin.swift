//
//  ClockPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK

/// ClockPlugin is Cascade's clock as a plugin: one widget showing the date and time, which the
/// kernel draws and keeps current. Whatever wakes it, it answers with the same face and asks for no
/// wake, so after its first refresh it never runs again until a restart asks for its content.
struct ClockPlugin: PluginProvider {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        try PluginOutput(publications: [PluginPublication(feature: "time", surface: .widget, document: Self.face())])
    }

    /// face is the clock, in a face for each size it comes in, largest first, the kernel showing
    /// the first that fits: today's weekday, day and month above a large time on the tall 2x2
    /// tile, as the lock screen sets them; a smaller date and time on the short 2x1 tile; the time
    /// alone on the small 1x1 tile. The kernel draws and keeps both current, so the plugin never
    /// runs to turn a minute or a day. The time is rounded and white, with digits that keep their
    /// width and roll as the minute turns; the date is smaller and dimmed. The large face is 56
    /// points tall and the medium one 100 points wide, so the kernel's choice follows the tile
    /// rather than how far the text could shrink.
    static func face() throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .viewThatFits(axes: .vertical),
                children: [
                    stacked(dateSize: 12, timeSize: 34, padding: 12, width: nil, height: 56),
                    PluginNode(
                        .viewThatFits(axes: .horizontal),
                        children: [
                            stacked(dateSize: 10, timeSize: 21, padding: 10, width: 100, height: nil),
                            PluginNode(
                                .zStack(alignment: .center),
                                modifiers: [.frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)],
                                children : [time(size: 15)]
                            ),
                        ]
                    ),
                ]
            )
        )
    }

    /// stacked is the date above the time, leading, at the given sizes, with a fixed width or
    /// height when the face needs one to be chosen for its tile alone.
    private static func stacked(
        dateSize: Double,
        timeSize: Double,
        padding : Double,
        width   : Double?,
        height  : Double?
    ) -> PluginNode {
        PluginNode(
            .vStack(alignment: .leading, spacing: 0),
            modifiers: [
                .padding(.horizontal, length: padding),
                .frame(width: width, height: height, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading),
            ],
            children: [
                PluginNode(
                    .today,
                    modifiers: [
                        .font(PluginFont(size: dateSize, weight: .semibold, design: .rounded)),
                        .foregroundStyle(.color(PluginColor(red: 1, green: 1, blue: 1, opacity: 0.55))),
                        .lineLimit(1),
                        .minimumScaleFactor(0.8),
                    ]
                ),
                time(size: timeSize),
            ]
        )
    }

    /// time is the kernel-drawn time, rolling to the next minute.
    private static func time(size: Double) -> PluginNode {
        PluginNode(
            .clock,
            modifiers: [
                .font(PluginFont(size: size, weight: .semibold, design: .rounded, monospacedDigit: true)),
                .foregroundStyle(.color(.white)),
                .contentTransition(.numericText(countsDown: false)),
                .lineLimit(1),
                .minimumScaleFactor(0.5),
            ]
        )
    }
}
