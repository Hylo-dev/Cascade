//
//  BluetoothConnectionActivity.swift
//  Cascade
//

import CascadeKit
import SwiftUI

/// BluetoothConnectionActivity presents one completed accessory state change.
/// The device identity coalesces enrichment of the same connection event. Its
/// monotonic sample revision lets late battery data reach the visible notice
/// without introducing a second connection notification.
@MainActor
final class BluetoothConnectionActivity: NotchTransientNotice {

    let id                       : String
    let sourceID                  = "cascade.bluetooth"
    let contentRevision          : UInt64
    let privacy                  : NotchActivityPrivacy   = .standard
    let compactPreferredSideWidth: CGFloat?               = 40
    let displayDuration          : TimeInterval           = 4
    let borderAppearance         : NotchBorderAppearance? = .neutral

    var accessibilityLabel: String {
        "\(event.name), \(stateText), \(batteryDescription)"
    }

    private let event: BluetoothConnectionEvent

    init(event: BluetoothConnectionEvent) {
        self.event      = event
        id              = "cascade.bluetooth.\(event.deviceID)"
        contentRevision = event.revision
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        let symbolSize  = min(14, context.availableSize.height, context.availableSize.width)
        let artworkSize = min(20, context.availableSize.height, context.availableSize.width)

        return AnyView(
            Group {

                if event.model != .generic || event.productID != nil {
                    AirPodsModelView(
                        model             : event.model,
                        productID         : event.productID,
                        colorID           : event.colorID,
                        fallbackSymbolName: event.symbolName
                    )
                    .frame(width: artworkSize, height: artworkSize)
                } else {
                    Image(systemName: event.symbolName)
                        .font(.system(size: symbolSize, weight: .regular))
                        .frame(width: artworkSize)
                }
            }
            .foregroundStyle(.white)
            .frame(
                maxWidth : context.availableSize.width,
                maxHeight: context.availableSize.height,
                alignment: .center
            )
            .help(accessibilityLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            BluetoothBatteryRing(
                level      : context.isStale ? nil : event.battery?.level,
                diameter   : min(18, context.availableSize.height, context.availableSize.width),
                isConnected: event.isConnected
            )
            .frame(
                maxWidth : context.availableSize.width,
                maxHeight: context.availableSize.height,
                alignment: .center
            )
            .help(accessibilityLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        return AnyView(
            BluetoothBatteryRing(
                level      : context.isStale ? nil : event.battery?.level,
                diameter   : min(18, context.availableSize.height, context.availableSize.width),
                isConnected: event.isConnected
            )
            .frame(
                maxWidth : context.availableSize.width,
                maxHeight: context.availableSize.height
            )
            .help(accessibilityLabel)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    private var stateText: String {
        guard event.isConnected else {
            return String(localized: "Disconnected", table: "BluetoothNotice")
        }

        switch event.kind {
            case .connection:
                return String(localized: "Connected", table: "BluetoothNotice")
            case .audioRoute:
                return String(localized: "Audio on Mac", table: "BluetoothNotice")
        }
    }

    private var batteryDescription: String {
        guard event.isConnected, let battery = event.battery, let level = battery.level else {
            return String(localized: "Battery unavailable", table: "BluetoothNotice")
        }

        var descriptions = [String(localized: "Battery, \(level) percent", table: "BluetoothNotice")]
        if let left = battery.left {
            descriptions.append(String(localized: "Left, \(left) percent", table: "BluetoothNotice"))
        }
        if let right = battery.right {
            descriptions.append(String(localized: "Right, \(right) percent", table: "BluetoothNotice"))
        }
        if let caseLevel = battery.caseLevel {
            descriptions.append(String(localized: "Case, \(caseLevel) percent", table: "BluetoothNotice"))
        }

        return descriptions.joined(separator: ", ")
    }
}
