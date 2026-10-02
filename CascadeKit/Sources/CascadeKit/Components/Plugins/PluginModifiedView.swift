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
                .modifier(effect(at: count - 1))
        } else {
            PluginNodeContent(model: model, store: store)
        }
    }

    /// readsAsOneElement is true for a node with children or layers whose subtree, the node
    /// included, holds no control. Its accessibility label then names it as one element that
    /// stands for the texts and symbols beneath it, where SwiftUI would give the label to each
    /// child and VoiceOver would read it again for each. A subtree with a button, a toggle or a
    /// slider keeps its elements, so every control stays reachable on its own. The walk reads
    /// only the models' children and layers and their fixed `isControl`, so the label is decided
    /// again when the subtree's shape changes, never when one of its texts does.
    static func readsAsOneElement(
        _ model : PluginNodeModel,
        in store: PluginNodeStore
    ) -> Bool {
        guard !model.isControl else { return false }

        var pending = model.children + model.layers
        guard !pending.isEmpty else { return false }

        while let id = pending.popLast() {
            guard let node = store.model(id) else { continue }
            guard !node.isControl else { return false }

            pending += node.children + node.layers
        }

        return true
    }

    /// effect is the modifier at `index` with what the plugin's values leave to the renderer:
    /// the layer an overlay or a background draws, and whether a label names the node as one
    /// element, which only a label asks, so no other modifier walks the subtree.
    private func effect(at index: Int) -> PluginModifierEffect {
        let modifier = model.modifiers[index]

        var readsAsOneElement = false
        if case .accessibilityLabel = modifier {
            readsAsOneElement = Self.readsAsOneElement(model, in: store)
        }

        return PluginModifierEffect(
            modifier         : modifier,
            layer            : layer(at: index),
            store            : store,
            readsAsOneElement: readsAsOneElement
        )
    }

    /// layer is the node that an overlay or background at `index` draws: layers pair with those
    /// modifiers in order, as validation guarantees.
    private func layer(at index: Int) -> PluginNodeModel? {
        guard model.modifiers[index].isLayer else { return nil }

        let position = model.modifiers[..<index].count(where: \.isLayer)
        return position < model.layers.count ? store.model(model.layers[position]) : nil
    }
}
