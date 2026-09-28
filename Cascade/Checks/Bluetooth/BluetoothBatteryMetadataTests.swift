//
//  BluetoothBatteryMetadataTests.swift
//  Cascade
//

#if BLUETOOTH_MONITOR_TESTS
import Foundation

/// BluetoothBatteryMetadataTests exercises unknown values, source identity and late enrichment.
enum BluetoothBatteryMetadataTests {

    static func run() throws {
        let earbuds = BluetoothBatterySnapshot(
            level    : 90,
            left     : 72,
            right    : 43,
            caseLevel: 100
        )
        try expectBluetoothMonitorBehavior(earbuds.level == 43, "The lower known earbud must set the summary.")
        try expectBluetoothMonitorBehavior(
            BluetoothBatterySnapshot(caseLevel: 80).level == nil,
            "The case must never masquerade as the headphone battery."
        )
        try expectBluetoothMonitorBehavior(
            BluetoothBatterySnapshot(level: -1).level == nil && BluetoothBatterySnapshot(level: 101).level == nil,
            "Out-of-range measurements must remain unknown."
        )
        for invalid: Any in [NSNumber(value: Double.nan), NSNumber(value: Double.infinity), true, -1, 255, "85%"] {
            try expectBluetoothMonitorBehavior(
                BluetoothMetadataParser.percentage(invalid) == nil,
                "Invalid, nonnumeric, boolean or sentinel measurements must be rejected."
            )
        }
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.percentage(NSNumber(value: 0)) == 0,
            "An explicit zero registry measurement must be preserved."
        )
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.privateBattery(properties: ["batteryPercentSingle": 0]) == nil,
            "Private zero getters are also returned for devices without battery support."
        )
        let deviceID = "AA-BB-CC-DD-EE-FF"
        let records: [[String: Any]] = [
            ["DeviceAddress": "00:11:22:33:44:55", "BatteryPercent": 100],
            ["DeviceAddress": "aa:bb:cc:dd:ee:ff", "BatteryPercentLeft": 61, "BatteryPercentRight": 27],
            ["Product": "AirPods", "BatteryPercent": 99]
        ]
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.registryBattery(records: records, deviceID: deviceID)?.level == 27,
            "Only the exact normalized Bluetooth address can supply a battery."
        )
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.registryBattery(records: records, deviceID: "invalid") == nil,
            "Invalid addresses cannot match anonymous records."
        )
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.deviceModel(vendorID: 76, productID: 0x2002, productName: "Renamed") == .airPods,
            "Verified hardware identity must survive renaming."
        )
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.deviceModel(vendorID: 99, productID: 0x2002, productName: "AirPods Pro") == .generic,
            "A foreign vendor must not inherit Apple's product identity or its name hint."
        )
        for (productID, model) in [(0x200A, BluetoothDeviceModel.airPodsMax), (0x200E, .airPodsPro),
                                   (0x2014, .airPodsPro), (0x2024, .airPodsPro)] {
            try expectBluetoothMonitorBehavior(
                BluetoothMetadataParser.deviceModel(vendorID: 76, productID: productID, productName: "Renamed") == model,
                "Known Pro and Max product IDs must survive device renaming."
            )
        }
        for (productID, model) in [(0x2013, BluetoothDeviceModel.airPods), (0x2019, .airPods),
                                   (0x201B, .airPods), (0x2027, .airPodsPro),
                                   (0x201F, .airPodsMax), (0x202D, .airPodsMax)] {
            try expectBluetoothMonitorBehavior(
                BluetoothMetadataParser.deviceModel(vendorID: 76, productID: productID, productName: "Renamed") == model,
                "Installed Apple product catalogs must identify newer AirPods families without a name hint."
            )
        }
        try exactProductIdentitySurvivesEnrichment()
        try enrichmentKeepsIdentityAndRetainedMetadata()
    }


    private static func exactProductIdentitySurvivesEnrichment() throws {
        try expectBluetoothMonitorBehavior(
            BluetoothMetadataParser.appleProductID(vendorID: 76, productID: 0x2013) == 0x2013,
            "The actual Apple product ID must remain exact rather than becoming a family representative."
        )
        for (vendorID, productID) in [(99, 0x2013), (76, 0), (76, -1), (76, 65_536)] {
            try expectBluetoothMonitorBehavior(
                BluetoothMetadataParser.appleProductID(vendorID: vendorID, productID: productID) == nil,
                "Foreign vendor, missing and overflowing product IDs cannot resolve Apple artwork."
            )
        }
        var reducer = BluetoothConnectionReducer()
        let device = BluetoothConnectedDevice(
            deviceID  : "AA-BB-CC-DD-EE-FF",
            name      : "Renamed",
            symbolName: "headphones"
        )
        _ = reducer.recordConnection(device, eventID: 29)
        let metadata = BluetoothDeviceMetadata(
            productID: 0x201F,
            colorID  : 19
        )
        let update = reducer.enrichConnection(deviceID: device.deviceID, eventID: 29, metadata: metadata)
        try expectBluetoothMonitorBehavior(
            update?.productID == 0x201F && update?.colorID == 19 && update?.revision == 1,
            "Product and color arriving without a battery must still revise the original event."
        )
        try expectBluetoothMonitorBehavior(
            reducer.enrichConnection(deviceID: device.deviceID, eventID: 29, metadata: metadata) == nil,
            "Identical product and color metadata must not cause redundant revisions."
        )
        _ = reducer.recordConnection(device)
        let disconnected = reducer.recordDisconnection(deviceID: device.deviceID)
        try expectBluetoothMonitorBehavior(
            disconnected?.productID == 0x201F && disconnected?.colorID == 19,
            "Sparse duplicate callbacks must retain exact hardware identity through disconnect."
        )
        let reconnected = reducer.recordConnection(device, eventID: 30)
        try expectBluetoothMonitorBehavior(
            reconnected?.productID == nil && reconnected?.colorID == nil,
            "A new connection must not silently reuse identity from an expired metadata sample."
        )
    }

    private static func enrichmentKeepsIdentityAndRetainedMetadata() throws {
        var reducer = BluetoothConnectionReducer()
        let device = BluetoothConnectedDevice(
            deviceID  : "AA-BB-CC-DD-EE-FF",
            name      : "Headphones",
            symbolName: "headphones"
        )
        let initial = reducer.recordConnection(device, eventID: 12)
        let metadata = BluetoothDeviceMetadata(
            battery: BluetoothBatterySnapshot(left: 58, right: 32),
            model  : .airPodsPro
        )
        let update = reducer.enrichConnection(deviceID: device.deviceID, eventID: 12, metadata: metadata)
        try expectBluetoothMonitorBehavior(
            update?.eventID == initial?.eventID && update?.revision == 1 && update?.battery?.level == 32,
            "Late measurements must update the original event identity and advance its revision."
        )
        try expectBluetoothMonitorBehavior(
            reducer.enrichConnection(deviceID: device.deviceID, eventID: 12, metadata: metadata) == nil,
            "Identical metadata must not issue a new content revision."
        )
        _ = reducer.recordConnection(device)
        var sparseCopy = reducer
        try expectBluetoothMonitorBehavior(
            sparseCopy.recordDisconnection(deviceID: device.deviceID)?.battery?.level == 32,
            "A duplicate sparse callback must preserve the last measured battery."
        )
        let refreshed = BluetoothConnectedDevice(
            deviceID  : device.deviceID,
            name      : device.name,
            symbolName: device.symbolName,
            battery   : BluetoothBatterySnapshot(left: 58, right: 18),
            model     : .airPodsPro
        )
        _ = reducer.recordConnection(refreshed)
        let disconnected = reducer.recordDisconnection(deviceID: device.deviceID)
        try expectBluetoothMonitorBehavior(
            disconnected?.battery?.level == 18 && disconnected?.model == .airPodsPro,
            "A duplicate callback must retain missing metadata but accept a newer measured battery."
        )
        _ = reducer.recordConnection(device, eventID: 13)
        try expectBluetoothMonitorBehavior(
            reducer.enrichConnection(deviceID: device.deviceID, eventID: 12, metadata: metadata) == nil,
            "A late sample from a prior connection must not mutate a reconnect."
        )
        reducer.replaceBaseline(with: [device])
        try expectBluetoothMonitorBehavior(
            reducer.enrichConnection(deviceID: device.deviceID, eventID: 13, metadata: metadata) == nil,
            "Wake baselines must never replay a metadata update as a new connection."
        )
    }
}

#endif
