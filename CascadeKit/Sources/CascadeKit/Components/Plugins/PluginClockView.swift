//
//  PluginClockView.swift
//  CascadeKit
//

import SwiftUI

/// PluginClockView draws a `clock` node: the time now, redrawn by SwiftUI at every minute
/// boundary and only while it is on screen, in the environment's zone and locale, the zone being
/// the one a `timeZone` modifier above it sets. It is a view of its own so that only a clock
/// reads the zone and the locale, and no other node depends on either.
struct PluginClockView: View {

    @Environment(\.timeZone)
    private var timeZone

    @Environment(\.locale)
    private var locale

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(verbatim: PluginTimeFormat.clock(context.date, in: timeZone, locale: locale))
                .animation(.smooth, value: context.date)
        }
    }
}
