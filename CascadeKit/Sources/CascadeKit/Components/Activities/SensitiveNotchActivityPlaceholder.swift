//
//  SensitiveNotchActivityPlaceholder.swift
//  CascadeKit
//

import SwiftUI

/// SensitiveNotchActivityPlaceholder is constructed without consulting the
/// provider, so private text, URLs, freshness, and accessibility labels cannot
/// enter the hidden SwiftUI tree.
struct SensitiveNotchActivityPlaceholder: View {

    let presentation: NotchActivityPresentation

    var body: some View {
        ZStack {

            isExpandedPresentation ? Color.clear : Color.black

            if isExpandedPresentation {
                Label(String(localized: "Hidden Activity", bundle: .module), systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hidden sensitive activity", bundle: .module))
    }

    private var isExpandedPresentation: Bool {
        if case .expanded = presentation { return true }

        return false
    }
}
