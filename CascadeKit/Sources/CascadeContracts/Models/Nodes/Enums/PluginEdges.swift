//
//  PluginEdges.swift
//  CascadeKit
//

/// PluginEdges names the edges a padding or a move transition applies to.
public enum PluginEdges: String, Codable, Hashable, Sendable {

    case all
    case horizontal
    case vertical
    case top
    case bottom
    case leading
    case trailing
}
