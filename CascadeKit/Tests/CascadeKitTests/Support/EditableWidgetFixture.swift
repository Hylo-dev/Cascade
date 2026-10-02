//
//  EditableWidgetFixture.swift
//  CascadeKit
//

import SwiftUI
@testable import CascadeKit

/// EditableWidgetFixture is a widget with the sizes a test gives it, counting its activations
/// and suspensions, so the editing tests can watch a widget come and go from the grid. A test
/// can also keep it out of the default arrangement, as a new widget that waits in the gallery.
@MainActor
final class EditableWidgetFixture: NotchWidget {

    static let kind = WidgetKind("editable-test")

    let id               : WidgetIdentifier
    let sizes            : [GridSpan]
    let isPlacedByDefault: Bool

    var size: GridSpan { sizes[0] }

    private(set) var activations = 0
    private(set) var suspensions = 0

    init(
        _ id             : String,
        sizes            : [GridSpan] = [GridSpan(columns: 4, rows: 2)],
        isPlacedByDefault: Bool = true
    ) {
        self.id                = WidgetIdentifier(id)
        self.sizes             = sizes
        self.isPlacedByDefault = isPlacedByDefault
    }

    var isActive: Bool { activations > suspensions }

    func makeContentView() -> AnyView { AnyView(Text(id.rawValue)) }

    func activate(in context: WidgetContext) { activations += 1 }

    func suspend() { suspensions += 1 }
}
