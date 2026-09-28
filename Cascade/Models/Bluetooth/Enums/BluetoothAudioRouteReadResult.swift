//
//  BluetoothAudioRouteReadResult.swift
//  Cascade
//

/// BluetoothAudioRouteReadResult keeps a transient HAL read error from looking like a physical
/// route departure.
nonisolated enum BluetoothAudioRouteReadResult: Equatable, Sendable {

    case output(BluetoothAudioRouteSnapshot)
    case noOutput
    case unavailable
}
