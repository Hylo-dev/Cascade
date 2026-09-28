//
//  CascadeSettingsPage.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// CascadeSettingsPage defines the three stable destinations in the sidebar.
enum CascadeSettingsPage: String, CaseIterable, Identifiable {
    case appearance, dev, widget

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .dev: "Dev"
        case .widget: "Widget"
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintbrush.fill"
        case .dev: "hammer.fill"
        case .widget: "square.grid.2x2.fill"
        }
    }

    var color: Color {
        switch self {
        case .appearance: .blue
        case .dev: .gray
        case .widget: .purple
        }
    }
}
