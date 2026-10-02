//
//  PluginActivity.swift
//  CascadeKit
//

import SwiftUI

/// PluginActivity adapts a plugin's ongoing task to the native activity host. Four regions
/// describe compact leading, compact trailing, minimal and expanded content; a plain document
/// fills every presentation. Its finite lifetime is retained when its nodes change. Time is
/// drawn only by the visible SwiftUI host, never by a wake in PluginHost.
@MainActor
final class PluginActivity: NotchLiveActivity {

    let id      : String
    let sourceID: String
    let store   : PluginNodeStore
    let lifetime = NotchActivityLifetime()
    let privacy  = NotchActivityPrivacy.standard
    let relevanceScore = 1.0

    private let visibility: (Bool) -> Void

    var contentRevision: UInt64 { store.revision }

    /// compactPreferredSideWidth honors explicit region widths plus the host's 12-point
    /// outer and 2-point inner insets. The controller reads this only on content changes.
    var compactPreferredSideWidth: CGFloat? {
        guard let root = store.root, root.kind == .regions else { return nil }
        var width: Double = 0
        for id in root.children.prefix(2) {
            guard let region = store.model(id) else { return nil }
            var declared: Double?
            for modifier in region.modifiers.reversed() {
                if case .frame(let fixedWidth?, _, _, _, _) = modifier {
                    declared = fixedWidth
                    break
                }
            }
            guard let declared else { return nil }
            width = max(width, declared)
        }
        return width > 0 ? CGFloat(width) + 14 : nil
    }

    var accessibilityLabel: String {
        for modifier in store.root?.modifiers ?? [] {
            if case .accessibilityLabel(let label) = modifier { return label }
        }
        return sourceID
    }

    init(
        id        : String,
        sourceID  : String,
        store     : PluginNodeStore,
        visibility: @escaping (Bool) -> Void
    ) {
        self.id         = id
        self.sourceID   = sourceID
        self.store      = store
        self.visibility = visibility
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView { view(0) }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView { view(1) }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView { view(2) }

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView { view(3) }

    func activate(in context: LiveActivityContext) { visibility(true) }

    func suspend() { visibility(false) }

    private func view(_ index: Int) -> AnyView {
        if store.root?.kind == .regions {
            return AnyView(PluginRegionView(store: store, index: index))
        }
        return AnyView(PluginDocumentView(store: store))
    }
}
