//
//  PluginNodeBuilder.swift
//  CascadeKit
//

import CascadeContracts

/// PluginNodeBuilder collects the nodes a block lists, in order, the way SwiftUI's `ViewBuilder`
/// collects views, so a plugin writes its children as nested blocks instead of arrays. An `if`
/// that does not hold adds nothing, an `if`/`else` adds the branch taken, and a `for` adds what
/// every pass lists. It only gathers values: nothing is checked until `PluginDocument.init`, so
/// building content never throws.
@resultBuilder
public enum PluginNodeBuilder {

    public static func buildExpression(_ node: PluginNode) -> [PluginNode] {
        [node]
    }

    public static func buildBlock(_ components: [PluginNode]...) -> [PluginNode] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [PluginNode]?) -> [PluginNode] {
        component ?? []
    }

    public static func buildEither(first component: [PluginNode]) -> [PluginNode] {
        component
    }

    public static func buildEither(second component: [PluginNode]) -> [PluginNode] {
        component
    }

    public static func buildArray(_ components: [[PluginNode]]) -> [PluginNode] {
        components.flatMap { $0 }
    }
}
