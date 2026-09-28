//
//  SpotlightDropletPresenting.swift
//  Cascade
//

import AppKit

/// SpotlightDropletPresenting owns the finite visual handoff before native Spotlight opens.
///
/// Completion is delivered once, after the detached capsule has landed, in
/// global AppKit coordinates. The landed glass yields its stacking position
/// before native invocation and is removed as soon as the native field becomes visible.
@MainActor
protocol SpotlightDropletPresenting: AnyObject {

    func play(
        at anchor  : SpotlightDisplayAnchor,
        nativeSize : CGSize,
        completion : @escaping (CGRect) -> Void
    )

    func yieldToNative()

    func revealNative()

    func cancel()

    func preview(
        at anchor  : SpotlightDisplayAnchor,
        completion: @escaping () -> Void
    )
}
