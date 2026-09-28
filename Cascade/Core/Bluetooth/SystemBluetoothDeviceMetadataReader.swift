//
//  SystemBluetoothDeviceMetadataReader.swift
//  Cascade
//

import Foundation
import IOBluetooth
import IOKit
import ObjectiveC

/// SystemBluetoothDeviceMetadataReader reads existing device records without
/// discovery, a connection attempt, subprocesses or preference writes.
///
/// Private battery accessors were verified against the installed Apple runtime:
/// batteryPercentSingle/Left/Right/Case return unsigned char, vendorID/productID
/// return unsigned short, and colorID returns unsigned char. The allowlist checks
/// those signatures at runtime
/// before KVC boxes a known scalar getter. No unknown key reaches KVC.
nonisolated struct SystemBluetoothDeviceMetadataReader: BluetoothDeviceMetadataReading {

    func metadata(for deviceID: String) -> BluetoothDeviceMetadata {
        guard BluetoothMetadataParser.normalizedAddress(deviceID) != nil,
              let device = IOBluetoothDevice(addressString: deviceID),
              device.isConnected()
        else { return BluetoothDeviceMetadata() }

        let properties      = privateProperties(device: device)
        let privateBattery  = BluetoothMetadataParser.privateBattery(properties: properties)
        let registryBattery = BluetoothMetadataParser.registryBattery(
            records : registryRecords(),
            deviceID: deviceID
        )
        let cachedIdentity  = cachedIdentity(deviceID: deviceID)
        let vendorID        = nonzeroInteger(properties["vendorID"]) ?? nonzeroInteger(cachedIdentity?["VendorID"])
        let productID       = nonzeroInteger(properties["productID"]) ?? nonzeroInteger(cachedIdentity?["ProductID"])
        let appleProductID  = BluetoothMetadataParser.appleProductID(
            vendorID : vendorID,
            productID: productID
        )

        // Zero is also the framework's default for absent color metadata. Leave
        // it unknown so the artwork resolver uses the system's base variant.
        let colorID = appleProductID == nil ? nil : nonzeroInteger(properties["colorID"])
            .flatMap { UInt8(exactly: $0) }
        let model   = BluetoothMetadataParser.deviceModel(
            vendorID   : vendorID,
            productID  : productID,
            productName: cachedIdentity?["ProductName"] as? String ?? device.name
        )

        return BluetoothDeviceMetadata(
            battery  : privateBattery?.fillingMissing(from: registryBattery) ?? registryBattery,
            model    : model,
            productID: appleProductID,
            colorID  : colorID
        )
    }

    /// privateProperties checks the exact getter signature before scalar boxing;
    /// future OS changes become unavailable metadata instead of an ABI assumption.
    private func privateProperties(device: IOBluetoothDevice) -> [String: Any] {
        let getterTypes: [(String, Character)] = [
            ("batteryPercentSingle", "C"),
            ("batteryPercentLeft",   "C"),
            ("batteryPercentRight",  "C"),
            ("batteryPercentCase",   "C"),
            ("vendorID",             "S"),
            ("productID",            "S"),
            ("colorID",              "C")
        ]

        var properties: [String: Any] = [:]
        for (key, returnType) in getterTypes {
            let selector = NSSelectorFromString(key)
            guard device.responds(to: selector),
                  let method = class_getInstanceMethod(type(of: device), selector),
                  method_getNumberOfArguments(method) == 2,
                  let encoding = method_getTypeEncoding(method),
                  String(cString: encoding).first == returnType,
                  let value = device.value(forKey: key) as? NSNumber
            else { continue }

            properties[key] = value
        }

        return properties
    }

    /// registryRecords bounds inspection to Bluetooth/HID service classes and
    /// at most 128 services. Battery attribution still requires an exact address.
    private func registryRecords() -> [[String: Any]] {
        let classes   = ["IOBluetoothDevice", "AppleDeviceManagementHIDEventService", "IOHIDDevice"]
        var records  : [[String: Any]] = []
        var remaining = 128

        for serviceClass in classes {
            guard remaining > 0, let matching = IOServiceMatching(serviceClass) else { break }

            var iterator: io_iterator_t = 0
            let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
            guard result == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(iterator) }

            while remaining > 0 {
                let service = IOIteratorNext(iterator)
                guard service != 0 else { break }
                defer { IOObjectRelease(service) }

                remaining -= 1
                var properties: Unmanaged<CFMutableDictionary>?
                let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
                guard result == KERN_SUCCESS,
                      let dictionary = properties?.takeRetainedValue() as? [String: Any]
                else { continue }

                records.append(dictionary)
            }
        }

        return records
    }

    /// cachedIdentity uses BluetoothDeviceCache/DeviceCache only for product
    /// identity. Cached battery reports may predate this connection indefinitely.
    private func cachedIdentity(deviceID: String) -> [String: Any]? {
        for key in ["BluetoothDeviceCache", "DeviceCache"] {
            for user in [kCFPreferencesAnyUser, kCFPreferencesCurrentUser] {
                guard let cache = CFPreferencesCopyValue(
                    key as CFString,
                    "com.apple.Bluetooth" as CFString,
                    user,
                    kCFPreferencesAnyHost
                ) as? [String: Any],
                let identity = BluetoothMetadataParser.cachedIdentity(
                    cache   : cache,
                    deviceID: deviceID
                )
                else { continue }

                return identity
            }
        }

        return nil
    }

    /// nonzeroInteger excludes absent, fractional and out-of-range hardware identifiers.
    private func nonzeroInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue > 0,
              number.doubleValue <= Double(UInt16.max),
              number.doubleValue.rounded(.towardZero) == number.doubleValue
        else { return nil }

        return number.intValue
    }
}
