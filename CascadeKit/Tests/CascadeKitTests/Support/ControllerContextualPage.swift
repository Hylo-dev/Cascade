//
//  ControllerContextualPage.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class ControllerContextualPage: NotchContextualPage {

    let id                        = "shelf"
    let contentRevision          : UInt64 = 1
    let contentHeight            : CGFloat
    let keepsExpandedPresentation: Bool
    let accessibilityLabel        = "Shelf"

    private(set) var contexts: [NotchContextualPageContext] = []

    init(
        contentHeight: CGFloat,
        keepsExpanded: Bool = false
    ) {
        self.contentHeight             = contentHeight
        self.keepsExpandedPresentation = keepsExpanded
    }

    func makeContentView(in context: NotchContextualPageContext) -> AnyView {
        contexts.append(context)
        return AnyView(Text("Shelf"))
    }
}
