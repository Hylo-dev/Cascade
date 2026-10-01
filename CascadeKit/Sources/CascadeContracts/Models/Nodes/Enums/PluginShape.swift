//
//  PluginShape.swift
//  CascadeKit
//

/// PluginShape is a basic shape, drawn as a node or used to clip one.
public enum PluginShape: Codable, Hashable, Sendable {

    case circle
    case capsule
    case roundedRectangle(cornerRadius: Double)
}
