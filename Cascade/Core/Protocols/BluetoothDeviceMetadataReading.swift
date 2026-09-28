//
//  BluetoothDeviceMetadataReading.swift
//  Cascade
//

/// BluetoothDeviceMetadataReading keeps synchronous framework reads behind a
/// Sendable boundary; the enrichment worker always invokes it off the main actor.
nonisolated protocol BluetoothDeviceMetadataReading: Sendable {

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata
}
