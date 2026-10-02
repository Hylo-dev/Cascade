//
//  PluginBluetoothBatteryComponent.swift
//  CascadeKit
//

import SwiftUI

/// PluginBluetoothBatteryComponent is the tier-2 component bluetooth.battery: a ring whose arc
/// length is a Bluetooth device's charge, as large as the frame it is given allows. Its thinner,
/// dim green track keeps the missing portion legible on black. An unknown charge, or that of a
/// device that just disconnected, draws no arc and never passes for a full battery; the notice's
/// sentence carries the numbers for VoiceOver.
struct PluginBluetoothBatteryComponent: View {

    let level      : Int?
    let isConnected: Bool

    private let chargeColor = Color(
        red  : 0.30,
        green: 0.91,
        blue : 0.40
    )

    var body: some View {
        GeometryReader { geometry in
            let diameter          = min(geometry.size.width, geometry.size.height)
            let progressLineWidth = max(2.25, diameter * 0.115)

            ZStack {

                Circle()
                    .stroke(chargeColor.opacity(0.28), lineWidth: progressLineWidth * 0.6)

                if isConnected, let level, level > 0 {
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, level)) / 100)
                        .stroke(
                            chargeColor,
                            style: StrokeStyle(lineWidth: progressLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
            .padding(progressLineWidth / 2)
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}
