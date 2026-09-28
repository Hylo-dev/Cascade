//
//  BluetoothMetadataEnricherTests.swift
//  Cascade
//

#if BLUETOOTH_MONITOR_TESTS
import Foundation

/// BluetoothMetadataEnricherTests verifies the bounded event-driven reader lifecycle.
enum BluetoothMetadataEnricherTests {

    static func run() async throws {
        let complete = BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64))
        let reader = BluetoothMetadataReaderProbe(samples: [BluetoothDeviceMetadata(), complete])
        let enricher = BluetoothMetadataEnricher(reader: reader, retryDelay: .milliseconds(1))
        let stream = AsyncStream<BluetoothDeviceMetadata>.makeStream()
        enricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { stream.continuation.yield($0) }
        var iterator = stream.stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        try expectBluetoothMonitorBehavior(
            first?.battery == nil && second?.battery?.level == 64,
            "A late battery report must be delivered by one bounded retry."
        )
        try await Task.sleep(for: .milliseconds(10))
        try expectBluetoothMonitorBehavior(
            reader.readCount == 2 && !reader.didReadOnMainThread,
            "Metadata must use at most two background reads per connection."
        )
        enricher.cancelAll()

        let cancelledReader = BluetoothMetadataReaderProbe(samples: [BluetoothDeviceMetadata(), complete])
        let cancelledEnricher = BluetoothMetadataEnricher(reader: cancelledReader, retryDelay: .milliseconds(30))
        let cancelledStream = AsyncStream<BluetoothDeviceMetadata>.makeStream()
        cancelledEnricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { snapshot in
            cancelledStream.continuation.yield(snapshot)
            cancelledEnricher.cancelAll()
        }
        var cancelledIterator = cancelledStream.stream.makeAsyncIterator()
        _ = await cancelledIterator.next()
        try await Task.sleep(for: .milliseconds(60))
        try expectBluetoothMonitorBehavior(
            cancelledReader.readCount == 1,
            "Stop, wake or disconnect cancellation must suppress the delayed retry."
        )

        let completeReader = BluetoothMetadataReaderProbe(samples: [complete])
        let completeEnricher = BluetoothMetadataEnricher(reader: completeReader, retryDelay: .milliseconds(1))
        let completeStream = AsyncStream<BluetoothDeviceMetadata>.makeStream()
        completeEnricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { completeStream.continuation.yield($0) }
        var completeIterator = completeStream.stream.makeAsyncIterator()
        _ = await completeIterator.next()
        try await Task.sleep(for: .milliseconds(10))
        try expectBluetoothMonitorBehavior(
            completeReader.readCount == 1,
            "A complete measurement must not schedule an unnecessary retry."
        )
        completeEnricher.cancelAll()
    }
}

/// BluetoothMetadataReaderProbe protects its small test record across detached reads.
nonisolated private final class BluetoothMetadataReaderProbe: BluetoothDeviceMetadataReading, @unchecked Sendable {
    private let lock = NSLock()
    private let samples: [BluetoothDeviceMetadata]
    private var count = 0
    private var mainThreadRead = false

    init(samples: [BluetoothDeviceMetadata]) {
        self.samples = samples
    }

    var readCount: Int { lock.withLock { count } }
    var didReadOnMainThread: Bool { lock.withLock { mainThreadRead } }

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata {
        lock.withLock {
            mainThreadRead = mainThreadRead || Thread.isMainThread
            let sample = samples[min(count, samples.count - 1)]
            count += 1
            return sample
        }
    }
}

#endif
