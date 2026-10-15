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
/// (`speakerWaveCount`) and a percent compares exactly where a `Double` would not. A level of 0
/// is drawn as muted: silent is silent, whether the system calls it mute.
nonisolated public enum AudioOutputIcon: Equatable, Sendable {

    case speaker(level: Int)
    case muted
    case symbol(String)

    /// resolve picks the icon. Muted wins over everything, because it is the state the user most
    /// needs to see, and a level that rounds to 0% is shown the same way. A Bluetooth device
    /// with a verified identity gets the symbol of its model (`symbolName`); one without falls
    /// back to headphones. Transports that say what the output physically is (a display, a
    /// television, AirPlay) get their own symbol. The built-in output is the default one, and
    /// shows the speaker for the level like anything else, or no output at all.
    public static func resolve(
        output : AudioOutputDevice?,
        level  : Double,
        isMuted: Bool
    ) -> AudioOutputIcon {
        if isMuted || percent(of: level) == 0 { return .muted }
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

    /// device picks the icon of the output itself, for the places that show which device it is
    /// (the picker's rows and the mixer's output button), where the pill's level speaker would
    /// say nothing. The built-in output is the MacBook; a Bluetooth product is its model's
    /// symbol, or headphones without a verified identity; a display, a television and AirPlay
    /// have their own; anything else, or no output at all, is a hi-fi speaker. Mute and level
    /// are not part of it: they belong to the capsule (`resolve`).
    public static func device(for output: AudioOutputDevice?) -> AudioOutputIcon {
        guard let output else { return .symbol("hifispeaker") }
        if let identity = output.bluetooth { return .symbol(symbolName(for: identity)) }

        switch output.transportType {
            case kAudioDeviceTransportTypeBuiltIn:
                return .symbol("macbook")

            case kAudioDeviceTransportTypeDisplayPort:
                return .symbol("display")

            case kAudioDeviceTransportTypeHDMI:
                return .symbol("tv")

            case kAudioDeviceTransportTypeAirPlay:
                return .symbol("airplayaudio")

            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return .symbol("headphones")

            default:
                return .symbol("hifispeaker")
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

    /// speakerWaveCount is how many of the speaker's three waves a level shows: one up to a
    /// third, two up to two thirds, three above, none at 0 (which is drawn muted anyway). It
    /// changes only at those thresholds, so between them the icon holds still while the level
    /// moves, as the system's own volume does; the view animates the change when one is crossed.
    public static func speakerWaveCount(level: Int) -> Int {
        switch level {
            case ...0:
                0

            case ...33:
                1

            case ...66:
                2

            default:
                3
        }
    }

    /// speakerSymbol is the speaker with `waves` whole waves: the plain speaker for none, then the
    /// one-, two- and three-wave speakers. Each symbol draws only its own waves, which is what
    /// keeps the waves not reached off the icon, where a variable value would draw them dimmed.
    public static func speakerSymbol(waves: Int) -> String {
        switch waves {
            case ...0:
                "speaker.fill"

            case 1:
                "speaker.wave.1.fill"

            case 2:
                "speaker.wave.2.fill"

            default:
                "speaker.wave.3.fill"
        }
    }

    private static func percent(of level: Double) -> Int {
        Swift.min(Swift.max(Int((level * 100).rounded()), 0), 100)
    }
}
