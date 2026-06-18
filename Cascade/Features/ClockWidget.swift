//
//  ClockWidget.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// ClockWidget is a demo widget: a live clock shown in the expanded notch.
///
/// It exists to exercise the widget SDK end to end — registration, region
/// placement, lifecycle and SwiftUI content — without touching any engine
/// internals. It talks to nothing but the `NotchWidget` protocol, which is the
/// whole point: widgets are decoupled from the app and the engine.
final class ClockWidget: NotchWidget {

    static let identifier = WidgetIdentifier("com.cascade.clock")

    let preferredRegion: NotchRegion = .expanded

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

            Text(context.date, format: .dateTime.hour().minute().second())
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }
}
