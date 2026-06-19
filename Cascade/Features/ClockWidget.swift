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

/// The clock face. `TimelineView` is SwiftUI's declarative, GPU-driven ticker —
/// it updates only while on screen, so it respects the "no idle polling" rule
/// once the notch closes and the content host is hidden.
private struct ClockContentView: View {

    var body: some View {

        TimelineView(.periodic(from: .now, by: 1)) { context in

            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
