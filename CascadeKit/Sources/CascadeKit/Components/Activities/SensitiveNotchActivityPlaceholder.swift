//
//  SensitiveNotchActivityPlaceholder.swift
//  CascadeKit
//

import AppKit
import Observation
import OSLog
import QuartzCore
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
                Label("Attività nascosta", systemImage: "lock.fill")
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
        .accessibilityLabel("Attività sensibile nascosta")
    }

    private var isExpandedPresentation: Bool {
        if case .expanded = presentation { return true }
        return false
    }
}
