//
//  CoreAudioBluetoothRouteSource.swift
//  Cascade
//

import AppKit
import CoreAudio
import notify
import Foundation
import os

/// Public HAL listener plus a read-only Smart Routing notification hint. The
/// Darwin notification carries no identity: it can only trigger the same HAL
/// snapshot and cannot manufacture a connection when the output is unchanged.
nonisolated final class CoreAudioBluetoothRouteSource: BluetoothAudioRouteSource {
    private let queue: DispatchQueue
    private var listener: AudioObjectPropertyListenerBlock?
    private var routingToken: Int32?

    init(queue: DispatchQueue) { self.queue = queue }

    func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        stop()
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
        ) == noErr else { return false }
        self.listener = listener
        var token: Int32 = 0
        if notify_register_dispatch("com.apple.BluetoothServices.AudioRoutingChanged", &token, queue, { _ in
            onChange()
        }) == NOTIFY_STATUS_OK {
            routingToken = token
        }
        return true
    }

    func snapshot() -> BluetoothAudioRouteReadResult {
        guard let deviceID = readUInt32(
            AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice
        ) else { return .unavailable }
        guard deviceID != kAudioObjectUnknown else { return .noOutput }
        guard let uid = readString(deviceID, selector: kAudioDevicePropertyDeviceUID),
              let transport = readUInt32(deviceID, selector: kAudioDevicePropertyTransportType) else { return .unavailable }
        let name = readString(deviceID, selector: kAudioObjectPropertyName) ?? "Bluetooth Device"
        return .output(BluetoothAudioRouteSnapshot(uid: uid, name: name, transportType: transport))
    }

    func stop() {
        if let listener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
            )
            self.listener = nil
        }
        if let routingToken { notify_cancel(routingToken) }
        routingToken = nil
    }

    private func readUInt32(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<UInt32>.size else { return nil }
        return value
    }

    private func readString(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        // HAL's UID/name CFString properties transfer ownership to the caller.
        let storage = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        storage.initialize(to: nil)
        defer { storage.deinitialize(count: 1); storage.deallocate() }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, storage) == noErr,
              let value = storage.pointee?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
    }
}
