//
//  PluginBatteryComponent.swift
//  CascadeKit
//

import SwiftUI

/// PluginBatteryComponent is the tier-2 component power.battery: a solid, continuously rounded
/// battery with a separate terminal and a straight charge boundary, drawn from the charge and Low
/// Power Mode its publication carries. It keeps that silhouette at every percentage, including
/// empty and full. A publication that says the Mac is charging gets a white bolt over the body,
/// as the battery widget asks; the charging notice says so in words and leaves it out.
struct PluginBatteryComponent: View {

    let percentage    : Int?
    let isLowPowerMode: Bool
    let isCharging    : Bool

    var body: some View {
        GeometryReader { geometry in
            let height        = geometry.size.height
            let terminalWidth = height * 0.11
            let gap           = height * 0.08
            let bodyWidth     = max(0, geometry.size.width - terminalWidth - gap)
            let fraction      = CGFloat(min(100, max(0, percentage ?? 0))) / 100
            let silhouette    = RoundedRectangle(cornerRadius: height * 0.43, style: .continuous)

            HStack(spacing: gap) {

                ZStack(alignment: .leading) {

                    silhouette
                        .fill(PluginBatteryPalette.remainder(isLowPowerMode))

                    Rectangle()
                        .fill(PluginBatteryPalette.fill(isLowPowerMode))
                        .frame(width: bodyWidth * fraction)
                }
                .frame(width: bodyWidth, height: height)
                .clipShape(silhouette)
                .overlay {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(height: height * 0.72)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: height * 0.05)
                    }
                }

                Capsule()
                    .fill(PluginBatteryPalette.remainder(isLowPowerMode))
                    .frame(width: terminalWidth, height: height * 0.36)
            }
        }
        .accessibilityHidden(true)
    }
}
