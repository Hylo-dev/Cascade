//
//  BluetoothDeviceMetadataReading.swift
//  CascadeKit
//

/// BluetoothDeviceMetadataReading keeps synchronous framework reads behind a
/// Sendable boundary; the enricher always invokes it on its own read queue.
protocol BluetoothDeviceMetadataReading: Sendable {

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata
}
