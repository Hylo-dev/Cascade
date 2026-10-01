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
        "BatteryPlugin" : BatteryPlugin(),
        "ChargingPlugin": ChargingPlugin(),
        "ClockPlugin"   : ClockPlugin(),
    ]

    /// manifests decodes every bundled manifest, in a stable order. One that fails validation
    /// can only be a broken bundle, since the tests decode them all, and is left out.
    public static func manifests() -> [PluginManifest] {
        (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in try? PluginManifest.decode(Data(contentsOf: url)) }
    }
}
