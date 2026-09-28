//
//  View+NotchGlassLights.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

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
