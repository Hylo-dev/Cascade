//
//  ActivityExpansionSelection.swift
//  CascadeKit
//

import Foundation

/// ActivityExpansionSelection distinguishes a closed surface, one requested
/// live activity, explicit fallback content, and a widget-only opening.
enum ActivityExpansionSelection: Equatable {
    case none
    case activity(String)
    case fallback
    case widgets
}
