//
//  AudioVolumeBarComponent.swift
//  CascadeKit
//

import AppKit
import SwiftUI

/// AudioVolumeBarComponent is the tier-2 component audio.volumeBar: the global volume as a
/// vertical capsule. It reads the mixer model from the component services and draws the level,
/// the output's icon and, while the user adjusts, the percentage. The plugin publishes nothing
/// for it: the level is live system state, which a document cannot hold.
///
/// A click opens the widget's detail (the mixer) when the widget has one; a drag sets the level;
/// scrolling over the bar sets it too. With no model, or before the first reading, it draws the
/// unavailable look and takes no input, rather than a control that would do nothing.
struct AudioVolumeBarComponent: View {

    static let accessibilityLabel = "Global volume"

    /// accessibilityStep is how far the VoiceOver increment and decrement move the level.
    private static let accessibilityStep = 1.0 / 16.0

    @Environment(\.pluginComponentServices)
    private var services

    @Environment(\.pluginOpenDetail)
    private var openDetail

    var body: some View {
        if let model = services?.audio, let system = model.system {
            available(model: model, system: system)
        } else {
            unavailable
        }
    }

    private func available(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        let output = system.outputs.first { $0.uid == system.selectedUIDs.first }
        let icon   = AudioOutputIcon.resolve(
            output : output,
            level  : system.level,
            isMuted: system.isMuted
        )

        return AudioVolumeCapsule(
            level          : system.level,
            isMuted        : system.isMuted,
            icon           : icon,
            showsPercentage: model.isAdjusting,
            onLevel        : { level in
                guard system.supportsVolume else { return }

                model.adjust(to: level)
            },
            onEnd          : {
                model.endAdjusting()
            },
            onClick        : openDetail
        )
        .background {
            ScrollWheelReader { deltaY, isPrecise, phase, momentum in
                scroll(
                    model    : model,
                    deltaY   : deltaY,
                    isPrecise: isPrecise,
                    phase    : phase,
                    momentum : momentum
                )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilityLabel)
        .accessibilityValue(Self.accessibilityValue(of: system))
        .accessibilityAdjustableAction { direction in
            let step: Double
            switch direction {
                case .increment:
                    step = Self.accessibilityStep

                case .decrement:
                    step = -Self.accessibilityStep

                @unknown default:
                    return
            }

            model.adjust(to: system.level + step)
            model.endAdjusting()
        }
    }

    /// accessibilityValue is the level VoiceOver reads, or a dash while there is no reading.
    static func accessibilityValue(of system: SystemAudioState?) -> String {
        guard let system else { return "\u{2014}" }

        return "\(Int((system.level * 100).rounded()))%"
    }

    private var unavailable: some View {
        AudioVolumeCapsule(
            level          : 0,
            isMuted        : false,
            icon           : nil,
            showsPercentage: false,
            onLevel        : { _ in },
            onEnd          : {},
            onClick        : nil
        )
        .overlay(alignment: .bottom) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: AudioVolumeCapsule.iconSize, height: AudioVolumeCapsule.iconSize)
                .padding(.bottom, AudioVolumeCapsule.iconInset)
        }
        .accessibilityElement()
        .accessibilityLabel(Self.accessibilityLabel)
        .accessibilityValue(Self.accessibilityValue(of: nil))
    }

    /// scroll moves the level for one scroll event. A trackpad's inertia after the fingers lift
    /// is ignored, so the level stops where the user stopped. A burst ends with its phase; a
    /// wheel has no phase, so each notch is a burst of its own.
    private func scroll(
        model    : AudioMixerModel,
        deltaY   : Double,
        isPrecise: Bool,
        phase    : NSEvent.Phase,
        momentum : NSEvent.Phase
    ) {
        guard momentum.isEmpty, let system = model.system, system.supportsVolume else { return }

        if deltaY != 0 {
            model.adjust(to: VolumeGesture.scrolled(system.level, deltaY: deltaY, isPrecise: isPrecise))
        }
        if phase.isEmpty || phase.contains(.ended) || phase.contains(.cancelled) {
            model.endAdjusting()
        }
    }
}
