//
//  SoundFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// SoundFace is the volume widget's document, a face for the 2x1 tile and one for the 1x1 tile,
/// the wider first. Both set the speaker, with as many waves as the volume notice draws, beside
/// the percentage, above the kernel's level bar; muted, the speaker is struck through, the bar
/// empty and the percentage gives way to "Muted". VoiceOver reads the level or that the audio is
/// muted, since the bar is hidden from it.
///
/// Under a 38-point notch a 2x1 tile is 110 by 31 points and a 1x1 tile 52 by 31. The 2x1 face is
/// 108 points wide, a 13-point reading over a bar as wide as the face; the 1x1 face is a
/// 10.5-point reading over a 50-point bar, about 20 points tall. In both the reading has a fixed
/// slot that holds "100%" whole, and only a longer word, such as a translation of "Muted",
/// shrinks into it. The fixed width is also what chooses the face: ViewThatFits measures a face
/// with the tile's height already given.
enum SoundFace {

    static let mediumWidth = 108.0

    private static let mediumPadding = 8.0
    private static let mediumSpeaker = 18.0
    private static let smallSpeaker  = 16.0
    private static let smallReading  = 32.0
    private static let gap           = 4.0

    static func publication(for state: PluginVolumeState) throws -> PluginPublication {
        let level = state.isMuted ? 0 : (state.percentage ?? 0)

        return try PluginPublication(
            feature : SoundPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .horizontal) {

                    medium(level, isMuted: state.isMuted)

                    small(level, isMuted: state.isMuted)
                }
                .accessibilityLabel(
                    state.isMuted
                        ? String(localized: "Audio muted", table: "Plugins", bundle: .module)
                        : String(localized: "Volume, \(level) percent", table: "Plugins", bundle: .module)
                )
            )
        )
    }

    /// medium is the 2x1 face: the speaker and the reading above a bar as wide as the face.
    private static func medium(
        _ level: Int,
        isMuted: Bool
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: 5) {

            HStack(spacing: gap) {

                speaker(level, isMuted: isMuted, size: 13)
                    .frame(width: mediumSpeaker, alignment: .leading)

                reading(level, isMuted: isMuted, size: 13)
                    .frame(width: mediumWidth - 2 * mediumPadding - mediumSpeaker - gap, alignment: .leading)
            }

            bar(level)
                .frame(height: 4, maxWidth: .infinity)
        }
        .padding(.horizontal, mediumPadding)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the speaker and the reading above a short bar.
    private static func small(
        _ level: Int,
        isMuted: Bool
    ) -> PluginNode {
        VStack(spacing: gap) {

            HStack(spacing: 2) {

                speaker(level, isMuted: isMuted, size: 10)
                    .frame(width: smallSpeaker)

                reading(level, isMuted: isMuted, size: 10.5)
                    .frame(width: smallReading, alignment: .leading)
            }

            bar(level)
                .frame(width: smallSpeaker + 2 + smallReading, height: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func speaker(
        _ level: Int,
        isMuted: Bool,
        size   : Double
    ) -> PluginNode {
        Image(systemName: VolumeNotice.symbol(level, isMuted: isMuted))
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(.white)
    }

    /// reading is the percentage in white rounded digits that keep their width, or "Muted",
    /// dimmed.
    private static func reading(
        _ level: Int,
        isMuted: Bool,
        size   : Double
    ) -> PluginNode {
        Text(isMuted ? String(localized: "Muted", table: "Plugins", bundle: .module) : "\(level)%")
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(isMuted ? .white.opacity(0.55) : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// bar is the kernel's level bar, empty while muted.
    private static func bar(_ level: Int) -> PluginNode {
        Component(
            id        : "volume.level",
            version   : 1,
            parameters: ["level": .number(Double(level))]
        )
    }
}
