//
//  PluginTimeFormat.swift
//  CascadeKit
//

import Foundation

/// PluginTimeFormat is how the kernel spells the time it draws for a plugin, in the zone and
/// locale the view's environment gives. The zone goes into the format style explicitly, so the
/// `timeZone` modifier moves a clock without relying on what `Text` reads from the environment,
/// and a test reads the result without rendering a view.
enum PluginTimeFormat {

    /// clock is the hour and minute, as the `clock` node draws them.
    static func clock(
        _ date : Date,
        in zone: TimeZone,
        locale : Locale
    ) -> String {
        Date.FormatStyle(locale: locale, timeZone: zone)
            .hour()
            .minute()
            .format(date)
    }

    /// today is the abbreviated weekday, the day and the abbreviated month, as the `today` node
    /// draws them.
    static func today(
        _ date : Date,
        in zone: TimeZone,
        locale : Locale
    ) -> String {
        Date.FormatStyle(locale: locale, timeZone: zone)
            .weekday(.abbreviated)
            .day()
            .month(.abbreviated)
            .format(date)
    }
}
