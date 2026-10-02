//
//  PluginHealthHistory.swift
//  CascadeKit
//

/// PluginHealthHistory is what a health policy remembers about one plugin: the instants of its
/// recent incidents and how many times it hung since Cascade started.
public struct PluginHealthHistory: Equatable, Sendable {

    public var incidents: [Duration] = []
    public var hangs     = 0

    public init() {}
}
