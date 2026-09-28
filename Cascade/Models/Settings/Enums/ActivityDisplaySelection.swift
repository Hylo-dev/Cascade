//
//  ActivityDisplaySelection.swift
//  Cascade
//

import Foundation

enum ActivityDisplaySelection: String, CaseIterable, Identifiable {

    case allDisplays
    case focusedDisplay
    case fixedDisplay

    var id: Self { self }

    var title: String {
        switch self {
            case .allDisplays   : String(localized: "All Displays")
            case .focusedDisplay: String(localized: "Follow Focus")
            case .fixedDisplay  : String(localized: "Specific Display")
        }
    }
}
