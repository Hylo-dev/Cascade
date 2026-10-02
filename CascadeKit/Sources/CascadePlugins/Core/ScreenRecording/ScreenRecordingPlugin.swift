//
//  ScreenRecordingPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// ScreenRecordingPlugin describes the native recording in PluginHost with the same public
/// nodes every plugin uses. It only reacts to capture state; elapsed time is a renderer-owned
/// timer, and Stop is a normal broker-authorized button. The native adapter keeps ownership of
/// the writer and withdraws this activity only after the file has been finalized.
public final class ScreenRecordingPlugin: PluginProvider {

    public static let identifier = "com.cascade.screen-recording"
    public static let feature    = "recording"
    public static let stop       = "recording.stop"

    public init() {}

    public func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        guard case .source(let source) = event, let state = PluginScreenRecordingState(source) else {
            return try PluginOutput()
        }
        return try PluginOutput(publications: [publication(for: state)])
    }

    private func publication(for state: PluginScreenRecordingState) throws -> PluginPublication {
        guard let session = state.session, let startedAt = state.startedAt else {
            return try PluginPublication(feature: Self.feature, surface: .activity, document: nil)
        }

        let red   = PluginForeground.color(PluginColor(red: 1, green: 0.23, blue: 0.19))
        let title = String(localized: "Screen Recording", table: "Plugins", bundle: .module)
        let stop  = String(localized: "Stop Screen Recording", table: "Plugins", bundle: .module)
        let icon  = PluginNode(.symbol(name: "record.circle"), modifiers: [
            .font(PluginFont(size: 20)), .foregroundStyle(red),
            .frame(width: 20, height: 20, maxWidth: nil, maxHeight: nil, alignment: .center),
        ])
        let compactTimer = PluginNode(
            .timer(start: startedAt, end: startedAt.addingTimeInterval(8 * 60 * 60), countsDown: false),
            modifiers: [
                .font(PluginFont(size: 10, monospacedDigit: true)),
                .foregroundStyle(.color(.white)),
                .contentTransition(.numericText(countsDown: false)),
                .frame(width: 36, height: nil, maxWidth: nil, maxHeight: nil, alignment: .center),
            ]
        )
        let frame: (Double) -> PluginModifier = { size in
            .frame(width: size, height: size, maxWidth: nil, maxHeight: nil, alignment: .center)
        }
        let stopFace = PluginNode(
            .zStack(alignment: .center),
            modifiers: [frame(44), .opacity(state.isStopping ? 0.5 : 1)],
            children : [
                PluginNode(.shape(.circle), modifiers: [.foregroundStyle(.color(.white)), frame(44)]),
                PluginNode(.shape(.circle), modifiers: [.foregroundStyle(.color(.black)), frame(40)]),
                PluginNode(.shape(.roundedRectangle(cornerRadius: 3)), modifiers: [.foregroundStyle(red), frame(18)]),
            ]
        )
        let control = state.isStopping ? stopFace : PluginNode(
            .button(action: Self.stop),
            id       : "stop." + session.uuidString,
            modifiers: [.accessibilityLabel(stop)],
            children : [stopFace]
        )
        let expanded = PluginNode(
            .hStack(alignment: .center, spacing: 24),
            modifiers: [.padding(.horizontal, length: 8)],
            children : [
                PluginNode(
                    .vStack(alignment: .leading, spacing: 3),
                    modifiers: [.font(PluginFont(size: 16))],
                    children : [
                        PluginNode(
                            .hStack(alignment: .center, spacing: 6),
                            modifiers: [.foregroundStyle(red)],
                            children : [
                                PluginNode(.shape(.circle), modifiers: [frame(10)]),
                                PluginNode(
                                    .timer(start: startedAt, end: startedAt.addingTimeInterval(8 * 60 * 60), countsDown: false),
                                    modifiers: [
                                        .font(PluginFont(size: 16, monospacedDigit: true)),
                                        .foregroundStyle(red),
                                        .contentTransition(.numericText(countsDown: false)),
                                    ]
                                ),
                            ]
                        ),
                        PluginNode(.text(title), modifiers: [.foregroundStyle(.color(.white)), .lineLimit(1)]),
                    ]
                ),
                PluginNode(.spacer(minLength: 0)),
                control,
            ]
        )
        return try PluginPublication(
            feature : Self.feature,
            surface : .activity,
            document: PluginDocument(root: PluginNode(
                .regions,
                modifiers: [.accessibilityLabel(title)],
                children : [icon, compactTimer, icon, expanded]
            ))
        )
    }
}
