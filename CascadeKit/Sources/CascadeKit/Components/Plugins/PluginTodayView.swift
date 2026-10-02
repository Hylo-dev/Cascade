//
//  PluginTodayView.swift
//  CascadeKit
//

import SwiftUI

/// PluginTodayView draws a `today` node: today's weekday, day and month, looked at again by
/// SwiftUI at every minute boundary and only while it is on screen, so the date turns at
/// midnight in the environment's zone and locale, the zone being the one a `timeZone` modifier
/// above it sets. It is a view of its own so that only a date of today reads the zone and the
/// locale, and no other node depends on either.
struct PluginTodayView: View {

    @Environment(\.timeZone)
    private var timeZone

    @Environment(\.locale)
    private var locale

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(verbatim: PluginTimeFormat.today(context.date, in: timeZone, locale: locale))
        }
    }
}
