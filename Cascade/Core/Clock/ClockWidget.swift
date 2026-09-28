//
//  ClockWidget.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// ClockWidget is a demo widget: a live clock placed on the notch grid.
///
/// It exists to exercise the widget SDK end to end — id/kind, grid size,
/// lifecycle and SwiftUI content — without touching any engine internals. It
/// talks to nothing but the `NotchWidget` protocol, which is the whole point:
/// widgets are decoupled from the app and the engine.
final class ClockWidget: NotchWidget {

    let id = WidgetIdentifier("clock-1") // UUID().uuidString

    static let kind = WidgetKind("com.cascade.clock")

    /// A wide, one-row tile (compact): two columns by one row.
    let size = GridSpan(columns: 4, rows: 1)

    func makeContentView() -> AnyView {
        AnyView(ClockContentView())
    }
}
