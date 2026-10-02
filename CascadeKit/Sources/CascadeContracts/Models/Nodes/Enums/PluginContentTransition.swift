//
//  PluginContentTransition.swift
//  CascadeKit
//

/// PluginContentTransition mirrors SwiftUI's content transitions: rolling digits for numbers
/// and the symbol effect for a symbol that changes in place.
public enum PluginContentTransition: Codable, Hashable, Sendable {

    case numericText(countsDown: Bool)
    case symbolEffect
}
