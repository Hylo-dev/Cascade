//
//  ClockContentView.swift
//  Cascade
//

import SwiftUI
import CascadeKit

/// ClockContentView draws the clock face. `TimelineView` is SwiftUI's
/// declarative, GPU-driven ticker — it updates only while on screen, so it
/// respects the "no idle polling" rule once the notch closes and the content
/// host is hidden.
struct ClockContentView: View {

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
