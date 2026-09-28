//
//  NotchGlassLightObserver.swift
//  CascadeKit
//

import CascadeContracts
import CascadePresentation
import SwiftUI

private struct GlassEmissionPreference: PreferenceKey {

    static var defaultValue: NotchGlassLightEmission? { nil }

    static func reduce(
        value    : inout NotchGlassLightEmission?,
        nextValue: () -> NotchGlassLightEmission?
    ) {
        if let next = nextValue() { value = next }
    }
}

/// NotchGlassLightObserver includes the root generation in the delivered value.
/// Replacing content with the same colors still updates its ownership, without
/// resetting view identity.
struct NotchGlassLightObserver: View {

    let content : AnyView
    let token   : NotchGlassLightSources.Token
    let onChange: @MainActor (NotchGlassLightEmission) -> Void

    var body: some View {
        content
            .overlayPreferenceValue(NotchGlassLightsPreferenceKey.self) { lights in
                Color.clear
                    .preference(
                        key  : GlassEmissionPreference.self,
                        value: NotchGlassLightEmission(token: token, lights: lights)
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onPreferenceChange(GlassEmissionPreference.self) { emission in
                guard let emission else { return }

                Task { @MainActor in onChange(emission) }
            }
    }
}
