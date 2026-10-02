//
//  EditableWidgetFixture.swift
//  CascadeKit
//

import SwiftUI
@testable import CascadeKit

/// EditableWidgetFixture is a widget with the sizes a test gives it, counting its activations
/// and suspensions, so the editing tests can watch a widget come and go from the grid.
@MainActor
final class EditableWidgetFixture: NotchWidget {

    static let kind = WidgetKind("editable-test")

    let id   : WidgetIdentifier
    let sizes: [GridSpan]

    var size: GridSpan { sizes[0] }

    private(set) var activations = 0
    private(set) var suspensions = 0

    init(
        _ id : String,
        sizes: [GridSpan] = [GridSpan(columns: 4, rows: 2)]
    ) {
        self.id    = WidgetIdentifier(id)
        self.sizes = sizes
    }

    var isActive: Bool { activations > suspensions }

    func makeContentView() -> AnyView { AnyView(Text(id.rawValue)) }

    func activate(in context: WidgetContext) { activations += 1 }

    func suspend() { suspensions += 1 }
}
