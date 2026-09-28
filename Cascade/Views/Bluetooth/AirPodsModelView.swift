//
//  AirPodsModelView.swift
//  Cascade
//

import AppKit
import SwiftUI

/// Apple's own installed banner artwork, selected by verified product and
/// color IDs. A bounded contents animation requires no player, display link or
/// per-frame SwiftUI updates. Only a small poster survives the single turn.
struct AirPodsModelView: View {

    let model             : BluetoothDeviceModel
    let productID         : UInt16?
    let colorID           : UInt8?
    let fallbackSymbolName: String?

    init(
        model             : BluetoothDeviceModel,
        productID         : UInt16? = nil,
        colorID           : UInt8?  = nil,
        fallbackSymbolName: String? = nil
    ) {
        self.model              = model
        self.productID          = productID
        self.colorID            = colorID
        self.fallbackSymbolName = fallbackSymbolName
    }

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

    let model             : BluetoothDeviceModel
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
