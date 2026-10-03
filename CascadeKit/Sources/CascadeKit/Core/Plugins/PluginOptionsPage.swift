//
//  PluginOptionsPage.swift
//  CascadeKit
//

import SwiftUI

/// PluginOptionsPage keeps one live publication store in the shared notch container.
/// Revision changes replace controls through the normal table diff, without a timer.
@MainActor
final class PluginOptionsPage: NotchContextualPage {

    let id: String
    let store: PluginNodeStore
    var contentRevision: UInt64 { store.revision }
    var contentHeight: CGFloat { 220 }
    var accessibilityLabel: String { "Widget options" }

    init(id: String, store: PluginNodeStore) {
        self.id = id
        self.store = store
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        AnyView(PluginDocumentView(store: store, showsOptions: true))
    }
}
