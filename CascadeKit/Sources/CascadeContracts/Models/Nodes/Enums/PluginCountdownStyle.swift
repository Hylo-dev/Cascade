//
//  PluginCountdownStyle.swift
//  CascadeKit
//

/// PluginCountdownStyle is how a `countdown` node writes the time left. `compact` is the
/// Dynamic Island's own: whole hours (`2h`), then whole minutes (`24m`), then `m:ss` (`4:59`).
/// `hoursMinutes` is a stepper's value: the time left rounded up to whole minutes, in hours and
/// minutes (`1h 5m`, `45m`, `1m`), so a value that moves by fifteen minutes shows that it moved.
public enum PluginCountdownStyle: String, Codable, Hashable, Sendable {

    case compact
    case hoursMinutes
}
