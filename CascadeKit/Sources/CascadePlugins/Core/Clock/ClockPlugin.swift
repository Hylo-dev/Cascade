//
//  ClockPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK

/// ClockPlugin is Cascade's clock as a plugin: one widget showing the time, which the kernel
/// draws and keeps current. Whatever wakes it, it answers with the same face and asks for no
/// wake, so after its first refresh it never runs again until a restart asks for its content.
struct ClockPlugin: PluginProvider {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        try PluginOutput(publications: [PluginPublication(feature: "time", surface: .widget, document: Self.face())])
    }

    /// face is today's clock: large rounded digits that keep their width, white, shrinking to
    /// fit the tile.
    static func face() throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .clock,
                modifiers: [
                    .font(PluginFont(size: 18, weight: .semibold, design: .rounded, monospacedDigit: true)),
                    .foregroundStyle(.color(.white)),
                    .minimumScaleFactor(0.5),
                    .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .center),
                ]
            )
        )
    }
}
