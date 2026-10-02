//
//  BluetoothMetadataEnricher.swift
//  CascadeKit
//

import Foundation

/// BluetoothMetadataEnricher reads a device's battery and identity when it connects, and once
/// more after `retryDelay` when the first read came before the device reported them. It owns no
/// periodic timer: the retry is one deferred block, and cancelling a device drops both its read
/// in flight and its retry, so a stop, a wake or a disconnection never publishes a late sample.
///
/// It lives on the Bluetooth source's queue: `enrich` and `cancel` are called there, snapshots
/// are delivered there, and every stored property is read and written only there, which is what
/// makes the type safe to share. The reads themselves, synchronous round trips to bluetoothd and
/// IOKit, run one at a time on a queue of their own, so the source keeps answering callbacks.
final class BluetoothMetadataEnricher: @unchecked Sendable {

    private let reader    : any BluetoothDeviceMetadataReading
    private let queue     : DispatchQueue
    private let retryDelay: DispatchTimeInterval
    private let readQueue  = DispatchQueue(label: "cascade.plugin-host.bluetooth-metadata", qos: .utility)

    private var tokensByID: [String: UInt64] = [:]
    private var nextToken  = UInt64.zero

    init(
        reader    : any BluetoothDeviceMetadataReading,
        queue     : DispatchQueue,
        retryDelay: DispatchTimeInterval = .seconds(1)
    ) {
        self.reader     = reader
        self.queue      = queue
        self.retryDelay = retryDelay
    }

    /// enrich replaces any read pending for the device and hands each snapshot to `onSnapshot`
    /// on the source's queue.
    func enrich(
        deviceID  : String,
        onSnapshot: @escaping @Sendable (BluetoothDeviceMetadata) -> Void
    ) {
        nextToken &+= 1
        tokensByID[deviceID] = nextToken

        read(
            deviceID  : deviceID,
            token     : nextToken,
            isRetry   : false,
            onSnapshot: onSnapshot
        )
    }

    func cancel(deviceID: String) {
        tokensByID[deviceID] = nil
    }

    func cancelAll() {
        tokensByID.removeAll(keepingCapacity: true)
    }

    private func read(
        deviceID  : String,
        token     : UInt64,
        isRetry   : Bool,
        onSnapshot: @escaping @Sendable (BluetoothDeviceMetadata) -> Void
    ) {
        let reader = reader
        readQueue.async { [weak self] in
            let snapshot = reader.metadata(for: deviceID)

            self?.queue.async { [weak self] in
                guard let self, tokensByID[deviceID] == token else { return }

                onSnapshot(snapshot)

                // onSnapshot may have cancelled the device, so the token is checked again.
                guard snapshot.needsRetry, !isRetry, tokensByID[deviceID] == token else {
                    if tokensByID[deviceID] == token {
                        tokensByID[deviceID] = nil
                    }
                    return
                }

                queue.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
                    guard let self, tokensByID[deviceID] == token else { return }

                    read(
                        deviceID  : deviceID,
                        token     : token,
                        isRetry   : true,
                        onSnapshot: onSnapshot
                    )
                }
            }
        }
    }
}
