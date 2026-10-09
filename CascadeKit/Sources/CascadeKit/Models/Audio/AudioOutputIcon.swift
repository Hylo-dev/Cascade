//
//  AudioOutputIcon.swift
//  CascadeKit
//

import CoreAudio

/// AudioOutputIcon says what the widget draws for the current output. It is decided from the
/// device and the level, never from a view, so the choice is testable and the view is a switch.
///
/// `speaker` carries the level as a whole percent, because the view picks the wave count from it
/// (1–33, 34–66, 67–100, and a plain filled speaker at 0) and a percent compares exactly where a
/// `Double` would not.
nonisolated public enum AudioOutputIcon: Equatable, Sendable {

    case speaker(level: Int)
    case muted
    case bluetooth(AudioBluetoothIdentity)
    case symbol(String)

    /// resolve picks the icon. Muted wins over everything, because it is the state the user most
    /// needs to see. A Bluetooth device with a verified identity is drawn as itself; one without
    /// falls back to headphones. Transports that say what the output physically is get their own
    /// symbol, and anything else, or no output at all, shows the speaker for the level.
    public static func resolve(
        output : AudioOutputDevice?,
        level  : Double,
        isMuted: Bool
    ) -> AudioOutputIcon {
        if isMuted {
            return .muted
        }
        guard let output else {
            return .speaker(level: percent(of: level))
        }
        if let identity = output.bluetooth {
            return .bluetooth(identity)
        }
        switch output.transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return .symbol("laptopcomputer")
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

    private static func percent(of level: Double) -> Int {
        Swift.min(Swift.max(Int((level * 100).rounded()), 0), 100)
    }
}
