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
/// differs between its uses comes in as values: whether it writes the percentage
/// (`showsPercentage`; only the mixer shows the level, in its title row), what a click does, and
/// which of the two it is (`role`).
///
/// Opening the mixer from the widget, or going back, the capsule glides from where the other one
/// was (`AudioCapsuleHandoff`): it starts offset and scaled onto the other's frame and springs
/// to its own. Offset and scale are render effects, so the glide lays nothing out again, and it
/// runs once per swap; at rest the control pays only for a frame noted when its layout changes.
struct AudioGlobalVolumeControl: View {

    /// accessibilityStep is how far the VoiceOver increment and decrement move the level.
    private static let accessibilityStep = 1.0 / 16.0

    /// glide is the spring that carries the capsule from the other one's place to its own.
    private static let glide = Animation.spring(response: 0.42, dampingFraction: 0.82)

    let role           : AudioCapsuleHandoff.Role
    let widthRatio     : CGFloat
    let model          : AudioMixerModel
    let system         : SystemAudioState
    let showsPercentage: Bool
    let onClick        : (() -> Void)?

    /// scrollOvershoot is how far the scroll has pushed past an end, in points: the capsule's
    /// rubber band for the scroll, which the capsule's own drag cannot see.
    @State
    private var scrollOvershoot: CGFloat = 0

    /// entryOffset and entryScale place the capsule on the other one's frame for the glide;
    /// hasArrived makes the handoff happen once, on the first frame the control learns.
    @State
    private var entryOffset: CGSize = .zero

    @State
    private var entryScale: CGFloat = 1

    @State
    private var hasArrived = false

    var body: some View {
        let output = system.outputs.first { $0.uid == system.selectedUIDs.first }
        let icon   = AudioOutputIcon.resolve(
            output : output,
            level  : system.level,
            isMuted: system.isMuted
        )

        AudioVolumeCapsule(
            widthRatio     : widthRatio,
            level          : system.level,
            isMuted        : system.isMuted,
            icon           : icon,
            iconOpacity    : 1,
            showsPercentage: showsPercentage,
            pushedOvershoot: scrollOvershoot,
            onLevel        : { level in
                guard system.supportsVolume else { return }

                model.adjust(to: level)
            },
            onEnd          : {
                model.endAdjusting()
            },
            onClick        : onClick
        )
        .scaleEffect(entryScale)
        .offset(entryOffset)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            arrive(at: frame)
        }
        .onDisappear {
            model.capsuleHandoff.leave(role)
        }
        .background {
            AudioVolumeGlassLight(
                widthRatio: widthRatio,
                level     : system.level,
                isMuted   : system.isMuted
            )
        }
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

    /// pillFrame is the pill the capsule draws inside the control's frame: centred, sized by the
    /// capsule's own metrics, so the handoff matches the pills and not the slots around them.
    static func pillFrame(
        in frame  : CGRect,
        widthRatio: CGFloat
    ) -> CGRect {
        let metrics = AudioVolumeCapsuleMetrics(
            availableWidth : frame.width,
            availableHeight: frame.height,
            widthRatio     : widthRatio
        )
        return CGRect(
            x     : frame.midX - metrics.width / 2,
            y     : frame.midY - metrics.height / 2,
            width : metrics.width,
            height: metrics.height
        )
    }

    /// arrive notes the pill's frame for the other capsule and, the first time, starts on the
    /// other's frame if it has just left. The start is set without animation and the spring
    /// back is asked on the next main-actor turn, once the start has been drawn: in the same
    /// update SwiftUI would see no change to animate.
    private func arrive(at frame: CGRect) {
        let handoff = model.capsuleHandoff
        let pill    = Self.pillFrame(in: frame, widthRatio: widthRatio)
        defer {
            handoff.record(pill, for: role)
        }
        guard !hasArrived, pill.height > 0 else { return }

        hasArrived = true
        guard let origin = handoff.origin(for: role) else { return }

        entryOffset = CGSize(
            width : origin.midX - pill.midX,
            height: origin.midY - pill.midY
        )
        entryScale  = origin.height / pill.height
        Task { @MainActor in
            withAnimation(Self.glide) {
                entryOffset = .zero
                entryScale  = 1
            }
        }
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
            let step = VolumeGesture.scrolledPastEnds(
                system.level,
                overshoot: Double(scrollOvershoot),
                deltaY   : deltaY,
                isPrecise: isPrecise
            )
            if step.level != system.level {
                model.adjust(to: step.level)
            }
            if isPrecise {
                scrollOvershoot = CGFloat(step.overshoot)
            } else if step.overshoot != 0 {
                kick(CGFloat(step.overshoot))
            }
        }
        if phase.isEmpty || phase.contains(.ended) || phase.contains(.cancelled) {
            model.endAdjusting()

            if isPrecise, scrollOvershoot != 0 {
                withAnimation(AudioVolumeCapsule.release) {
                    scrollOvershoot = 0
                }
            }
        }
    }

    /// kick nudges the pill past an end for one wheel notch and springs it straight back.
    private func kick(_ overshoot: CGFloat) {
        withAnimation(.spring(duration: 0.12)) {
            scrollOvershoot = overshoot
        } completion: {
            withAnimation(AudioVolumeCapsule.release) {
                scrollOvershoot = 0
            }
        }
    }
}
