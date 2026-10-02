//
//  VolumeNotice.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// VolumeNotice is the volume plugin's notice, the system volume HUD's replacement: the speaker
/// and the title leading, the level bar and the percentage trailing, the speaker alone when
/// minimal. It lasts 1.8 seconds and every announced change shows it again, so holding a key
/// keeps it up.
enum VolumeNotice {

    static func publication(for state: PluginVolumeState) throws -> PluginPublication {
        let percentage = state.isMuted ? 0 : (state.percentage ?? 0)
        let speaker    = Image(systemName: symbol(percentage, isMuted: state.isMuted))
            .font(.system(size: 14, weight: .regular))
            .frame(width: 18)

        return try PluginPublication(
            feature : VolumePlugin.feature,
            surface : .notice,
            document: PluginDocument(
                root: Regions {

                    HStack(spacing: 6) {

                        speaker

                        Text(state.isMuted ? text("Muted") : text("Volume"))
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)

                    HStack(spacing: 6) {

                        Component(
                            id        : "volume.level",
                            version   : 1,
                            parameters: ["level": .number(Double(percentage))]
                        )
                        .frame(height: 4, maxWidth: .infinity)

                        Text("\(percentage)%")
                            .font(.callout.monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                    }
                    .foregroundStyle(.white)

                    Image(systemName: symbol(percentage, isMuted: state.isMuted))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white)
                }
            ),
            notice  : PluginNoticeAttributes(
                duration          : 1.8,
                compactWidth      : 116,
                accessibilityLabel: state.isMuted
                    ? text("Audio muted")
                    : String(localized: "Volume, \(percentage) percent", table: "VolumeNotice", bundle: .module)
            )
        )
    }

    private static func symbol(
        _ percentage: Int,
        isMuted     : Bool
    ) -> String {
        if isMuted || percentage == 0 { return "speaker.slash.fill" }
        if percentage < 34 { return "speaker.wave.1.fill" }
        if percentage < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "VolumeNotice", bundle: .module)
    }
}
