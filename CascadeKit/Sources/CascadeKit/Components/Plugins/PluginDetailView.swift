//
//  PluginDetailView.swift
//  CascadeKit
//

import SwiftUI

/// PluginDetailView draws a detail page: the plugin's document over the whole frame, and a back
/// button laid over its top leading corner. The page is only as tall as the notch's ordinary
/// expanded surface, so a bar above the document would cost it a row of its few; the button
/// floats instead, inside the left shoulder beside the hardware notch, and the document is told
/// where the notch is (`pluginPageObstruction`) so it keeps clear of it. It gives the components
/// their services and no `openDetail`, since a page that is already a detail has nowhere deeper
/// to go.
struct PluginDetailView: View {

    static let backButtonSize: CGFloat = 24

    private static let backButtonLeadingInset: CGFloat = 4
    private static let backButtonTopInset    : CGFloat = 4

    let store      : PluginNodeStore
    let services   : PluginComponentServices
    let obstruction: CGRect
    let back       : @MainActor () -> Void

    /// backButtonOrigin is where the back button's top leading corner goes: vertically centred
    /// in the obstruction's height when the notch covers the top of the page, else at the top.
    static func backButtonOrigin(obstruction: CGRect) -> CGPoint {
        let top = obstruction.height > 0
            ? (obstruction.height - backButtonSize) / 2
            : backButtonTopInset
        return CGPoint(
            x: backButtonLeadingInset,
            y: top
        )
    }

    var body: some View {
        let origin = Self.backButtonOrigin(obstruction: obstruction)

        PluginDocumentView(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: Self.backButtonSize, height: Self.backButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back", bundle: .module))
                .padding(.leading, origin.x)
                .padding(.top, origin.y)
            }
            .environment(\.pluginComponentServices, services)
            .environment(\.pluginPageObstruction, obstruction)
    }
}
