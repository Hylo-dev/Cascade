//
//  PluginDetailView.swift
//  CascadeKit
//

import SwiftUI

/// PluginDetailView draws a detail page: a back button at the top leading corner, then the
/// plugin's document. It gives the components their services and no `openDetail`, since a page
/// that is already a detail has nowhere deeper to go.
struct PluginDetailView: View {

    let store   : PluginNodeStore
    let services: PluginComponentServices
    let back    : @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Back", bundle: .module))

            PluginDocumentView(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.pluginComponentServices, services)
    }
}
