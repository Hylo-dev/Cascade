//
//  ActivityDisplaySelection.swift
//  Cascade
//

enum ActivityDisplaySelection: String, CaseIterable, Identifiable {

    case allDisplays
    case focusedDisplay
    case fixedDisplay

    var id: Self { self }

    var title: String {
        switch self {
            case .allDisplays   : "Tutti gli schermi"
            case .focusedDisplay: "Segui il focus"
            case .fixedDisplay  : "Schermo specifico"
        }
    }
}
