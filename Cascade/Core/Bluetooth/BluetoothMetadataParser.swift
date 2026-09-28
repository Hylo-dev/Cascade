//
//  BluetoothMetadataParser.swift
//  Cascade
//

import Foundation

/// BluetoothMetadataParser isolates validation and exact-address selection
/// from IOKit and private API availability so absent data stays absent.
nonisolated enum BluetoothMetadataParser {

    /// percentage accepts explicit integer measurements, excluding CFBoolean,
    /// floating-point failures and the private API's 255 unknown sentinel.
    static func percentage(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, (0...100).contains(value), value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    /// normalizedAddress refuses partial identifiers, names and malformed addresses.
    static func normalizedAddress(_ address: String) -> String? {
        let compact = address.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard compact.count == 12, compact.unicodeScalars.allSatisfy({
            (48...57).contains($0.value) || (65...70).contains($0.value)
        }) else { return nil }
        return compact
    }

    /// privateBattery treats zero as unavailable because these getters return
    /// zero for unsupported devices and sleeping components as well as exhaustion.
    /// IORegistry's explicit measurements use a separate path that preserves zero.
    static func privateBattery(properties: [String: Any]) -> BluetoothBatterySnapshot? {
        func positivePercentage(_ key: String) -> Int? {
            guard let value = percentage(properties[key]), value > 0 else { return nil }
            return value
        }
        let battery = BluetoothBatterySnapshot(
            level    : positivePercentage("batteryPercentSingle"),
            left     : positivePercentage("batteryPercentLeft"),
            right    : positivePercentage("batteryPercentRight"),
            caseLevel: positivePercentage("batteryPercentCase")
        )
        return battery.hasMeasurement ? battery : nil
    }

    /// registryBattery matches addresses before inspecting charge; a product
    /// name or nearby registry entry can never lend its battery to another device.
    static func registryBattery(
        records : [[String: Any]],
        deviceID: String
    ) -> BluetoothBatterySnapshot? {
        guard let expectedAddress = normalizedAddress(deviceID) else { return nil }
        var result: BluetoothBatterySnapshot?
        for record in records {
            let addresses = ["DeviceAddress", "BluetoothDeviceAddress", "BD_ADDR", "SerialNumber"]
                .compactMap { record[$0] as? String }
            guard addresses.contains(where: { normalizedAddress($0) == expectedAddress }) else { continue }
            let battery = BluetoothBatterySnapshot(
                level    : percentage(record["BatteryPercent"]),
                left     : percentage(record["BatteryPercentLeft"]),
                right    : percentage(record["BatteryPercentRight"]),
                caseLevel: percentage(record["BatteryPercentCase"])
            )
            guard battery.hasMeasurement else { continue }
            result = result?.fillingMissing(from: battery) ?? battery
        }
        return result
    }

    /// appleProductID preserves the device-reported generation only for Apple's
    /// Bluetooth or USB vendor identity. A family or display name never invents an ID.
    static func appleProductID(
        vendorID : Int?,
        productID: Int?
    ) -> UInt16? {
        guard vendorID == 76 || vendorID == 1452,
              let productID, productID > 0 else { return nil }
        return UInt16(exactly: productID)
    }

    /// deviceModel gives verified product IDs priority over a user-editable name.
    /// A known foreign vendor blocks Apple's IDs and name hints altogether.
    static func deviceModel(
        vendorID   : Int?,
        productID  : Int?,
        productName: String?
    ) -> BluetoothDeviceModel {
        guard vendorID == 76 || vendorID == 1452 else { return .generic }
        switch productID {
        // Apple IOBluetoothUI AssetPaths.plist verifies the original AirPods IDs.
        // Pro/Max IDs are also documented by the primary ESPHome implementation:
        // github.com/myhomeiot/esphome-components/blob/main/examples/ble_gateway/airpods.yaml
        // Newer families come from the installed Apple CoreBluetoothUI
        // AssetPaths{,-B768,-B788,-B515c,-B515d}.plist product catalogs.
        case 0x2002, 0x200F, 0x2013, 0x2019, 0x201B: return .airPods
        case 0x200E, 0x2014, 0x2024, 0x2027: return .airPodsPro
        case 0x200A, 0x201F, 0x202D: return .airPodsMax
        default: break
        }
        let name = productName?.lowercased() ?? ""
        if name.contains("airpods pro") { return .airPodsPro }
        if name.contains("airpods max") { return .airPodsMax }
        if name.contains("airpods") { return .airPods }
        return .generic
    }

    /// cachedIdentity reads only an exact-address metadata record. Historical
    /// battery cache fields have no verified freshness contract and are not used.
    static func cachedIdentity(
        cache   : [String: Any],
        deviceID: String
    ) -> [String: Any]? {
        guard let expectedAddress = normalizedAddress(deviceID) else { return nil }
        for (address, value) in cache where normalizedAddress(address) == expectedAddress {
            return value as? [String: Any]
        }
        return nil
    }
}
