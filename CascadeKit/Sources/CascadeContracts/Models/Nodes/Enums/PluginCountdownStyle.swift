//
//  PluginCountdownStyle.swift
//  CascadeKit
//

/// PluginCountdownStyle is how a `countdown` node writes the time left. `compact` is the
/// Dynamic Island's own: whole hours (`2h`), then whole minutes (`24m`), then `m:ss` (`4:59`).
public enum PluginCountdownStyle: String, Codable, Hashable, Sendable {

    case compact
}
