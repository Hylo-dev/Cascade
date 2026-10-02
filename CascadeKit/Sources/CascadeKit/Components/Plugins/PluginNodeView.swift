//
//  PluginNodeView.swift
//  CascadeKit
//

import SwiftUI

/// PluginNodeView renders one node: its modifiers, applied in the plugin's order around its
/// content. It is nominal and recursive, children and layers being `PluginNodeView`s again, so
/// SwiftUI keeps every node's identity and no view is type-erased.
struct PluginNodeView: View {

    let model: PluginNodeModel
    let store: PluginNodeStore

    var body: some View {
        PluginModifiedView(model: model, store: store, count: model.modifiers.count)
    }
}
