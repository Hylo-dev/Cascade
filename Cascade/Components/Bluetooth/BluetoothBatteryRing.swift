//
//  BluetoothBatteryRing.swift
//  Cascade
//

import SwiftUI

/// BluetoothBatteryRing uses arc length to show charge without visible text.
/// Its thinner, dim green track keeps the missing portion legible on black.
/// Unknown charge never implies a full battery; exact values remain available
/// to accessibility clients and in the notice's help text.
struct BluetoothBatteryRing: View {
    let level       : Int?
    let diameter    : CGFloat
    let isConnected : Bool

    private var normalizedLevel: Int? {
        guard isConnected, let level, (0...100).contains(level) else { return nil }
        return level
    }

    private let chargeColor = Color(red: 0.30, green: 0.91, blue: 0.40)

    private var progressLineWidth: CGFloat { max(2.25, diameter * 0.115) }
    private var trackLineWidth   : CGFloat { progressLineWidth * 0.6 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(chargeColor.opacity(0.28), lineWidth: trackLineWidth)

            if let level = normalizedLevel, level > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(level) / 100)
                    .stroke(
                        chargeColor,
                        style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(progressLineWidth / 2)
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    var accessibilityLabel: String {
        guard isConnected else {
            return String(localized: "Disconnected, battery unavailable", table: "BluetoothNotice")
        }
        guard let level = normalizedLevel else {
            return String(localized: "Battery unavailable", table: "BluetoothNotice")
        }
        return String(localized: "Battery, \(level) percent", table: "BluetoothNotice")
    }
}
