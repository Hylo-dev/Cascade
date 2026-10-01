//
//  PluginHierarchy.swift
//  CascadeKit
//

/// PluginHierarchy mirrors SwiftUI's hierarchical shape styles, `.secondary` and the rest.
public enum PluginHierarchy: String, Codable, Hashable, Sendable {

    case primary
    case secondary
    case tertiary
    case quaternary
}
