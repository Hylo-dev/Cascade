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

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        region(0, alignment: .leading, in: context)
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        region(1, alignment: .trailing, in: context)
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        region(2, alignment: .center, in: context)
    }

    func activate(in context: LiveActivityContext) {
        visibility(true)
    }

    func suspend() {
        visibility(false)
    }

    /// region frames one region in its slot and reads it to VoiceOver as the notice's sentence,
    /// as Cascade's own notices do, instead of the texts and symbol names it is drawn from.
    private func region(
        _ index   : Int,
        alignment : Alignment,
        in context: NotchActivityViewContext
    ) -> AnyView {
        AnyView(
            PluginRegionView(store: store, index: index)
                .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height, alignment: alignment)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(attributes.accessibilityLabel)
        )
    }
}
