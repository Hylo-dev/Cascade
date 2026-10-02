//
//  PluginStatusSection.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine
import CascadePlugins
import SwiftUI

/// PluginStatusSection shows each first-party plugin's state and PluginHost's, as the plugin
/// engine spec asks, with the way back from whatever stopped them: Re-enable for a plugin stopped
/// after it froze or kept failing, Restart for a host given up on after repeated crashes. A
/// plugin switched off in the alerts above simply reads Off.
struct PluginStatusSection: View {

    /// Row is one plugin, named in the user's language.
    private struct Row: Identifiable {

        let id   : PluginID
        let name : String
        let state: PluginState
    }

    let services: CascadeServices

    var body: some View {
        Section {
            if let status = services.pluginStatus {
                hostRow(status.host)

                ForEach(rows(of: status)) { row in
                    pluginRow(row)
                }
            } else {
                Text("Starting plugins…")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Plugins")
        } footer: {
            Text("Widgets and alerts run as plugins in a separate process, so a fault in one never takes the notch down.")
        }
    }

    private func rows(of status: PluginEngineStatus) -> [Row] {
        status.plugins
            .map { Row(id: $0.key, name: FirstPartyPlugins.name(of: $0.key), state: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func pluginRow(_ row: Row) -> some View {
        HStack(spacing: 12) {

            Text(row.name)

            Spacer(minLength: 12)

            Text(label(of: row.state))
                .foregroundStyle(row.state == .disabledAfterHang || row.state == .quarantined ? .orange : .secondary)

            if row.state == .disabledAfterHang || row.state == .quarantined {
                Button(String(localized: "Re-enable")) { services.reenablePlugin(row.id) }
                    .accessibilityLabel(String(localized: "Re-enable \(row.name)"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func hostRow(_ host: PluginHostStatus) -> some View {
        HStack(spacing: 12) {

            Text("Plugin host")

            Spacer(minLength: 12)

            Text(label(of: host))
                .foregroundStyle(host == .stopped ? .orange : .secondary)

            if host == .stopped {
                Button(String(localized: "Restart")) { services.restartPluginHost() }
                    .accessibilityLabel(String(localized: "Restart the plugin host"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func label(of state: PluginState) -> String {
        switch state {
            case .active           : String(localized: "On")
            case .switchedOff      : String(localized: "Off")
            case .disabledAfterHang: String(localized: "Stopped after freezing")
            case .quarantined      : String(localized: "Stopped after repeated errors")
        }
    }

    private func label(of host: PluginHostStatus) -> String {
        switch host {
            case .connecting: String(localized: "Starting")
            case .running   : String(localized: "Running")
            case .stopped   : String(localized: "Stopped after repeated crashes")
        }
    }
}
