//
//  PluginPowerState.swift
//  CascadeKit
//

/// PluginPowerState is the `power` catalog source's state, typed: the built-in battery's charge,
/// whether the Mac draws external power, whether it is charging, and Low Power Mode. PluginHost's
/// power source builds its events from it and a plugin reads them back with it, so both sides
/// agree on the fields by construction. Charging can be on hold while the charger is connected,
/// so external power and charging are separate. A Mac without a built-in battery has no power
/// state at all.
public struct PluginPowerState: Equatable, Sendable {

    public static let source = "power"

    public let percentage     : Int?
    public let isExternalPower: Bool
    public let isCharging     : Bool
    public let isLowPowerMode : Bool

    public init(
        percentage     : Int?,
        isExternalPower: Bool,
        isCharging     : Bool,
        isLowPowerMode : Bool
    ) {
        self.percentage      = percentage.map { min(100, max(0, $0)) }
        self.isExternalPower = isExternalPower
        self.isCharging      = isCharging
        self.isLowPowerMode  = isLowPowerMode
    }

    /// init(_:) reads a power event, or fails for another source's event or a malformed one.
    public init?(_ event: PluginSourceEvent) {
        guard event.source == Self.source,
              case .bool(let isExternalPower)? = event.fields["isExternalPower"],
              case .bool(let isCharging)?      = event.fields["isCharging"],
              case .bool(let isLowPowerMode)?  = event.fields["isLowPowerMode"]
        else { return nil }

        // A number is only known to be finite here, so it is clamped before it becomes an Int,
        // which would trap past Int's range.
        var percentage: Int?
        if case .number(let value)? = event.fields["percentage"] {
            percentage = Int(min(100, max(0, value)).rounded())
        }

        self.init(
            percentage     : percentage,
            isExternalPower: isExternalPower,
            isCharging     : isCharging,
            isLowPowerMode : isLowPowerMode
        )
    }

    /// event is the state as the source emits it; an unknown charge is left out.
    public func event() throws -> PluginSourceEvent {
        var fields: [String: PluginValue] = [
            "isExternalPower": .bool(isExternalPower),
            "isCharging"     : .bool(isCharging),
            "isLowPowerMode" : .bool(isLowPowerMode),
        ]
        if let percentage {
            fields["percentage"] = .number(Double(percentage))
        }

        return try PluginSourceEvent(source: Self.source, fields: fields)
    }
}
