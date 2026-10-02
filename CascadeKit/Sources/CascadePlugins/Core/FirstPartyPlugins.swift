//
//  FirstPartyPlugins.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// FirstPartyPlugins lists the plugins Cascade ships. PluginHost serves their providers by entry
/// point, and Cascade registers their manifests, which are bundled as JSON and validated by the
/// tests with the same rules `cascade-addon validate` applies, so a broken manifest never ships.
public enum FirstPartyPlugins {

    public static let providers: [String: any PluginProvider] = [
        "BatteryPlugin"  : BatteryPlugin(),
        "BluetoothPlugin": BluetoothPlugin(),
        "ChargingPlugin" : ChargingPlugin(),
        "ClockPlugin"    : ClockPlugin(),
        "VolumePlugin"   : VolumePlugin(),
        "ScreenRecordingPlugin": ScreenRecordingPlugin(),
    ]

    /// name is how settings call a bundled plugin, in the user's language. Manifests carry no
    /// names, so the first-party ones live here, beside the plugins they name; an unknown id
    /// reads as itself.
    public static func name(of plugin: PluginID) -> String {
        switch plugin.rawValue {
            case "com.cascade.battery"  : String(localized: "Battery", table: "Plugins", bundle: .module)
            case "com.cascade.bluetooth": String(localized: "Bluetooth alerts", table: "Plugins", bundle: .module)
            case "com.cascade.clock"    : String(localized: "Clock", table: "Plugins", bundle: .module)
            case "com.cascade.power"    : String(localized: "Charging alerts", table: "Plugins", bundle: .module)
            case "com.cascade.volume"   : String(localized: "Volume alerts", table: "Plugins", bundle: .module)
            case "com.cascade.screen-recording": String(localized: "Screen Recording", table: "Plugins", bundle: .module)
            default                     : plugin.rawValue
        }
    }

    /// manifests decodes every bundled manifest, in a stable order. One that fails validation
    /// can only be a broken bundle, since the tests decode them all, and is left out.
    public static func manifests() -> [PluginManifest] {
        (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in try? PluginManifest.decode(Data(contentsOf: url)) }
    }
}
