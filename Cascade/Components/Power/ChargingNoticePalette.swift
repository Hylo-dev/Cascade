//
//  ChargingNoticePalette.swift
//  Cascade
//

import SwiftUI

enum ChargingNoticePalette {

    static func text(_ lowPower: Bool) -> Color {
        lowPower
            ? Color(red: 1, green: 0.82, blue: 0.27)
            : Color(red: 0.20, green: 0.88, blue: 0.46)
    }

    static func fill(_ lowPower: Bool) -> Color {
        lowPower
            ? Color(red: 1, green: 0.95, blue: 0.18)
            : text(false)
    }

    static func remainder(_ lowPower: Bool) -> Color {
        lowPower
            ? Color(red: 0.48, green: 0.36, blue: 0.20)
            : text(false).opacity(0.38)
    }
}
