//
//  PluginForeground.swift
//  CascadeKit
//

/// PluginForeground is a foreground style: a color, a hierarchical level, or a top-to-bottom
/// gradient of two to four colors.
public enum PluginForeground: Codable, Hashable, Sendable {

    case color(PluginColor)
    case hierarchical(PluginHierarchy)
    case gradient([PluginColor])
}
