//
//  BluetoothNoticeSnapshot.swift
//  Cascade
//

/// BluetoothNoticeSnapshot contains only the bounded candidate window's matching data.
nonisolated struct BluetoothNoticeSnapshot: Sendable {

    let ownerBundleID          : String
    let texts                  : [String]
    let isModal                : Bool
    let hasInteractiveControls : Bool
    let closeButtonCount       : Int
    let isComplete             : Bool
    let isFloatingWindow       : Bool
    let width                  : Double
    let height                 : Double
    var bannerIdentifier       : String? = nil
    var dismissButtonIdentifier: String? = nil
}
