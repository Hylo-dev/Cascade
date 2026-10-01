//
//  PluginValue.swift
//  CascadeKit
//

/// PluginValue is one typed parameter of a tier-2 component.
public enum PluginValue: Codable, Hashable, Sendable {

    case string(String)
    case number(Double)
    case bool(Bool)
}
