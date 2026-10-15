//
//  PluginBluetoothState.swift
//  CascadeKit
//

/// PluginBluetoothState is the `bluetooth` catalog source's state, typed: the device of the
/// latest event, what the system measured and verified about it, and the event's number and
/// revision. PluginHost's Bluetooth source builds its events from it and a plugin reads them back
/// with it, so both sides agree on the fields by construction.
///
/// The source numbers each real transition and never reuses a number within one PluginHost; a
/// later battery or model reading of the same transition keeps the number and raises the
/// revision. Event zero is a baseline, emitted when the source starts and after a wake that
/// changed the connected devices, with no device of its own, which says whether monitoring works
/// on this Mac.
///
/// Every state, the baseline included, also lists the devices connected at that moment, in the
/// order they connected, since the kernel keeps only the latest state and a plugin that starts
/// later would otherwise never learn what is connected. The list is state, not news: a state
/// that differs from the last one only in it is no event to announce.
public struct PluginBluetoothState: Equatable, Sendable {

    public static let source = "bluetooth"

    public let deviceID   : String
    public let name       : String
    public let symbolName : String
    public let isConnected: Bool
    public let battery    : PluginBluetoothBattery?
    public let model      : PluginBluetoothDeviceModel
    public let productID  : UInt16?
    public let colorID    : UInt8?
    public let eventID    : UInt64
    public let revision   : UInt64
    public let kind       : PluginBluetoothEventKind
    public let isAvailable: Bool

    public let connectedDevices: [PluginBluetoothDevice]

    /// init keeps the first `PluginBluetoothDevice.maximumCount` connected devices.
    public init(
        deviceID        : String,
        name            : String,
        symbolName      : String,
        isConnected     : Bool,
        battery         : PluginBluetoothBattery?,
        model           : PluginBluetoothDeviceModel,
        productID       : UInt16?,
        colorID         : UInt8?,
        eventID         : UInt64,
        revision        : UInt64,
        kind            : PluginBluetoothEventKind,
        isAvailable     : Bool,
        connectedDevices: [PluginBluetoothDevice] = []
    ) {
        self.deviceID         = deviceID
        self.name             = name
        self.symbolName       = symbolName
        self.isConnected      = isConnected
        self.battery          = battery
        self.model            = model
        self.productID        = productID
        self.colorID          = colorID
        self.eventID          = eventID
        self.revision         = revision
        self.kind             = kind
        self.isAvailable      = isAvailable
        self.connectedDevices = Array(connectedDevices.prefix(PluginBluetoothDevice.maximumCount))
    }

    /// baseline is event zero: no device of its own, only whether monitoring works and the
    /// devices already connected.
    public static func baseline(
        isAvailable     : Bool,
        connectedDevices: [PluginBluetoothDevice] = []
    ) -> PluginBluetoothState {
        PluginBluetoothState(
            deviceID        : "",
            name            : "",
            symbolName      : "",
            isConnected     : false,
            battery         : nil,
            model           : .generic,
            productID       : nil,
            colorID         : nil,
            eventID         : 0,
            revision        : 0,
            kind            : .connection,
            isAvailable     : isAvailable,
            connectedDevices: connectedDevices
        )
    }

    /// isNewConnection is the first revision of a device that connected or brought its audio
    /// back: the moment macOS shows its own banner, which Cascade may replace.
    public var isNewConnection: Bool {
        eventID != 0 && revision == 0 && isConnected
    }

    /// init(_:) reads a Bluetooth event, or fails for another source's event or a malformed one.
    /// Numbers are only known to be finite here: a charge is clamped before it becomes an Int,
    /// which would trap past Int's range, and an identity that is not an exact integer of its
    /// range is unknown, never a trap.
    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .string(let deviceID)?   = event.fields["deviceID"],
              case .string(let name)?       = event.fields["name"],
              case .string(let symbolName)? = event.fields["symbolName"],
              case .bool(let isConnected)?  = event.fields["isConnected"],
              case .string(let model)?      = event.fields["model"],
              let deviceModel               = PluginBluetoothDeviceModel(rawValue: model),
              case .string(let kind)?       = event.fields["kind"],
              let eventKind                 = PluginBluetoothEventKind(rawValue: kind),
              case .bool(let isAvailable)?  = event.fields["isAvailable"],
              let eventID                   = Self.counter(event.fields["eventID"]),
              let revision                  = Self.counter(event.fields["revision"]),
              let connectedDevices          = Self.devices(in: event.fields)
        else { return nil }

        let level     = Self.percentage(event.fields["batteryLevel"])
        let left      = Self.percentage(event.fields["batteryLeft"])
        let right     = Self.percentage(event.fields["batteryRight"])
        let caseLevel = Self.percentage(event.fields["batteryCase"])
        let battery   = [level, left, right, caseLevel].allSatisfy { $0 == nil }
            ? nil
            : PluginBluetoothBattery(level: level, left: left, right: right, caseLevel: caseLevel)

        var productID: UInt16?
        if case .number(let value)? = event.fields["productID"] {
            productID = UInt16(exactly: value)
        }

        var colorID: UInt8?
        if case .number(let value)? = event.fields["colorID"] {
            colorID = UInt8(exactly: value)
        }

        self.init(
            deviceID        : deviceID,
            name            : name,
            symbolName      : symbolName,
            isConnected     : isConnected,
            battery         : battery,
            model           : deviceModel,
            productID       : productID,
            colorID         : colorID,
            eventID         : eventID,
            revision        : revision,
            kind            : eventKind,
            isAvailable     : isAvailable,
            connectedDevices: connectedDevices
        )
    }

    /// event is the state as the source emits it; every unknown number is left out.
    public func event() throws -> PluginSourceEvent {
        var fields: [String: PluginValue] = [
            "deviceID"   : .string(deviceID),
            "name"       : .string(name),
            "symbolName" : .string(symbolName),
            "isConnected": .bool(isConnected),
            "model"      : .string(model.rawValue),
            "eventID"    : .number(Double(eventID)),
            "revision"   : .number(Double(revision)),
            "kind"       : .string(kind.rawValue),
            "isAvailable": .bool(isAvailable),
        ]
        let numbers: [String: Int?] = [
            "batteryLevel": battery?.level,
            "batteryLeft" : battery?.left,
            "batteryRight": battery?.right,
            "batteryCase" : battery?.caseLevel,
            "productID"   : productID.map(Int.init),
            "colorID"     : colorID.map(Int.init),
        ]
        for (key, number) in numbers {
            if let number {
                fields[key] = .number(Double(number))
            }
        }

        fields["deviceCount"] = .number(Double(connectedDevices.count))
        for (index, device) in connectedDevices.enumerated() {
            fields["device\(index).name"]   = .string(device.name)
            fields["device\(index).symbol"] = .string(device.symbolName)
            if let level = device.batteryLevel {
                fields["device\(index).battery"] = .number(Double(level))
            }
        }

        return try PluginSourceEvent(source: Self.source, fields: fields)
    }

    /// devices reads the connected devices. An event without `deviceCount` comes from a source
    /// that did not list them yet and lists none; a count past the maximum, or a device without
    /// its name or symbol, makes the whole event malformed.
    private static func devices(in fields: [String: PluginValue]) -> [PluginBluetoothDevice]? {
        guard let deviceCount = fields["deviceCount"] else { return [] }
        guard case .number(let number) = deviceCount,
              let count = Int(exactly: number),
              (0...PluginBluetoothDevice.maximumCount).contains(count)
        else { return nil }

        var devices: [PluginBluetoothDevice] = []
        for index in 0..<count {
            guard case .string(let name)?       = fields["device\(index).name"],
                  case .string(let symbolName)? = fields["device\(index).symbol"]
            else { return nil }

            devices.append(
                PluginBluetoothDevice(
                    name        : name,
                    symbolName  : symbolName,
                    batteryLevel: percentage(fields["device\(index).battery"])
                )
            )
        }

        return devices
    }

    private static func percentage(_ value: PluginValue?) -> Int? {
        guard case .number(let number)? = value else { return nil }

        return Int(min(100, max(0, number)).rounded())
    }

    /// counter reads an event number or revision: a whole number a Double still counts exactly.
    private static func counter(_ value: PluginValue?) -> UInt64? {
        guard case .number(let number)? = value,
              let counter = UInt64(exactly: number),
              counter < 9_007_199_254_740_992
        else { return nil }

        return counter
    }
}
