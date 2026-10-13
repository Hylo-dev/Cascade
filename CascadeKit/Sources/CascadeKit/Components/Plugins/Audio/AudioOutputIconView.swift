//
//  AudioOutputIconView.swift
//  CascadeKit
//

import SwiftUI

/// AudioOutputIconView draws what `AudioOutputIcon` decided: a speaker whose waves follow the
/// level, the muted speaker, or a system symbol, the Bluetooth product's included. It is a switch
/// and nothing more; the choice was made, and tested, away from any view. A symbol takes its
/// colour from the environment, so the capsule can ink it for the fill it sits on.
struct AudioOutputIconView: View {

    let icon: AudioOutputIcon

    var body: some View {
        switch icon {
            case .speaker(let level):
                Image(systemName: Self.speakerSymbol(forPercent: level))

            case .muted:
                Image(systemName: "speaker.slash.fill")

            case .symbol(let name):
                Image(systemName: AudioOutputSymbol.installedName(for: name))
        }
    }

    /// speakerSymbol picks the wave count: none at zero, then a third of the range per wave.
    private static func speakerSymbol(forPercent percent: Int) -> String {
        switch percent {
            case ..<1:
                "speaker.fill"

            case 1...33:
                "speaker.wave.1.fill"

            case 34...66:
                "speaker.wave.2.fill"

            default:
                "speaker.wave.3.fill"
        }
    }
}
