//
//  PluginActivity.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginActivity shows one plugin's live activity on the notch through today's activity host.
/// It lives as long as its publication: the router keeps the same instance across updates, so
/// the host sees one activity whose content revision moves. The router presents it again when
/// its attributes change, and when the plugin renews its start it ends the old session and
/// presents the activity anew, which is what gives the renewed lifetime a fresh session cap.
/// The three compact regions fill their slots as a notice's do, the leading one from the leading
/// edge, the trailing one from the trailing edge, the minimal one centred; the optional fourth
/// is the expanded content, which lays itself out in the room the host gives it. Without it the
/// activity reports no expanded presentation and never takes over the opened notch.
///
/// Whether the activity is on screen is reported as it is activated and suspended, so the kernel
/// can ask the plugin for one refresh when stale content becomes visible, and never otherwise.
@MainActor
final class PluginActivity: NotchLiveActivity {

    let id      : String
    let sourceID: String
    let store   : PluginNodeStore
    let privacy  = NotchActivityPrivacy.standard

    private(set) var attributes: PluginActivityAttributes

    private let visibility: (Bool) -> Void

    init(
        id        : String,
        sourceID  : String,
        store     : PluginNodeStore,
        attributes: PluginActivityAttributes,
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

    var accessibilityLabel: String {
        attributes.accessibilityLabel
    }

    var lifetime: NotchActivityLifetime {
        NotchActivityLifetime(startedAt: attributes.startedAt)
    }

    var relevanceScore: Double {
        attributes.relevance
    }

    /// The plugin publishes a fourth region only for an activity that expands; with three the
    /// activity is a status, and the notch opens on the widgets instead of on an empty page.
    var hasExpandedPresentation: Bool {
        store.root?.children.count == 4
    }

    func update(_ attributes: PluginActivityAttributes) {
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

    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        region(3, alignment: .center, in: context)
    }

    func activate(in context: LiveActivityContext) {
        visibility(true)
    }

    func suspend() {
        visibility(false)
    }

    /// region frames one region in its slot and reads the compact ones to VoiceOver as the
    /// activity's sentence, instead of the texts and symbol names they are drawn from. The
    /// expanded region keeps its own controls reachable, so it is not folded into one element.
    private func region(
        _ index   : Int,
        alignment : Alignment,
        in context: NotchActivityViewContext
    ) -> AnyView {
        let view = PluginRegionView(store: store, index: index)
            .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height, alignment: alignment)

        guard index < 3 else { return AnyView(view) }

        return AnyView(
            view
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(attributes.accessibilityLabel)
        )
    }
}
