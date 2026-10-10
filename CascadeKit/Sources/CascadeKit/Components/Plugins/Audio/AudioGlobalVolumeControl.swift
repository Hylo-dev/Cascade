//
//  AudioGlobalVolumeControl.swift
//  CascadeKit
//

import AppKit
import SwiftUI

/// AudioGlobalVolumeControl is the system volume as the user touches it: the capsule wired to the
/// mixer model, the output's icon inside it, scrolling over it, and what VoiceOver reads and
/// adjusts. The widget's bar and the mixer's global column both draw this one view, so a drag, a
/// scroll or an accessibility step behaves the same in both places and is fixed in one.
///
/// It is handed the reading to draw, so its owner decides what to do when there is none. What
/// differs between its uses comes in as two values: whether the capsule shows the percentage and
/// what a click does.
struct AudioGlobalVolumeControl: View {

    /// accessibilityStep is how far the VoiceOver increment and decrement move the level.
    private static let accessibilityStep = 1.0 / 16.0

    let model          : AudioMixerModel
    let system         : SystemAudioState
    let showsPercentage: Bool
    let onClick        : (() -> Void)?

    var body: some View {
        let output = system.outputs.first { $0.uid == system.selectedUIDs.first }
        let icon   = AudioOutputIcon.resolve(
            output : output,
            level  : system.level,
            isMuted: system.isMuted
        )

        AudioVolumeCapsule(
            level          : system.level,
            isMuted        : system.isMuted,
            icon           : icon,
            showsPercentage: showsPercentage,
            onLevel        : { level in
                guard system.supportsVolume else { return }

                model.adjust(to: level)
            },
            onEnd          : {
                model.endAdjusting()
            },
            onClick        : onClick
        )
        .background {
            ScrollWheelReader { deltaY, isPrecise, phase, momentum in
                scroll(
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

    static var accessibilityLabel: String {
        String(localized: "Global volume", bundle: .module)
    }

    /// accessibilityValue is the level VoiceOver reads, or a dash while there is no reading.
    static func accessibilityValue(of system: SystemAudioState?) -> String {
        guard let system else { return "\u{2014}" }

        return "\(Int((system.level * 100).rounded()))%"
    }

    /// scroll moves the level for one scroll event. A trackpad's inertia after the fingers lift
    /// is ignored, so the level stops where the user stopped. A burst ends with its phase; a
    /// wheel has no phase, so each notch is a burst of its own.
    private func scroll(
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
