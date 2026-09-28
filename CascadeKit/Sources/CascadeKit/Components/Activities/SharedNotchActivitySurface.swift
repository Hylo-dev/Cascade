//
//  SharedNotchActivitySurface.swift
//  CascadeKit
//

import SwiftUI

/// SharedNotchActivitySurface applies the host-owned appearance and behavior
/// around standard provider content. Providers keep control of their own view,
/// while Cascade supplies safe insets, stale status, accessibility, and links.
struct SharedNotchActivitySurface: View {

    let content           : AnyView
    let contentSize       : CGSize
    let contentURL        : URL?
    let accessibilityLabel: String
    let presentation      : NotchActivityPresentation
    let isStale           : Bool
    let insets            : EdgeInsets

    var body: some View {
        ZStack {

            // The host owns expanded chrome, including glass and the opaque
            // accessibility fallback. A provider wrapper must not cover it.
            isExpandedPresentation ? Color.clear : Color.black

            linkedContent
                .padding(insets)
        }
        .environment(\.colorScheme, .dark)
        .font(isExpandedPresentation ? .body : .callout)
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var linkedContent: some View {
        if !isExpandedPresentation, let contentURL {
            Link(destination: contentURL) {
                row(showsOpenControl: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            row(showsOpenControl: isExpandedPresentation && contentURL != nil)
        }
    }

    private func row(showsOpenControl: Bool) -> some View {
        HStack(spacing: 0) {

            content
                .frame(
                    width : contentSize.width,
                    height: contentSize.height
                )
                // Layout stays inside the content insets. Permit a bounded
                // glow/shadow around it; the native container still clips all
                // painting to the notch outline, including above the content.
                .padding(40)
                .clipped()
                .padding(-40)

            if isStale {
                Spacer()
                    .frame(width: 4)

                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .frame(width: 14)
                    .accessibilityLabel("Aggiornamento in ritardo")
            }

            if showsOpenControl, let contentURL {
                Spacer()
                    .frame(width: 8)

                Link(destination: contentURL) {
                    Label("Apri", systemImage: "arrow.up.forward.app")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .frame(width: 68)
            }
        }
    }

    private var isExpandedPresentation: Bool {
        if case .expanded = presentation { return true }

        return false
    }
}
