//
//  PluginDocumentView.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

/// PluginDocumentView shows a store's publication: its root node and the document's glass
/// lights. It reads only the root and the lights, so a change deep in the tree never
/// invalidates it.
struct PluginDocumentView: View {

    let store        : PluginNodeStore
    var optionsOrigin: AddonOptionsOrigin? = nil
    var showsOptions = false

    var body: some View {
        if let root = showsOptions ? store.optionsRoot : store.root {
            PluginNodeView(
                model        : root,
                store        : store,
                optionsOrigin: optionsOrigin
            )
                .notchGlassLights(store.glassLights)
        }
    }
}
