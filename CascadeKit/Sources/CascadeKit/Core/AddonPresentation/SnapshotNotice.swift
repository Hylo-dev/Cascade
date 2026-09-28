//
//  SnapshotNotice.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

@MainActor
final class SnapshotNotice: NotchTransientNotice {
    let id: String
    let sourceID: String
    let contentRevision: UInt64
    let displayDuration: TimeInterval = 10
    let accessibilityLabel: String
    let privacy: NotchActivityPrivacy
    private let content: PresentationSet
    private let assets: any ContentAssetResolving
    private let actions: ActionLease
    private var permit: ActionPermit?

    init(id: String, sourceID: String, revision: UInt64, content: PresentationSet, assets: any ContentAssetResolving, actions: ActionLease) {
        self.id = id; self.sourceID = sourceID; contentRevision = revision
        self.content = content; self.assets = assets; self.actions = actions
        let docs = [content.compactLeading, content.compactTrailing, content.minimal].compactMap { $0 }
        privacy = docs.contains { $0.privacy == .sensitive } ? .sensitive : .standard
        accessibilityLabel = content.minimal?.accessibilityLabel ?? "Addon notice"
    }
    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView { view(content.compactLeading) }
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { view(content.compactTrailing) }
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { view(content.minimal) }
    private func view(_ document: ContentDocument?) -> AnyView {
        let captured = permit
        return AnyView(SnapshotDocumentView(document: document ?? content.minimal!, assets: assets) { action in
            captured?.dispatch(action)
        })
    }
    func activate(in context: LiveActivityContext) {
        permit = ActionPermit { [actions] action in actions.dispatch(action) }
    }
    func suspend() { permit?.revoke(); permit = nil }
    func copiedActionForTesting() -> @MainActor @Sendable (ActionDescriptor) -> Void {
        let captured = permit
        return { action in captured?.dispatch(action) }
    }
}
