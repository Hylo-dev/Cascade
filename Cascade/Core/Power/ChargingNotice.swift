//
//  ChargingNotice.swift
//  Cascade
//

import CascadeKit
import SwiftUI

/// A charger connection is a brief event, not a live activity lasting for the
/// whole charging session. The host owns dismissal and the contextual glow.
@MainActor
final class ChargingNotice: NotchTransientNotice {

    let id                        = "cascade.power.charging"
    let sourceID                  = "cascade.power"
    let privacy                  : NotchActivityPrivacy = .standard
    let displayDuration          : TimeInterval = 4
    let compactPreferredSideWidth: CGFloat? = 116
    let contentRevision          : UInt64

    private let snapshot: MacPowerSnapshot

    var borderAppearance: NotchBorderAppearance? {
        snapshot.isLowPowerMode ? .chargingLowPower : .charging
    }

    var accessibilityLabel: String {
        let battery = snapshot.percentage.map {
            String(localized: "Battery, \($0) percent", table: "ChargingNotice")
        } ?? String(localized: "Battery unavailable", table: "ChargingNotice")
        let lowPower = snapshot.isLowPowerMode
            ? ", " + String(localized: "Low Power Mode", table: "ChargingNotice")
            : ""

        return "\(statusText), \(battery)\(lowPower)"
    }

    init(
        snapshot: MacPowerSnapshot,
        revision: UInt64
    ) {
        self.snapshot   = snapshot
        contentRevision = revision
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(10.0 / 12.0)
                .frame(
                    maxWidth : context.availableSize.width,
                    maxHeight: context.availableSize.height,
                    alignment: .leading
                )
                .help(accessibilityLabel)
                .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        let height = min(12, context.availableSize.height)

        return AnyView(
            HStack(spacing: 6) {

                Text(snapshot.percentage.map { "\($0)%" } ?? "—")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(ChargingNoticePalette.text(snapshot.isLowPowerMode))
                    .lineLimit(1)
                    .minimumScaleFactor(10.0 / 12.0)

                ChargingBatteryIcon(
                    percentage    : snapshot.percentage,
                    isLowPowerMode: snapshot.isLowPowerMode
                )
                .frame(width: height * 2.14, height: height)
            }
            .frame(
                maxWidth : context.availableSize.width,
                maxHeight: context.availableSize.height,
                alignment: .trailing
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        let height = min(12, context.availableSize.height, context.availableSize.width / 2.14)

        return AnyView(
            ChargingBatteryIcon(
                percentage    : snapshot.percentage,
                isLowPowerMode: snapshot.isLowPowerMode
            )
            .frame(width: height * 2.14, height: height)
            .frame(maxWidth: context.availableSize.width, maxHeight: context.availableSize.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    private var statusText: String {
        if snapshot.isCharging { return String(localized: "Charging", table: "ChargingNotice") }
        if snapshot.percentage == 100 { return String(localized: "Charged", table: "ChargingNotice") }
        return String(localized: "Plugged In", table: "ChargingNotice")
    }
}
