//
//  BluetoothDeviceModel.swift
//  Cascade
//



/// BluetoothDeviceModel selects a verified product family while retaining a
/// neutral fallback for hardware whose identity the system does not expose.
nonisolated enum BluetoothDeviceModel: Equatable, Sendable {
    case generic
    case airPods
    case airPodsPro
    case airPodsMax
}
