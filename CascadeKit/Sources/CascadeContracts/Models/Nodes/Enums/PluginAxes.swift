//
//  PluginAxes.swift
//  CascadeKit
//

/// PluginAxes names the axes a `viewThatFits` measures its alternatives along: a face that comes
/// in tall and short variants is chosen by height, one in wide and narrow ones by width.
public enum PluginAxes: String, Codable, Hashable, Sendable {

    case horizontal
    case vertical
    case both
}
