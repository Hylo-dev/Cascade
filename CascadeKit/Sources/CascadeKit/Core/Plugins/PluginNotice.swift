//
//  PluginNotice.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginNotice shows one plugin's notice on the notch through today's notice host. It lives as
/// long as its publication and is shown again for each new revision, which the store gives every
/// notice publication, so a repeated notice appears again. The host expires it after its
/// duration. Each region fills its slot as today's notices do: the leading one from the leading
/// edge, the trailing one from the trailing edge, the minimal one centred.
@MainActor
final class PluginNotice: NotchTransientNotice {

    let id      : String
    let sourceID: String
    let store   : PluginNodeStore
    let privacy  = NotchActivityPrivacy.standard

    private(set) var attributes: PluginNoticeAttributes

    private let visibility: (Bool) -> Void

    init(
        id        : String,
        sourceID  : String,
        store     : PluginNodeStore,
        attributes: PluginNoticeAttributes,
        visibility: @escaping (Bool) -> Void
    ) {
        self.id         = id
        self.sourceID   = sourceID
        self.store      = store
        self.attributes = attributes
        self.visibility = visibility
    }

    var contentRevision: UInt64 {
        store.revision
    }

    var displayDuration: TimeInterval {
        attributes.duration
    }

    var accessibilityLabel: String {
        attributes.accessibilityLabel
    }

    var borderAppearance: NotchBorderAppearance? {
        attributes.border?.notchBorderAppearance
    }

    var compactPreferredSideWidth: CGFloat? {
        attributes.compactWidth.map { CGFloat($0) }
    }

    func update(_ attributes: PluginNoticeAttributes) {
        self.attributes = attributes
    }

    /// region is the node a region draws, for tests and accessibility checks.
    func region(_ index: Int) -> PluginNodeModel? {
        guard let root = store.root, root.children.indices.contains(index) else { return nil }

        return store.model(root.children[index])
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            PluginRegionView(store: store, index: 0)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height, alignment: .leading)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            PluginRegionView(store: store, index: 1)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height, alignment: .trailing)
        )
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            PluginRegionView(store: store, index: 2)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
        )
    }

    func activate(in context: LiveActivityContext) {
        visibility(true)
    }

    func suspend() {
        visibility(false)
    }
}
