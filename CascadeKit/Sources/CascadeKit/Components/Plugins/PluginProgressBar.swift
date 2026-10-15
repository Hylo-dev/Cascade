//
//  PluginProgressBar.swift
//  CascadeKit
//

import SwiftUI

/// PluginProgressBar is the kernel's bar at a fraction: a thin capsule filled with the foreground
/// style it inherits, as text is, over a dim track of the same colour, which on the widget
/// surface's dark scheme is white unless the node or a parent names another. It reads to
/// VoiceOver as a progress indicator.
///
/// A `timerProgress` draws it at the fraction its timeline has reached, and a linear `progress`
/// at its value, so a paused timer's bar looks like the running one. SwiftUI's own linear bar
/// is not used for either: it turns grey in a window that is never key, which the notch's panel
/// never is.
struct PluginProgressBar: View {

    static let height = 5.0

    let fraction: Double

    var body: some View {
        Capsule()
            .fill(.foreground.opacity(0.22))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.foreground)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: Self.height)
            .accessibilityRepresentation {
                ProgressView(value: fraction)
            }
    }
}
