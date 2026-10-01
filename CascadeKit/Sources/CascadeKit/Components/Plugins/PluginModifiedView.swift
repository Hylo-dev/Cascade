//
//  PluginModifiedView.swift
//  CascadeKit
//

import SwiftUI

/// PluginModifiedView is a node's content with its first `count` modifiers applied, the last of
/// them outermost, as SwiftUI applies a chain written in order. Each level is a nominal view, so
/// a node with any number of modifiers, at most sixteen, needs no type erasure.
struct PluginModifiedView: View {

    let model: PluginNodeModel
    let store: PluginNodeStore
    let count: Int

    var body: some View {
        if count > 0, count <= model.modifiers.count {
            PluginModifiedView(model: model, store: store, count: count - 1)
                .modifier(PluginModifierEffect(modifier: model.modifiers[count - 1], layer: layer(at: count - 1), store: store))
        } else {
            PluginNodeContent(model: model, store: store)
        }
    }

    /// layer is the node that an overlay or background at `index` draws: layers pair with those
    /// modifiers in order, as validation guarantees.
    private func layer(at index: Int) -> PluginNodeModel? {
        guard model.modifiers[index].isLayer else { return nil }

        let position = model.modifiers[..<index].count(where: \.isLayer)
        return position < model.layers.count ? store.model(model.layers[position]) : nil
    }
}
