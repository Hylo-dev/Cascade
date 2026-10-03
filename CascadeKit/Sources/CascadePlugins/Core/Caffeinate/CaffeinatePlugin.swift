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

    /// options groups infrequent controls inside the shared notch footprint.
    /// Only the selected duration and enabled display switch use the cup's amber.
    /// A fixed session end time and passive busy state need no scheduled wakeups.
    private func options(state: PluginCaffeinateState) -> PluginNode {
        let suffix = "." + state.token.uuidString
        let amber = PluginColor(red: 1, green: 0.77, blue: 0.33)
        let muted = PluginColor(red: 0.72, green: 0.72, blue: 0.75)
        let dark = PluginColor(red: 0.15, green: 0.13, blue: 0.10)
        let status = state.error ?? (state.isBusy
            ? String(localized: "Updating…", table: "Plugins", bundle: .module)
            : state.isActive
                ? String(localized: "On", table: "Plugins", bundle: .module)
                : String(localized: "Off", table: "Plugins", bundle: .module))
        var statusNodes = [PluginNode(.text(status))]
        if state.isActive, !state.isBusy, state.error == nil, let until = state.until {
            statusNodes.append(PluginNode(.date(until, style: .time)))
        }
        let durationNodes = [0, 15, 30, 60, 120, 240, 480].map { minutes in
            let label = minutes == 0 ? "∞" : minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h"
            let selected = minutes == state.minutes
            let text = PluginNode(
                .text(label),
                modifiers: [
                    .font(PluginFont(size: 11, weight: .semibold)),
                    .foregroundStyle(.color(selected ? dark : .white)),
                    .lineLimit(1),
                    .frame(width: nil, height: 26, maxWidth: .infinity, maxHeight: nil, alignment: .center),
                    .background(alignment: .center),
                ],
                layers: [PluginNode(
                    .shape(.roundedRectangle(cornerRadius: 7)),
                    modifiers: [.foregroundStyle(.color(selected ? amber : PluginColor(red: 1, green: 1, blue: 1, opacity: 0.09)))]
                )]
            )
            return state.isBusy ? text : PluginNode(
                .button(action: "caffeinate.duration.\(minutes)"),
                id: "duration.\(minutes)" + suffix,
                modifiers: [.accessibilityLabel(minutes == 0 ? "Duration: Indefinite" : "Duration: \(minutes) min")],
                children: [text]
            )
        }
        var rows = [
            PluginNode(
                .hStack(alignment: .center, spacing: 10),
                children: [
                    PluginNode(.symbol(name: state.isActive ? "cup.and.saucer.fill" : "cup.and.saucer"), modifiers: [
                        .font(PluginFont(size: 24, weight: .medium)),
                        .foregroundStyle(.color(state.isActive ? amber : .white)),
                        .frame(width: 34, height: 34, maxWidth: nil, maxHeight: nil, alignment: .center),
                    ]),
                    PluginNode(.vStack(alignment: .leading, spacing: 2), children: [
                        PluginNode(.text(String(localized: "Caffeinate", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 16, weight: .semibold))]),
                        PluginNode(.hStack(alignment: .center, spacing: 5), modifiers: [
                            .font(PluginFont(size: 11)),
                            .foregroundStyle(.color(muted)),
                            .lineLimit(1),
                            .accessibilityLabel(status),
                        ], children: statusNodes),
                    ]),
                    PluginNode(.spacer(minLength: nil)),
                ]
            ),
            PluginNode(.vStack(alignment: .leading, spacing: 5), children: [
                PluginNode(.text(String(localized: "Duration", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 11, weight: .medium)), .foregroundStyle(.color(muted))]),
                PluginNode(.hStack(alignment: .center, spacing: 4), children: durationNodes),
            ]),
        ]
        func displayLabel(isOn: Bool) -> PluginNode {
            PluginNode(
                .hStack(alignment: .center, spacing: 8),
                modifiers: [.frame(width: nil, height: 28, maxWidth: .infinity, maxHeight: nil, alignment: .leading)],
                children: [
                    PluginNode(.symbol(name: "display"), modifiers: [.font(PluginFont(size: 15)), .foregroundStyle(.color(muted))]),
                    PluginNode(.text(String(localized: "Keep display awake", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 12, weight: .medium)), .lineLimit(1), .minimumScaleFactor(0.8)]),
                    PluginNode(.spacer(minLength: nil)),
                    PluginNode(
                        .shape(.capsule),
                        modifiers: [
                            .foregroundStyle(.color(isOn ? amber : PluginColor(red: 1, green: 1, blue: 1, opacity: 0.22))),
                            .frame(width: 30, height: 18, maxWidth: nil, maxHeight: nil, alignment: .center),
                            .overlay(alignment: isOn ? .trailing : .leading),
                        ],
                        layers: [PluginNode(.shape(.circle), modifiers: [
                            .foregroundStyle(.color(isOn ? dark : .white)),
                            .frame(width: 14, height: 14, maxWidth: nil, maxHeight: nil, alignment: .center),
                            .padding(.horizontal, length: 2),
                        ])]
                    ),
                ]
            )
        }
        rows.append(state.isBusy ? displayLabel(isOn: state.keepDisplayAwake) : PluginNode(
            .toggle(isOn: state.keepDisplayAwake, action: "caffeinate.display"),
            id: "display" + suffix,
            modifiers: [.accessibilityLabel("Keep display awake")],
            children: [displayLabel(isOn: false), displayLabel(isOn: true)]
        ))
        let stop = PluginNode(
            .hStack(alignment: .center, spacing: 6),
            modifiers: [
                .font(PluginFont(size: 11, weight: .medium)),
                .frame(width: 104, height: 26, maxWidth: nil, maxHeight: nil, alignment: .center),
                .background(alignment: .center),
                .opacity(state.isActive ? 1 : 0.45),
            ],
            children: [PluginNode(.symbol(name: "stop.fill"), modifiers: [.font(PluginFont(size: 8))]), PluginNode(.text(String(localized: "Stop", table: "Plugins", bundle: .module)))],
            layers: [PluginNode(.shape(.roundedRectangle(cornerRadius: 7)), modifiers: [.foregroundStyle(.color(PluginColor(red: 1, green: 1, blue: 1, opacity: 0.09)))])]
        )
        let credits = PluginNode(.hStack(alignment: .center, spacing: 5), modifiers: [.font(PluginFont(size: 11)), .foregroundStyle(.color(muted)), .frame(width: nil, height: 26, maxWidth: nil, maxHeight: nil, alignment: .center)], children: [
            PluginNode(.symbol(name: "info.circle")),
            PluginNode(.text(String(localized: "Credits", table: "Plugins", bundle: .module)), modifiers: [.lineLimit(1)]),
            PluginNode(.symbol(name: state.showsCredits ? "chevron.up" : "chevron.down"), modifiers: [.font(PluginFont(size: 8))]),
        ])
        rows.append(PluginNode(.hStack(alignment: .center, spacing: 12), children: [
            state.isActive && !state.isBusy ? PluginNode(.button(action: "caffeinate.stop"), id: "stop" + suffix, modifiers: [.accessibilityLabel("Stop Caffeinate")], children: [stop]) : stop,
            PluginNode(.spacer(minLength: nil)),
            state.isBusy ? credits : PluginNode(.button(action: "caffeinate.credits"), id: "credits" + suffix, modifiers: [.accessibilityLabel("Caffeinate credits")], children: [credits]),
        ]))
        if state.showsCredits {
            rows.append(PluginNode(.text(String(localized: "Functional references: Vorssaint (2026, GPL-3.0-or-later) and Amphetamine by William Gustafson. Independently authored with Apple IOKit and SF Symbols; no third-party code or assets.", table: "Plugins", bundle: .module)), modifiers: [.font(PluginFont(size: 10)), .lineLimit(4), .foregroundStyle(.color(muted))]))
        }
        return PluginNode(
            .vStack(alignment: .leading, spacing: 10),
            id: "caffeinate.options.page",
            modifiers: [.foregroundStyle(.color(.white)), .padding(.horizontal, length: 8), .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)],
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
