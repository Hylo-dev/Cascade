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

    /// nodes lists a tree's nodes, layers included, so a test can find one by what it carries.
    static func nodes(in node: PluginNode) -> [PluginNode] {
        [node] + (node.children + node.layers).flatMap { nodes(in: $0) }
    }

    static func kinds(in node: PluginNode) -> [PluginNodeKind] {
        nodes(in: node).map(\.kind)
    }

    /// controlRow is a face's row of buttons, the first horizontal stack whose children are all
    /// buttons or the spacers that hold an empty slot, with the child indices that lead to it.
    static func controlRow(
        in node: PluginNode,
        path   : [Int] = []
    ) -> (path: [Int], row: PluginNode)? {
        if case .hStack = node.kind, !node.children.isEmpty, node.children.allSatisfy(isSlot) {
            return (path, node)
        }

        for (index, child) in node.children.enumerated() {
            if let found = controlRow(in: child, path: path + [index]) { return found }
        }

        return nil
    }

    /// slots lists a row's slots by the action each button sends, nil for an empty slot.
    static func slots(of row: PluginNode) -> [String?] {
        row.children.map { slot in
            if case .button(let action) = slot.kind { return action }

            return nil
        }
    }

    /// accessibilityLabel is the label a node gives VoiceOver, if it gives one.
    static func accessibilityLabel(of node: PluginNode) -> String? {
        for modifier in node.modifiers {
            if case .accessibilityLabel(let label) = modifier { return label }
        }

        return nil
    }

    private static func isSlot(_ node: PluginNode) -> Bool {
        switch node.kind {
            case .button, .spacer:
                true

            default:
                false
        }
    }
}
