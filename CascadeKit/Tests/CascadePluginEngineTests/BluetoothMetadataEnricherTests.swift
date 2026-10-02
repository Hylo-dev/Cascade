//
//  BluetoothMetadataEnricherTests.swift
//  CascadeKit
//

import Foundation
import Synchronization
import Testing

@testable import CascadePluginHost

/// BluetoothMetadataEnricherTests check the connection-triggered read: at most one retry, off
/// the source's queue and never on the main thread, and nothing delivered once cancelled.
@Suite
struct BluetoothMetadataEnricherTests {

    private let queue    = DispatchQueue(label: "cascade.tests.bluetooth-enricher")
    private let complete = BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(level: 64))

    @Test
    func aLateBatteryArrivesWithOneBoundedRetry() async throws {
        let reader    = MetadataReaderProbe(samples: [BluetoothDeviceMetadata(), complete])
        let enricher  = BluetoothMetadataEnricher(reader: reader, queue: queue, retryDelay: .milliseconds(1))
        let snapshots = Mutex<[BluetoothDeviceMetadata]>([])
        queue.sync {
            enricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { snapshot in snapshots.withLock { $0.append(snapshot) } }
        }

        #expect(try await eventually { snapshots.withLock { $0.count } == 2 })
        try await Task.sleep(for: .milliseconds(20))

        #expect(snapshots.withLock { $0.map(\.battery?.level) } == [nil, 64])
        #expect(reader.readCount == 2)
        #expect(!reader.didReadOnMainThread)
    }

    @Test
    func cancellingSuppressesTheDelayedRetry() async throws {
        let reader   = MetadataReaderProbe(samples: [BluetoothDeviceMetadata(), complete])
        let enricher = BluetoothMetadataEnricher(reader: reader, queue: queue, retryDelay: .milliseconds(30))
        let received = Mutex(0)
        queue.sync {
            enricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { _ in
                received.withLock { $0 += 1 }
                enricher.cancelAll()
            }
        }

        #expect(try await eventually { received.withLock { $0 } == 1 })
        try await Task.sleep(for: .milliseconds(80))

        #expect(reader.readCount == 1)
        #expect(received.withLock { $0 } == 1)
    }

    @Test
    func aCompleteMeasurementNeedsNoRetry() async throws {
        let reader   = MetadataReaderProbe(samples: [complete])
        let enricher = BluetoothMetadataEnricher(reader: reader, queue: queue, retryDelay: .milliseconds(1))
        let received = Mutex(0)
        queue.sync {
            enricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { _ in received.withLock { $0 += 1 } }
        }

        #expect(try await eventually { received.withLock { $0 } == 1 })
        try await Task.sleep(for: .milliseconds(20))

        #expect(reader.readCount == 1)
    }

    @Test
    func aReadInFlightForACancelledDeviceIsDropped() async throws {
        let reader   = MetadataReaderProbe(samples: [complete], delay: 0.03)
        let enricher = BluetoothMetadataEnricher(reader: reader, queue: queue, retryDelay: .milliseconds(1))
        let received = Mutex(0)
        queue.sync {
            enricher.enrich(deviceID: "AA-BB-CC-DD-EE-FF") { _ in received.withLock { $0 += 1 } }
            enricher.cancel(deviceID: "AA-BB-CC-DD-EE-FF")
        }

        // A sleeping utility thread may be woken late, so the read is awaited, not timed.
        #expect(try await eventually { reader.readCount == 1 })
        try await Task.sleep(for: .milliseconds(30))

        #expect(received.withLock { $0 } == 0)
    }
}

/// MetadataReaderProbe hands out its samples in order and records where it was read.
private final class MetadataReaderProbe: BluetoothDeviceMetadataReading {

    private struct Record {

        var count          = 0
        var mainThreadRead = false
    }

    private let samples: [BluetoothDeviceMetadata]
    private let delay  : TimeInterval
    private let record = Mutex(Record())

    init(
        samples: [BluetoothDeviceMetadata],
        delay  : TimeInterval = 0
    ) {
        self.samples = samples
        self.delay   = delay
    }

    var readCount: Int {
        record.withLock { $0.count }
    }

    var didReadOnMainThread: Bool {
        record.withLock { $0.mainThreadRead }
    }

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata {
        Thread.sleep(forTimeInterval: delay)

        return record.withLock { record in
            record.mainThreadRead = record.mainThreadRead || Thread.isMainThread
            defer { record.count += 1 }

            return samples[min(record.count, samples.count - 1)]
        }
    }
}
