//
//  PluginBluetoothBattery.swift
//  CascadeKit
//

/// PluginBluetoothBattery is what a Bluetooth device measured of its charge: a summary, each
/// earbud and the case, each a percentage or unknown. The source decides the summary (the lower
/// earbud, never the case), so this value only keeps every number within the battery.
public struct PluginBluetoothBattery: Equatable, Sendable {

    public let level    : Int?
    public let left     : Int?
    public let right    : Int?
    public let caseLevel: Int?

    public init(
        level    : Int?,
        left     : Int?,
        right    : Int?,
        caseLevel: Int?
    ) {
        self.level     = level.map { min(100, max(0, $0)) }
        self.left      = left.map { min(100, max(0, $0)) }
        self.right     = right.map { min(100, max(0, $0)) }
        self.caseLevel = caseLevel.map { min(100, max(0, $0)) }
    }
}
