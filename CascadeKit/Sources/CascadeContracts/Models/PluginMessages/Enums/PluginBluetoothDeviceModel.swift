//
//  PluginBluetoothDeviceModel.swift
//  CascadeKit
//

/// PluginBluetoothDeviceModel is the product family the system verified for a Bluetooth device.
/// `generic` is every device whose identity the system does not expose, so the notice shows its
/// class symbol instead of claiming a model it cannot prove.
public enum PluginBluetoothDeviceModel: String, Codable, Hashable, Sendable {

    case generic
    case airPods
    case airPodsPro
    case airPodsMax
}
