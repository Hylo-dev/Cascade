//
//  ActivityDisplaySelection.swift
//  Cascade
//

import SwiftUI
import CascadeKit

enum ActivityDisplaySelection: String, CaseIterable, Identifiable {
    case allDisplays, focusedDisplay, fixedDisplay

    var id: Self { self }

    var title: String {
        switch self {
        case .allDisplays: "Tutti gli schermi"
        case .focusedDisplay: "Segui il focus"
        case .fixedDisplay: "Schermo specifico"
        }
    }
}
