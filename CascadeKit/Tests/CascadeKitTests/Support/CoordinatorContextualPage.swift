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

    private let content: (@MainActor () -> AnyView)?

    init(
        id                       : String,
        contentRevision          : UInt64,
        keepsExpandedPresentation: Bool = false,
        content                  : (@MainActor () -> AnyView)? = nil
    ) {
        self.id                        = id
        self.contentRevision           = contentRevision
        self.keepsExpandedPresentation = keepsExpandedPresentation
        self.content                   = content
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        content?() ?? AnyView(Text(id))
    }
}
