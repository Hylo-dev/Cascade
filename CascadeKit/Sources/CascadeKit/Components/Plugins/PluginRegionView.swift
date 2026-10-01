//
//  PluginRegionView.swift
//  CascadeKit
//

import SwiftUI

/// PluginRegionView draws one region of a notice: the child of the document's `regions` root at
/// `index`, or nothing while the store has no such region.
struct PluginRegionView: View {

    let store: PluginNodeStore
    let index: Int

    var body: some View {
        if let root = store.root, root.children.indices.contains(index), let region = store.model(root.children[index]) {
            PluginNodeView(model: region, store: store)
        }
    }
}
