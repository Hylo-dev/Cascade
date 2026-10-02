//
//  PluginAlignment.swift
//  CascadeKit
//

/// PluginAlignment mirrors SwiftUI's two-axis `Alignment`, for depth stacks, frames and layers.
public enum PluginAlignment: String, Codable, Hashable, Sendable {

    case center
    case top
    case bottom
    case leading
    case trailing
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}
