//
//  PluginBluetoothDeviceComponent.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

/// PluginBluetoothDeviceComponent is the tier-2 component bluetooth.device: Apple's own installed
/// banner artwork for an AirPods model, chosen by its verified product and colour, falling back
/// to the device's SF Symbol. It plays one bounded Core Animation turn, with no player, display
/// link or per-frame SwiftUI update, and keeps only a small poster afterwards.
struct PluginBluetoothDeviceComponent: View {

    let model             : PluginBluetoothDeviceModel
    let productID         : UInt16?
    let colorID           : UInt8?
    let fallbackSymbolName: String?

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        AirPodsTurntableRepresentable(
            model             : model,
            productID         : productID,
            colorID           : colorID,
            fallbackSymbolName: fallbackSymbolName,
            allowsAnimation   : !reduceMotion
        )
        .accessibilityHidden(true)
    }
}

private struct AirPodsTurntableRepresentable: NSViewRepresentable {

    let model             : PluginBluetoothDeviceModel
    let productID         : UInt16?
    let colorID           : UInt8?
    let fallbackSymbolName: String?
    let allowsAnimation   : Bool

    func makeNSView(context: Context) -> AirPodsTurntableSurface {
        AirPodsTurntableSurface()
    }

    func updateNSView(
        _ view : AirPodsTurntableSurface,
        context: Context
    ) {
        view.configure(
            model             : model,
            productID         : productID,
            colorID           : colorID,
            fallbackSymbolName: fallbackSymbolName,
            allowsAnimation   : allowsAnimation,
            isActive          : true
        )
    }

    static func dismantleNSView(
        _ view     : AirPodsTurntableSurface,
        coordinator: ()
    ) {
        view.releaseResources()
    }
}
