//
//  NotchGlassLights.swift
//  Cascade
//

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
