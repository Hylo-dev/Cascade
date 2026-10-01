//
//  PluginDimension.swift
//  CascadeKit
//

/// PluginDimension is a frame's maximum: a length in points, or infinity to fill the
/// proposal. Infinity is a case, not a `Double`, because JSON cannot carry an infinite number.
public enum PluginDimension: Codable, Hashable, Sendable {

    case points(Double)
    case infinity
}
