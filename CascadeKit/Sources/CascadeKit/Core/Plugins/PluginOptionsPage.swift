//
//  PluginOptionsPage.swift
//  CascadeKit
//

import SwiftUI

/// PluginOptionsPage keeps one live publication store in the shared notch container.
/// Revision changes replace controls through the normal table diff, without a timer.
/// Each rendered control captures this page's origin, so reopening cannot lend it authority.
@MainActor
final class PluginOptionsPage: NotchContextualPage {

    let id    : String
    let store : PluginNodeStore
    let origin: PluginOptionsOrigin
    var contentRevision: UInt64 { store.revision }
    var contentHeight: CGFloat { 220 }
    var accessibilityLabel: String { "Widget options" }

    init(
        id    : String,
        store : PluginNodeStore,
        origin: PluginOptionsOrigin
    ) {
        self.id     = id
        self.store  = store
        self.origin = origin
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        AnyView(PluginDocumentView(
            store        : store,
            optionsOrigin: origin,
            showsOptions : true
        ))
    }
}
