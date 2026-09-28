//
//  SpotlightDropletPresenting.swift
//  Cascade
//

import AppKit

extension NSScreen {
    /// cascadeRuntimeDisplayID exposes the AppKit session identifier to app
    /// integrations without depending on CascadeKit's internal screen adapter.
    var cascadeRuntimeDisplayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

/// SpotlightDisplayAnchor freezes the invocation display and its actual compact
/// surface before focus can move to the native Spotlight window.
@MainActor
struct SpotlightDisplayAnchor {
    let displayID    : CGDirectDisplayID
    let screen       : NSScreen
    let restingBounds: CGRect
}

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
