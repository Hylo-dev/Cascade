//
//  PluginDocumentView.swift
//  CascadeKit
//

import SwiftUI

/// PluginDocumentView shows a store's publication: its root node and the document's glass
/// lights. It reads only the root and the lights, so a change deep in the tree never
/// invalidates it.
struct PluginDocumentView: View {

    let store: PluginNodeStore

    var body: some View {
        if let root = store.root {
            PluginNodeView(model: root, store: store)
                .notchGlassLights(store.glassLights)
        }
    }
}
