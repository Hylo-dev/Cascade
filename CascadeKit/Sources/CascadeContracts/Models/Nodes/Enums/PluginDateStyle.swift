//
//  PluginDateStyle.swift
//  CascadeKit
//

/// PluginDateStyle mirrors the `Text.DateStyle` cases the kernel draws without waking the plugin.
public enum PluginDateStyle: String, Codable, Hashable, Sendable {

    case time
    case date
    case relative
}
