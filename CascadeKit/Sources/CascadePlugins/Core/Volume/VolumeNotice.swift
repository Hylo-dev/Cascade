//
//  VolumeNotice.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// VolumeNotice is the volume plugin's notice, the system volume HUD's replacement: the speaker
/// and the title leading, the level bar and the percentage trailing, the speaker alone when
/// minimal. It lasts 1.8 seconds and every announced change shows it again, so holding a key
/// keeps it up.
enum VolumeNotice {

    static func publication(for state: PluginVolumeState) throws -> PluginPublication {
        let percentage = state.isMuted ? 0 : (state.percentage ?? 0)
        let speaker    = PluginNode(
            .symbol(name: symbol(percentage, isMuted: state.isMuted)),
            modifiers: [
                .font(PluginFont(size: 14, weight: .regular)),
                .frame(width: 18, height: nil, maxWidth: nil, maxHeight: nil, alignment: .center),
            ]
        )

        return try PluginPublication(
            feature : VolumePlugin.feature,
            surface : .notice,
            document: PluginDocument(
                root: PluginNode(
                    .regions,
                    children: [
                        PluginNode(
                            .hStack(alignment: .center, spacing: 6),
                            modifiers: [.foregroundStyle(.color(.white))],
                            children : [
                                speaker,
                                PluginNode(
                                    .text(state.isMuted ? text("Muted") : text("Volume")),
                                    modifiers: [.font(PluginFont(style: .callout)), .lineLimit(1)]
                                ),
                            ]
                        ),
                        PluginNode(
                            .hStack(alignment: .center, spacing: 6),
                            modifiers: [.foregroundStyle(.color(.white))],
                            children : [
                                PluginNode(
                                    .component(id: "volume.level", version: 1, parameters: ["level": .number(Double(percentage))]),
                                    modifiers: [.frame(width: nil, height: 4, maxWidth: .infinity, maxHeight: nil, alignment: .center)]
                                ),
                                PluginNode(
                                    .text("\(percentage)%"),
                                    modifiers: [
                                        .font(PluginFont(style: .callout, monospacedDigit: true)),
                                        .frame(width: 36, height: nil, maxWidth: nil, maxHeight: nil, alignment: .trailing),
                                    ]
                                ),
                            ]
                        ),
                        PluginNode(
                            .symbol(name: symbol(percentage, isMuted: state.isMuted)),
                            modifiers: [.font(PluginFont(size: 14, weight: .regular)), .foregroundStyle(.color(.white))]
                        ),
                    ]
                )
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
