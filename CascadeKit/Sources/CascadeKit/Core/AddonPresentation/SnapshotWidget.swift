//
//  SnapshotWidget.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
final class SnapshotWidget: NotchWidget {

    static let kind = WidgetKind("addon.snapshot")

    let id  : WidgetIdentifier
    let size = GridSpan(columns: 2, rows: 1)

    private(set) var document          : ContentDocument
    private(set) var accessibilityLabel: String

    private var assets : any ContentAssetResolving
    private var actions: ActionLease
    private var permit : ActionPermit?
    private var context: WidgetContext?

    init(
        id      : String,
        document: ContentDocument,
        assets  : any ContentAssetResolving,
        actions : ActionLease
    ) {
        self.id            = WidgetIdentifier(id)
        self.document      = document
        self.assets        = assets
        self.actions       = actions
        accessibilityLabel = document.privacy == .sensitive ? "Sensitive content hidden" : document.accessibilityLabel
    }

    func makeContentView() -> AnyView {
        let captured = permit

        return AnyView(
            SnapshotDocumentView(
                document               : document,
                assets                 : assets,
                redactsSensitiveContent: true
            ) { action in
                captured?.dispatch(action)
            }
        )
    }

    func activate(in context: WidgetContext) {
        self.context = context
        permit       = ActionPermit { [actions] action in actions.dispatch(action) }
    }

    func suspend() {
        permit?.revoke()
        permit  = nil
        context = nil
    }

    func update(
        document: ContentDocument,
        assets  : any ContentAssetResolving,
        actions : ActionLease
    ) {
        permit?.revoke()

        self.document      = document
        self.assets        = assets
        self.actions       = actions
        accessibilityLabel = document.privacy == .sensitive ? "Sensitive content hidden" : document.accessibilityLabel

        if context != nil { permit = ActionPermit { [actions] action in actions.dispatch(action) } }
        context?.setNeedsContent()
    }

    func copiedActionForTesting() -> @MainActor @Sendable (ActionDescriptor) -> Void {
        let captured = permit

        return { action in captured?.dispatch(action) }
    }

    func dispatchForTesting(_ action: ActionDescriptor) { permit?.dispatch(action) }
}
