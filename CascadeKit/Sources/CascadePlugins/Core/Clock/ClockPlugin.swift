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

    /// face is the clock: today's weekday, day and month above the time, as the lock screen sets
    /// them. The kernel draws and keeps both current, so the plugin never runs to turn a minute or
    /// a day. The time is large, rounded and white, with digits that keep their width and roll as
    /// the minute turns; the date sits above it, smaller and dimmed.
    static func face() throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .vStack(alignment: .leading, spacing: 0),
                modifiers: [
                    .padding(.horizontal, length: 12),
                    .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading),
                ],
                children: [
                    PluginNode(
                        .today,
                        modifiers: [
                            .font(PluginFont(size: 12, weight: .semibold, design: .rounded)),
                            .foregroundStyle(.color(PluginColor(red: 1, green: 1, blue: 1, opacity: 0.55))),
                            .lineLimit(1),
                            .minimumScaleFactor(0.8),
                        ]
                    ),
                    PluginNode(
                        .clock,
                        modifiers: [
                            .font(PluginFont(size: 34, weight: .semibold, design: .rounded, monospacedDigit: true)),
                            .foregroundStyle(.color(.white)),
                            .contentTransition(.numericText(countsDown: false)),
                            .lineLimit(1),
                            .minimumScaleFactor(0.5),
                        ]
                    ),
                ]
            )
        )
    }
}
