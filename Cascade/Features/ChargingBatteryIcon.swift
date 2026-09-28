//
//  ChargingBatteryIcon.swift
//  Cascade
//

import SwiftUI

/// The reference uses a solid, continuously rounded battery with a separate
/// terminal and a straight charge boundary. Keep that silhouette at every
/// percentage, including empty/full, without adding a lightning bolt.
struct ChargingBatteryIcon: View {
    let percentage    : Int?
    let isLowPowerMode: Bool

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let terminalWidth = height * 0.11
            let gap = height * 0.08
            let bodyWidth = max(0, geometry.size.width - terminalWidth - gap)
            let fraction = CGFloat(min(100, max(0, percentage ?? 0))) / 100
            let silhouette = RoundedRectangle(cornerRadius: height * 0.43, style: .continuous)
            HStack(spacing: gap) {
                ZStack(alignment: .leading) {
                    silhouette
                        .fill(ChargingNoticePalette.remainder(isLowPowerMode))

                    Rectangle()
                        .fill(ChargingNoticePalette.fill(isLowPowerMode))
                        .frame(width: bodyWidth * fraction)
                }
                .frame(width: bodyWidth, height: height)
                .clipShape(silhouette)

                Capsule()
                    .fill(ChargingNoticePalette.remainder(isLowPowerMode))
                    .frame(width: terminalWidth, height: height * 0.36)
            }
        }
        .accessibilityHidden(true)
    }
}

enum ChargingNoticePalette {
    static func text(_ lowPower: Bool) -> Color {
        lowPower ? Color(red: 1, green: 0.82, blue: 0.27) : Color(red: 0.20, green: 0.88, blue: 0.46)
    }

    static func fill(_ lowPower: Bool) -> Color {
        lowPower ? Color(red: 1, green: 0.95, blue: 0.18) : text(false)
    }

    static func remainder(_ lowPower: Bool) -> Color {
        lowPower ? Color(red: 0.48, green: 0.36, blue: 0.20) : text(false).opacity(0.38)
    }
}
