//
//  SnapshotOptionsPage.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

/// SnapshotOptionsPage renders a bounded leased document inside native host chrome.
/// Revision invalidation revokes the copied action lease before rebuilding disabled content.
@MainActor
final class SnapshotOptionsPage: NotchContextualPage {

    let id                          : String
    private(set) var contentRevision: UInt64
    let contentHeight               : CGFloat = 200
    var accessibilityLabel: String {
        document.privacy == .sensitive
            ? String(localized: "Sensitive content hidden", bundle: .module)
            : document.accessibilityLabel
    }
    private(set) var actions        : ActionLease
    private var document            : ContentDocument
    private var assets              : any ContentAssetResolving
    private var isEnabled = true

    init(
        id      : String,
        document: ContentDocument,
        assets  : any ContentAssetResolving,
        actions : ActionLease,
        revision: UInt64 = 1
    ) {
        self.id         = id
        self.document   = document
        self.assets     = assets
        self.actions    = actions
        contentRevision = revision
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        let captured = actions
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text(accessibilityLabel)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                SnapshotDocumentView(
                    document               : document,
                    assets                 : assets,
                    redactsSensitiveContent: true
                ) { action in captured.dispatch(action) }
                .disabled(!isEnabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        )
    }

    func invalidateControls() {
        actions.revoke()
        guard isEnabled else { return }
        isEnabled = false
        contentRevision &+= 1
    }
}
