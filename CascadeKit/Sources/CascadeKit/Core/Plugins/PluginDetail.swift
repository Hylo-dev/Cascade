//
//  PluginDetail.swift
//  CascadeKit
//

import CascadePluginEngine
import SwiftUI

/// PluginDetail is one plugin feature's detail page: the notch shows it over its expanded surface
/// when the feature's widget asks. It is built once, with the feature's first detail publication,
/// and kept: the store behind it keeps following the plugin while the page is closed, so opening
/// it never waits for the plugin. Its revision is the store's, so a new publication redraws the
/// shown page without the host rebuilding it.
@MainActor
final class PluginDetail: NotchContextualPage {

    /// contentHeight asks for more than the notch will ever give, as the file shelf does: the
    /// host clamps every page to the ordinary expanded height, so the notch keeps its size
    /// whatever it shows and the page lays itself out in what is left.
    let contentHeight: CGFloat = 144

    let id   : String
    let store: PluginNodeStore

    private let services: PluginComponentServices
    private let dismiss : @MainActor () -> Void

    /// init(key:store:services:dismiss:) takes the closure the back button runs, which closes the
    /// page through the host, so the page never holds the notch.
    init(
        key     : PluginPublicationKey,
        store   : PluginNodeStore,
        services: PluginComponentServices,
        dismiss : @escaping @MainActor () -> Void
    ) {
        self.id       = Self.identifier(of: key)
        self.store    = store
        self.services = services
        self.dismiss  = dismiss
    }

    static func identifier(of key: PluginPublicationKey) -> String {
        "plugin-detail:" + key.plugin.rawValue + "/" + key.feature
    }

    var contentRevision: UInt64 {
        store.revision
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        AnyView(detailView(in: context))
    }

    /// detailView is the page's view with what the context says about the notch it sits under:
    /// the hardware notch's obstruction goes into the view, which puts it in the environment
    /// for the components. It is separate from `makeContentView`, which erases the type, so a
    /// test can read what the page was given.
    func detailView(in context: NotchContextualPageContext) -> PluginDetailView {
        PluginDetailView(
            store      : store,
            services   : services,
            obstruction: context.centerObstructionFrame,
            back       : back
        )
    }

    /// back closes the page, as the back button does.
    func back() {
        dismiss()
    }
}
