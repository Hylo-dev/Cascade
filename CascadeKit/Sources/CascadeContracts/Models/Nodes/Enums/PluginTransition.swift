//
//  PluginTransition.swift
//  CascadeKit
//

/// PluginTransition mirrors the SwiftUI transitions a node uses when it is inserted or removed.
public enum PluginTransition: Codable, Hashable, Sendable {

    case opacity
    case scale
    case move(PluginEdges)
}
