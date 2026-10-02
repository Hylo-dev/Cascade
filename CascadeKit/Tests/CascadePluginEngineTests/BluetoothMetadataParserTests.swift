//
//  BluetoothMetadataParserTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadePluginHost

/// BluetoothMetadataParserTests are Cascade's battery metadata checks, carried over with the
/// parser into PluginHost: unknown values stay unknown, only the exact address lends a battery,
/// and a verified product identity beats a name.
@Suite
struct BluetoothMetadataParserTests {

    @Test
    func theLowerEarbudSetsTheSummaryAndTheCaseNeverStandsIn() {
        #expect(BluetoothBatterySnapshot(level: 90, left: 72, right: 43, caseLevel: 100).level == 43)
        #expect(BluetoothBatterySnapshot(caseLevel: 80).level == nil)
        #expect(BluetoothBatterySnapshot(level: -1).level == nil)
        #expect(BluetoothBatterySnapshot(level: 101).level == nil)
    }

    @Test
    func onlyExplicitIntegerMeasurementsAreCharges() {
        let invalid: [Any] = [NSNumber(value: Double.nan), NSNumber(value: Double.infinity), true, -1, 255, "85%"]

        for value in invalid {
            #expect(BluetoothMetadataParser.percentage(value) == nil)
        }
        #expect(BluetoothMetadataParser.percentage(NSNumber(value: 0)) == 0)
        #expect(BluetoothMetadataParser.privateBattery(properties: ["batteryPercentSingle": 0]) == nil, "Private getters return zero for devices without a battery")
    }

    @Test
    func onlyTheExactAddressSuppliesARegistryBattery() {
        let records: [[String: Any]] = [
            ["DeviceAddress": "00:11:22:33:44:55", "BatteryPercent": 100],
            ["DeviceAddress": "aa:bb:cc:dd:ee:ff", "BatteryPercentLeft": 61, "BatteryPercentRight": 27],
            ["Product": "AirPods", "BatteryPercent": 99],
        ]

        #expect(BluetoothMetadataParser.registryBattery(records: records, deviceID: "AA-BB-CC-DD-EE-FF")?.level == 27)
        #expect(BluetoothMetadataParser.registryBattery(records: records, deviceID: "invalid") == nil)
    }

    @Test
    func aVerifiedProductSurvivesRenamingAndAForeignVendorGetsNone() {
        let catalog: [(Int, PluginBluetoothDeviceModel)] = [
            (0x2002, .airPods), (0x2013, .airPods), (0x2019, .airPods), (0x201B, .airPods),
            (0x200E, .airPodsPro), (0x2014, .airPodsPro), (0x2024, .airPodsPro), (0x2027, .airPodsPro),
            (0x200A, .airPodsMax), (0x201F, .airPodsMax), (0x202D, .airPodsMax),
        ]

        for (productID, model) in catalog {
            #expect(BluetoothMetadataParser.deviceModel(vendorID: 76, productID: productID, productName: "Renamed") == model)
        }
        #expect(BluetoothMetadataParser.deviceModel(vendorID: 99, productID: 0x2002, productName: "AirPods Pro") == .generic)
        #expect(BluetoothMetadataParser.deviceModel(vendorID: 76, productID: nil, productName: "My AirPods Max") == .airPodsMax)
    }

    @Test
    func theExactAppleProductIDIsKeptAndAnythingElseIsUnknown() {
        #expect(BluetoothMetadataParser.appleProductID(vendorID: 76, productID: 0x2013) == 0x2013)

        for (vendorID, productID) in [(99, 0x2013), (76, 0), (76, -1), (76, 65_536)] {
            #expect(BluetoothMetadataParser.appleProductID(vendorID: vendorID, productID: productID) == nil)
        }
    }

    @Test
    func aDeviceSnapshotKeepsKnownFieldsWhenSparseMetadataOmitsThem() {
        let known = BluetoothConnectedDevice(
            deviceID  : "AA-BB-CC-DD-EE-FF",
            name      : "AirPods",
            symbolName: "airpods",
            battery   : BluetoothBatterySnapshot(left: 40, right: 50, caseLevel: 90),
            model     : .airPods,
            productID : 0x2013,
            colorID   : 2
        )

        let enriched = known.enriched(with: BluetoothDeviceMetadata(battery: BluetoothBatterySnapshot(left: 38)))

        #expect(enriched.battery == BluetoothBatterySnapshot(left: 38, right: 50, caseLevel: 90))
        #expect(enriched.model == .airPods && enriched.productID == 0x2013 && enriched.colorID == 2)
    }
}
