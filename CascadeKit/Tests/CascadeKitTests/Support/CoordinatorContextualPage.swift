//
//  CoordinatorContextualPage.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class CoordinatorContextualPage: NotchContextualPage {

    let id                       : String
    var contentRevision          : UInt64
    let contentHeight            : CGFloat = 146
    let accessibilityLabel        = "Shelf"
    var keepsExpandedPresentation: Bool

    init(
        id                       : String,
        contentRevision          : UInt64,
        keepsExpandedPresentation: Bool = false
    ) {
        self.id                        = id
        self.contentRevision           = contentRevision
        self.keepsExpandedPresentation = keepsExpandedPresentation
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        AnyView(Text(id))
    }
}
