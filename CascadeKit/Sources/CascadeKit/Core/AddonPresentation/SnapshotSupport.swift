//
//  SnapshotSupport.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

/// AddonPresentationAssetResolving resolves the asset binding of one observed publication revision.
/// The host implementation validates current authority without calling the provider or waiting for IPC.
@MainActor
public protocol AddonPresentationAssetResolving: AnyObject {
    func image(
        for assetID        : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) -> Image?
}

@MainActor
final class EmptyAddonAssetResolver: AddonPresentationAssetResolving {
    func image(
        for assetID        : String,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) -> Image? { nil }
}

@MainActor
final class ScopedAssetResolver: ContentAssetResolving {
    private weak var base: (any AddonPresentationAssetResolving)?
    private let publicationID: PublicationID
    private let publicationRevision: UInt64

    init(
        base               : any AddonPresentationAssetResolving,
        publicationID      : PublicationID,
        publicationRevision: UInt64
    ) {
        self.base = base
        self.publicationID = publicationID
        self.publicationRevision = publicationRevision
    }

    /// image preserves this view's revision even when the host replaces the publication.
    func image(for assetID: String) -> Image? {
        base?.image(
            for                : assetID,
            publicationID      : publicationID,
            publicationRevision: publicationRevision
        )
    }
}

@MainActor
final class ActionLease {
    private var callback: (@MainActor @Sendable (ActionDescriptor) -> Void)?
    private let expiresAt: Date
    private let now: () -> Date
    init(
        expiresAt: Date = .distantFuture,
        now: @escaping () -> Date = Date.init,
        _ callback: @escaping @MainActor @Sendable (ActionDescriptor) -> Void
    ) {
        self.expiresAt = expiresAt; self.now = now; self.callback = callback
    }
    func dispatch(_ action: ActionDescriptor) {
        guard now() < expiresAt else { callback = nil; return }
        callback?(action)
    }
    func revoke() { callback = nil }
}

@MainActor
final class ActionPermit {
    private var callback: (@MainActor @Sendable (ActionDescriptor) -> Void)?
    init(_ callback: @escaping @MainActor @Sendable (ActionDescriptor) -> Void) { self.callback = callback }
    func dispatch(_ action: ActionDescriptor) { callback?(action) }
    func revoke() { callback = nil }
}

@MainActor
struct SnapshotDocumentView: View {
    let document: ContentDocument
    let assets: any ContentAssetResolving
    var redactsSensitiveContent = false
    let dispatch: @MainActor @Sendable (ActionDescriptor) -> Void

    var body: some View {
        if redactsSensitiveContent && document.privacy == .sensitive {
            Label("Sensitive content hidden", systemImage: "eye.slash")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sensitive content hidden")
        } else if let renderer = try? ContentRenderer(document: document, assets: assets, dispatch: dispatch) {
            renderer
        }
    }
}
