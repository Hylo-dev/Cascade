//
//  AudioMixerComponent.swift
//  CascadeKit
//

import SwiftUI

/// AudioMixerComponent is the tier-2 component audio.mixer, the whole body of the audio widget's
/// detail page. The page is only as tall as the notch's ordinary expanded surface, so it is laid
/// out around the hardware notch (`pluginPageObstruction`) instead of under a title bar. In the
/// notch's left shoulder, beside the back button, sits one row: "Audio" and the level. Below the
/// shoulder, the global column (the level as a capsule, with the output button and the mute
/// button beside it), a divider, and the apps area, which will hold one strip per app that plays
/// audio and, until then, says where they will appear.
///
/// The output button opens the output selector in the apps area, beside the column. Whether it
/// is open is local state of this view: nothing outside it cares, and nothing is kept once the
/// page closes. A press on the capsule or on the empty apps area closes it; Escape is not
/// handled here, since the detail page already takes it to close the whole page.
///
/// It draws the same live system state the volume bar does, through the same capsule, so a drag
/// or a scroll feels identical in both places. With no model, or before the first reading, it
/// draws nothing, as the page behind it has nothing to offer yet.
struct AudioMixerComponent: View {

    /// emptyAppsText is the apps area's empty state, which is also its localization key.
    static let emptyAppsText = "Apps appear here when they play audio"

    /// titleLeadingInset leaves the back button's room: its 4 pt inset, its 24 pt and a gap.
    static let titleLeadingInset: CGFloat = 30

    /// bandHeightWithoutObstruction is the title row's height where no notch covers the top: the
    /// back button and its insets.
    static let bandHeightWithoutObstruction: CGFloat = 32

    private static let capsuleWidth: CGFloat = 28
    private static let buttonSize  : CGFloat = 20

    @Environment(\.pluginComponentServices)
    private var services

    @Environment(\.pluginPageObstruction)
    private var obstruction

    @State
    private var isPickerOpen = false

    var body: some View {
        if let model = services?.audio, let system = model.system {
            let band = Self.bandHeight(obstruction: obstruction)

            VStack(alignment: .leading, spacing: 0) {
                titleRow(
                    level: system.level,
                    band : band
                )

                HStack(spacing: 10) {
                    AudioGlobalVolumeControl(
                        widthRatio     : 1,
                        model          : model,
                        system         : system,
                        isAdjusting    : false,
                        showsPercentage: false,
                        onClick        : {
                            isPickerOpen = false
                        }
                    )
                    .frame(width: Self.capsuleWidth)

                    VStack(spacing: 10) {
                        outputButton(system: system)
                        muteButton(model: model, system: system)
                    }
                    .frame(maxHeight: .infinity)

                    Rectangle()
                        .fill(Color(white: 0.2))
                        .frame(width: 1)
                        .padding(.vertical, 4)

                    appsArea(model: model)
                }
                .padding(.top, 4)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        } else {
            Color.clear
        }
    }

    /// bandHeight is how tall the title row is: the notch's obstruction where there is one, so
    /// the row sits in the shoulder beside it, else the back button's row at the top.
    static func bandHeight(obstruction: CGRect) -> CGFloat {
        obstruction.height > 0 ? obstruction.maxY : bandHeightWithoutObstruction
    }

    /// titleWidth is how far the title row may reach: up to the notch where there is one, else
    /// as far as the page goes, so "Audio" never slides under the hardware.
    static func titleWidth(obstruction: CGRect) -> CGFloat? {
        obstruction.width > 0 ? Swift.max(0, obstruction.minX - titleLeadingInset) : nil
    }

    private func titleRow(
        level: Double,
        band : CGFloat
    ) -> some View {
        HStack(spacing: 4) {
            Text(String(localized: "Audio", bundle: .module))
                .foregroundStyle(.white)

            Text("· \(Int((level * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .padding(.leading, Self.titleLeadingInset)
        .frame(
            width    : Self.titleWidth(obstruction: obstruction).map { $0 + Self.titleLeadingInset },
            height   : band,
            alignment: .leading
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }

    private func outputButton(system: SystemAudioState) -> some View {
        let output = system.outputs.first { $0.uid == system.selectedUIDs.first }
        let icon   = AudioOutputIcon.resolve(
            output : output,
            level  : 1,
            isMuted: false
        )

        return Button {
            isPickerOpen.toggle()
        } label: {
            AudioOutputIconView(icon: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    Circle()
                        .fill(isPickerOpen ? Color.white.opacity(0.28) : Color.white.opacity(0.14))
                )
                .overlay(alignment: .topTrailing) {
                    if let badge = Self.badge(selectedCount: system.selectedUIDs.count) {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(white: 0.15))
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(.white))
                            .offset(x: 6, y: -4)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Audio output", bundle: .module))
    }

    private func muteButton(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        Button {
            model.toggleMute()
        } label: {
            Image(systemName: Self.muteSymbol(isMuted: system.isMuted))
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    Circle()
                        .fill(system.isMuted ? Color.white.opacity(0.28) : Color.white.opacity(0.14))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            system.isMuted
                ? String(localized: "Unmute", bundle: .module)
                : String(localized: "Mute", bundle: .module)
        )
    }

    private func appsArea(model: AudioMixerModel) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isPickerOpen = false
                }

            if isPickerOpen {
                AudioOutputPicker(
                    model  : model,
                    onClose: {
                        isPickerOpen = false
                    }
                )
                .frame(maxHeight: .infinity)
            } else {
                Text(String(localized: "Apps appear here when they play audio", bundle: .module))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// badge is the "+N" on the output button while the system plays to several outputs: how many
    /// there are beyond the one whose icon the button wears.
    static func badge(selectedCount: Int) -> String? {
        selectedCount > 1 ? "+\(selectedCount - 1)" : nil
    }

    static func muteSymbol(isMuted: Bool) -> String {
        isMuted ? "speaker.slash.fill" : "speaker.fill"
    }
}
