//
//  AudioMixerComponent.swift
//  CascadeKit
//

import SwiftUI

/// AudioMixerComponent is the tier-2 component audio.mixer, the whole body of the audio widget's
/// detail page. On the left is the global column: the level as a wide capsule under its
/// percentage, with the output button and the mute button below it. A divider separates it from
/// the apps area, which will hold one strip per app that plays audio and, until then, says where
/// they will appear.
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

    private static let columnWidth: CGFloat = 46
    private static let buttonSize : CGFloat = 20

    @Environment(\.pluginComponentServices)
    private var services

    @State
    private var isPickerOpen = false

    var body: some View {
        if let model = services?.audio, let system = model.system {
            HStack(spacing: 0) {
                column(model: model, system: system)

                Rectangle()
                    .fill(Color(white: 0.2))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                appsArea(model: model)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        } else {
            Color.clear
        }
    }

    private func column(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        VStack(spacing: 8) {
            Text("\(Int((system.level * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)

            AudioGlobalVolumeControl(
                model          : model,
                system         : system,
                showsPercentage: false,
                onClick        : {
                    isPickerOpen = false
                }
            )

            HStack(spacing: 6) {
                outputButton(system: system)
                muteButton(model: model, system: system)
            }
        }
        .frame(width: Self.columnWidth)
        .padding(.trailing, 12)
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
                .padding(.leading, 12)
                .frame(maxWidth: 260, maxHeight: .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
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
