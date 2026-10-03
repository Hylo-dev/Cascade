//
//  CaffeinatePlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinatePlugin offers a text face up to four grid columns wide and a cup-only fallback.
/// Its manifest uses two plugin columns, which the shared adapter maps to four grid cells.
/// Its glyph lives outside the revision-bound button, so native symbol animation survives
/// busy and accepted-state publications. A fixed end time needs no countdown wakeups.
public struct CaffeinatePlugin: PluginProvider {

    public static let identifier = "com.cascade.caffeinate"
    public static let feature    = "awake"

    public init() {}

    public func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        guard case .source(let event) = event, let state = PluginCaffeinateState(event) else {
            return try PluginOutput()
        }

        let status = state.error != nil
            ? String(localized: "Error", table: "Plugins", bundle: .module)
            : state.isActive
                ? String(localized: "On", table: "Plugins", bundle: .module)
                : String(localized: "Off", table: "Plugins", bundle: .module)
        var statusNodes = [PluginNode(.text(status))]
        if state.isActive, let until = state.until {
            statusNodes.append(PluginNode(.date(until, style: .time)))
        }

        let details = PluginNode(
            .vStack(alignment: .leading, spacing: 1),
            modifiers: [.frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: nil, alignment: .leading)],
            children: [
                PluginNode(
                    .text(String(localized: "Caffeinate", table: "Plugins", bundle: .module)),
                    modifiers: [
                        .font(PluginFont(size: 12, weight: .semibold)),
                        .lineLimit(1),
                        .minimumScaleFactor(0.8),
                    ]
                ),
                PluginNode(
                    .hStack(alignment: .center, spacing: 4),
                    modifiers: [
                        .font(PluginFont(size: 10)),
                        .foregroundStyle(.color(PluginColor(red: 0.82, green: 0.82, blue: 0.84))),
                        .lineLimit(1),
                    ],
                    children: statusNodes
                ),
            ]
        )
        let full = PluginNode(
            .hStack(alignment: .center, spacing: 8),
            modifiers: [
                .frame(width: 104, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading),
            ],
            children: [
                cup(state: state, compact: false, status: status),
                state.isBusy ? details : PluginNode(
                    .button(action: "caffeinate.options"),
                    id: "options." + state.token.uuidString,
                    modifiers: [.accessibilityLabel("Caffeinate options")],
                    children: [PluginNode(
                        .hStack(alignment: .center, spacing: 4),
                        children: [details, PluginNode(.symbol(name: "chevron.right"), modifiers: [.font(PluginFont(size: 9))])]
                    )]
                ),
            ]
        )
        let root = PluginNode(
            .viewThatFits(axes: .both),
            modifiers: [
                .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .center),
                .foregroundStyle(.color(.white)),
            ],
            children: [full, cup(state: state, compact: true, status: status)]
        )
        return try PluginOutput(publications: [PluginPublication(
            feature : Self.feature,
            surface : .widget,
            document: PluginDocument(
                root         : root,
                optionsRoot  : options(state: state),
                optionsAction: state.isBusy ? nil : "caffeinate.options"
            )
        )])
    }

    /// options uses the ordinary control vocabulary and native freshness token.
    /// Busy and stopped states publish passive labels instead of actionable controls.
    private func options(state: PluginCaffeinateState) -> PluginNode {
        let suffix = "." + state.token.uuidString
        let durationNodes = [0, 15, 30, 60, 120, 240, 480].map { minutes in
            let label = minutes == 0
                ? String(localized: "Indefinite", table: "Plugins", bundle: .module)
                : "\(minutes) min"
            let text = PluginNode(.text(label), modifiers: [
                .font(PluginFont(size: 11, weight: minutes == state.minutes ? .bold : .regular)),
                .foregroundStyle(.color(minutes == state.minutes ? PluginColor(red: 1, green: 0.77, blue: 0.33) : .white)),
            ])
            return state.isBusy ? text : PluginNode(
                .button(action: "caffeinate.duration.\(minutes)"),
                id: "duration.\(minutes)" + suffix,
                modifiers: [.accessibilityLabel(minutes == 0 ? "Duration: Indefinite" : "Duration: \(minutes) min")],
                children: [text]
            )
        }
        var rows = [
            PluginNode(.text(String(localized: "Caffeinate", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 15, weight: .semibold))]),
            PluginNode(.text(String(localized: "Duration", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 11)), .foregroundStyle(.hierarchical(.secondary))]),
            PluginNode(.hStack(alignment: .center, spacing: 12), children: durationNodes),
        ]
        let displayLabel = PluginNode(.text(String(localized: "Keep display awake", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 12))])
        rows.append(state.isBusy ? displayLabel : PluginNode(
            .toggle(isOn: state.keepDisplayAwake, action: "caffeinate.display"),
            id: "display" + suffix,
            modifiers: [.accessibilityLabel("Keep display awake")],
            children: [displayLabel]
        ))
        let stop = PluginNode(.text(String(localized: "Stop", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 12)), .opacity(state.isActive ? 1 : 0.4)])
        let credits = PluginNode(.text(String(localized: "Credits", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 12))])
        rows.append(PluginNode(.hStack(alignment: .center, spacing: 18), children: [
            state.isActive && !state.isBusy ? PluginNode(.button(action: "caffeinate.stop"), id: "stop" + suffix, modifiers: [.accessibilityLabel("Stop Caffeinate")], children: [stop]) : stop,
            state.isBusy ? credits : PluginNode(.button(action: "caffeinate.credits"), id: "credits" + suffix, modifiers: [.accessibilityLabel("Caffeinate credits")], children: [credits]),
        ]))
        if state.showsCredits {
            rows.append(PluginNode(.text(String(localized: "Functional references: Vorssaint (2026, GPL-3.0-or-later) and Amphetamine by William Gustafson. Independently authored with Apple IOKit and SF Symbols; no third-party code or assets.", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 10)), .lineLimit(3), .foregroundStyle(.hierarchical(.secondary))]))
        }
        if let error = state.error {
            rows.append(PluginNode(.text(error), modifiers: [.font(PluginFont(size: 10)), .lineLimit(2)]))
        }
        return PluginNode(
            .vStack(alignment: .leading, spacing: 10),
            id: "caffeinate.options.page",
            modifiers: [.foregroundStyle(.color(.white)), .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: nil, alignment: .leading)],
            children: rows
        )
    }

    /// cup keeps the animated glyph's identity independent of an action's freshness token.
    /// A transparent, separate hit area disappears while busy without replacing the glyph.
    private func cup(
        state  : PluginCaffeinateState,
        compact: Bool,
        status : String
    ) -> PluginNode {
        let diameter = compact ? 32.0 : 36.0
        let prefix   = compact ? "compact" : "full"
        let amber    = PluginColor(red: 1, green: 0.77, blue: 0.33)
        let label    = String(localized: "Toggle Caffeinate", table: "Plugins", bundle: .module)
        var children = [
            PluginNode(
                .shape(.circle),
                modifiers: [
                    .foregroundStyle(.color(state.isActive ? amber : .white)),
                    .frame(width: diameter, height: diameter, maxWidth: nil, maxHeight: nil, alignment: .center),
                ]
            ),
            PluginNode(
                .symbol(name: state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"),
                id: prefix + ".cup",
                modifiers: [
                    .font(PluginFont(size: compact ? 18 : 20, weight: .semibold)),
                    .foregroundStyle(.color(PluginColor(red: 0.15, green: 0.13, blue: 0.10))),
                    .contentTransition(.symbolEffect),
                ]
            ),
        ]
        if !state.isBusy {
            children.append(PluginNode(
                .button(action: "caffeinate.toggle"),
                id: (compact ? "toggle.compact." : "toggle.") + state.token.uuidString,
                modifiers: [.accessibilityLabel(label + ": " + status)],
                children: [PluginNode(
                    .shape(.circle),
                    modifiers: [
                        .opacity(0),
                        .frame(width: diameter, height: diameter, maxWidth: nil, maxHeight: nil, alignment: .center),
                    ]
                )]
            ))
        }
        return PluginNode(
            .zStack(alignment: .center),
            id: prefix + ".face",
            modifiers: [.frame(width: diameter, height: diameter, maxWidth: nil, maxHeight: nil, alignment: .center)],
            children: children
        )
    }
}
