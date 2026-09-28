//
//  NotchGlassLights.swift
//  Cascade
//

import AppKit
import CascadeContracts
import SwiftUI

/// NotchGlassLightsPreferenceKey combines descendant contributions in view order.
/// Only the first eight lights reach the host, bounding the renderer's work.
public struct NotchGlassLightsPreferenceKey: PreferenceKey {
    public static var defaultValue: [GlassLight] { [] }

    public static func reduce(value: inout [GlassLight], nextValue: () -> [GlassLight]) {
        value = Array(value.prefix(GlassLight.maximumCount))
        let remaining = GlassLight.maximumCount - value.count
        guard remaining > 0 else { return }
        value.append(contentsOf: nextValue().prefix(remaining))
    }
}

extension View {
    /// notchGlassLights adds decorative light to expanded glass without changing content layout.
    /// Descendant contributions retain priority; the host controls visibility and accessibility.
    public func notchGlassLights(_ lights: [GlassLight]) -> some View {
        let boundedLights = Array(lights.prefix(GlassLight.maximumCount))
        return transformPreference(NotchGlassLightsPreferenceKey.self) { value in
            NotchGlassLightsPreferenceKey.reduce(value: &value, nextValue: { boundedLights })
        }
    }
}

/// NotchGlassLightReceiving lets AppKit content drive glass light without a
/// SwiftUI update per change. A view inside the notch's content finds the
/// nearest receiver among its superviews and hands it lights in the same
/// normalized space as `notchGlassLights`; an empty array withdraws them, and
/// so does replacing or hiding the content the view belongs to.
///
/// For light that follows a live signal, such as a spectrum at 30 Hz: through
/// the preference every tick re-evaluated SwiftUI, measured at ~1.3 % of a core
/// more than this path. Static light keeps using `notchGlassLights`.
@MainActor
public protocol NotchGlassLightReceiving: NSView {
    /// The outline the lights are normalized to once the notch settles, in
    /// the receiver's coordinates; y runs down from its top edge.
    var glassLightBounds: CGRect { get }
    func setGlassLights(_ lights: [GlassLight], from emitter: NSView)
}
