//
//  AudioOutputIcon.swift
//  CascadeKit
//

import CascadeContracts
import CoreAudio

/// AudioOutputIcon says what the widget draws for the current output. It is decided from the
/// device and the level, never from a view, so the choice is testable and the view is a switch.
/// Everything is an SF Symbol: a Bluetooth product is the symbol of its model, not a drawing.
///
/// `speaker` carries the level as a whole percent, because the view picks the wave count from it
/// (1–33, 34–66, 67–100, and a plain filled speaker at 0) and a percent compares exactly where a
/// `Double` would not.
nonisolated public enum AudioOutputIcon: Equatable, Sendable {

    case speaker(level: Int)
    case muted
    case symbol(String)

    /// resolve picks the icon. Muted wins over everything, because it is the state the user most
    /// needs to see. A Bluetooth device with a verified identity gets the symbol of its model
    /// (`symbolName`); one without falls back to headphones. Transports that say what the output
    /// physically is (a display, a television, AirPlay) get their own symbol. The built-in output
    /// is the default one, and shows the speaker for the level like anything else, or no output
    /// at all.
    public static func resolve(
        output : AudioOutputDevice?,
        level  : Double,
        isMuted: Bool
    ) -> AudioOutputIcon {
        if isMuted { return .muted }
        guard let output else { return .speaker(level: percent(of: level)) }
        if let identity = output.bluetooth { return .symbol(symbolName(for: identity)) }

        switch output.transportType {
            case kAudioDeviceTransportTypeDisplayPort:
                return .symbol("display")

            case kAudioDeviceTransportTypeHDMI:
                return .symbol("tv")

            case kAudioDeviceTransportTypeAirPlay:
                return .symbol("airplayaudio")

            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return .symbol("headphones")

            default:
                return .speaker(level: percent(of: level))
        }
    }

    /// symbolName is the SF Symbol of a verified Bluetooth product. The AirPods names are the
    /// preferred, newer spellings; `AudioOutputSymbol` falls back to the older ones where the
    /// system lacks them. Any other product is plain headphones.
    public static func symbolName(for identity: AudioBluetoothIdentity) -> String {
        switch identity.model {
            case .airPods:
                "airpods"

            case .airPodsPro:
                "airpods.pro"

            case .airPodsMax:
                "airpods.max"

            case .generic:
                "headphones"
        }
    }

    private static func percent(of level: Double) -> Int {
        Swift.min(Swift.max(Int((level * 100).rounded()), 0), 100)
    }
}
