//
//  BluetoothMonitorTestSupport.swift
//  Cascade
//

#if BLUETOOTH_MONITOR_TESTS
import Foundation

enum BluetoothMonitorTestFailure: Error, CustomStringConvertible {

    case assertion(String)

    var description: String {
        switch self {
            case .assertion(let message):
                return message
        }
    }
}

func expectBluetoothMonitorBehavior(
    _ condition: @autoclosure () -> Bool,
    _ message  : String
) throws {
    guard condition() else { throw BluetoothMonitorTestFailure.assertion(message) }
}

@main
enum BluetoothMonitorTestMain {

    @MainActor
    static func main() async throws {
        try BluetoothConnectionReducerTests.run()
        try BluetoothBatteryMetadataTests.run()
        try await BluetoothMetadataEnricherTests.run()
        try await BluetoothMonitorLifecycleTests.run()
        print("Bluetooth monitor tests: reducer, metadata, enrichment and lifecycle checks passed")
    }
}

#endif
