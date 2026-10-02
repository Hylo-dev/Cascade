//
//  PluginNodeSearch.swift
//  CascadeKit
//

import CascadeContracts

/// PluginNodeSearch walks a document depth first so a test can ask what it says and does.
enum PluginNodeSearch {

    static func texts(in node: PluginNode) -> [String] {
        var found: [String] = []
        if case .text(let text) = node.kind { found.append(text) }
        for child in node.children + node.layers { found += texts(in: child) }
        return found
    }

    static func actions(in node: PluginNode) -> [String] {
        var found: [String] = []
        if case .button(let action) = node.kind { found.append(action) }
        for child in node.children + node.layers { found += actions(in: child) }
        return found
    }

    static func kinds(in node: PluginNode) -> [PluginNodeKind] {
        [node.kind] + (node.children + node.layers).flatMap { kinds(in: $0) }
    }
}
