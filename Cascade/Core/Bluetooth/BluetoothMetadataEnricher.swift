//
//  BluetoothMetadataEnricher.swift
//  Cascade
//

import Foundation

/// BluetoothMetadataEnricher performs a connection-triggered read and at most
/// one retry. It owns no periodic timer and cancels pending delivery on lifecycle changes.
@MainActor
final class BluetoothMetadataEnricher {

    private let reader    : any BluetoothDeviceMetadataReading
    private let retryDelay: Duration
    private var tasksByID : [String: Task<Void, Never>] = [:]
    private var tokensByID: [String: UUID] = [:]

    init(
        reader    : any BluetoothDeviceMetadataReading = SystemBluetoothDeviceMetadataReader(),
        retryDelay: Duration = .seconds(1)
    ) {
        self.reader     = reader
        self.retryDelay = retryDelay
    }

    /// enrich sends immutable snapshots to the main actor while framework objects
    /// are created, used and released entirely inside the detached read operation.
    func enrich(
        deviceID  : String,
        onSnapshot: @escaping @MainActor @Sendable (BluetoothDeviceMetadata) -> Void
    ) {
        cancel(deviceID: deviceID)
        let token = UUID()
        tokensByID[deviceID] = token
        let reader = reader
        let retryDelay = retryDelay
        tasksByID[deviceID] = Task { [weak self] in
            defer {
                if self?.tokensByID[deviceID] == token {
                    self?.tasksByID[deviceID] = nil
                    self?.tokensByID[deviceID] = nil
                }
            }
            for attempt in 0..<2 {
                guard !Task.isCancelled else { return }
                if attempt > 0 {
                    do { try await Task.sleep(for: retryDelay) } catch { return }
                }
                guard !Task.isCancelled else { return }
                let snapshot = await Task.detached(priority: .utility) {
                    reader.metadata(for: deviceID)
                }.value
                guard !Task.isCancelled, self?.tokensByID[deviceID] == token else { return }
                onSnapshot(snapshot)
                guard snapshot.needsRetry else { return }
            }
        }
    }

    /// cancel prevents in-flight results and the delayed retry from being published.
    func cancel(deviceID: String) {
        tasksByID.removeValue(forKey: deviceID)?.cancel()
        tokensByID[deviceID] = nil
    }

    /// cancelAll is used by stop and silent baseline replacement.
    func cancelAll() {
        for task in tasksByID.values { task.cancel() }
        tasksByID.removeAll(keepingCapacity: true)
        tokensByID.removeAll(keepingCapacity: true)
    }

    isolated deinit {
        for task in tasksByID.values { task.cancel() }
    }
}
