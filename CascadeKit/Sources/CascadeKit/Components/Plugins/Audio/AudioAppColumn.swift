//
//  AudioAppColumn.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

/// AudioAppColumn is one app in the mixer's apps area: its icon, a capsule for its volume, and
/// below it the mute button and the output button. It is thin on purpose, 34 pt, so several fit
/// beside each other in the area's horizontal scroll view.
///
/// It owns no state. The app's reading comes in as a value, the user's gestures go out to the
/// model, and what the picker is showing is the owner's business: the output button only says it
/// was pressed. The capsule is the same `AudioVolumeCapsule` the system volume uses, so a drag, a
/// scroll and a VoiceOver step feel identical, with the app's icon above it instead of inside.
///
/// The column never claims a control the app does not have. While AudioHost rebuilds the app's
/// tap, a small arrow badge sits on its icon. When the user's request is not being enforced, the
/// capsule is dashed and the context menu offers "Return to native audio". When the system has
/// refused audio capture, the column is read-only: it shows the app at its native level, full and
/// unmuted, and its controls do nothing, because a tap that cannot be played back would only
/// silence the app.
struct AudioAppColumn: View {

    static let width       : CGFloat = 34
    static let iconSize    : CGFloat = 18
    static let capsuleWidth: CGFloat = 18
    static let buttonSize  : CGFloat = 16

    /// accessibilityStep is how far the VoiceOver increment and decrement move the level.
    private static let accessibilityStep = 1.0 / 16.0

    let app         : AudioAppState
    let system      : SystemAudioState
    let model       : AudioMixerModel
    let icons       : AudioAppIconCache
    let isPickerOpen: Bool
    let onClick     : () -> Void
    let onOutputTap : () -> Void

    var body: some View {
        let isReadOnly = model.areAppsReadOnly

        VStack(spacing: 5) {
            appIcon

            capsule(isReadOnly: isReadOnly)

            HStack(spacing: 2) {
                muteButton(isReadOnly: isReadOnly)

                outputButton(isReadOnly: isReadOnly)
            }
        }
        .frame(width: Self.width)
        .contextMenu {
            if Self.offersReturnToNative(app, isReadOnly: isReadOnly) {
                Button(String(localized: "Return to native audio", bundle: .module)) {
                    model.returnToNative(app: app.identity)
                }
            }
        }
        .task(id: app.identity) {
            await icons.load(app.identity.bundleID)
        }
    }

    // MARK: - Pieces

    private var appIcon: some View {
        Group {
            if let image = icons.icon(for: app.identity.bundleID) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .overlay(alignment: .bottomTrailing) {
            if app.isRecovering {
                Image(systemName: "arrow.triangle.circlepath")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Circle().fill(Color(white: 0.1)))
                    .offset(x: 4, y: 3)
            }
        }
        .help(app.displayName)
        .accessibilityHidden(true)
    }

    private func capsule(isReadOnly: Bool) -> some View {
        let level = Self.level(of: app, isReadOnly: isReadOnly)

        return AudioVolumeCapsule(
            widthRatio     : 1,
            level          : level,
            isMuted        : Self.isMuted(app, isReadOnly: isReadOnly),
            icon           : nil,
            iconOpacity    : 1,
            isDashed       : Self.isDashed(app, isReadOnly: isReadOnly),
            isAdjusting    : model.adjustingApp == app.identity,
            showsPercentage: false,
            onLevel        : { chosen in
                model.adjust(app: app.identity, to: chosen)
            },
            onEnd          : {
                model.endAdjusting(app: app.identity)
            },
            onClick        : onClick
        )
        .frame(width: Self.capsuleWidth)
        .frame(maxHeight: .infinity)
        .background {
            ScrollWheelReader { deltaY, isPrecise, phase, momentum in
                scroll(
                    level    : level,
                    deltaY   : deltaY,
                    isPrecise: isPrecise,
                    phase    : phase,
                    momentum : momentum
                )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(app.displayName)
        .accessibilityValue(Self.accessibilityValue(of: app, isReadOnly: isReadOnly))
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

            model.adjust(app: app.identity, to: level + step)
            model.endAdjusting(app: app.identity)
        }
    }

    private func muteButton(isReadOnly: Bool) -> some View {
        let isMuted = Self.isMuted(app, isReadOnly: isReadOnly)

        return Button {
            model.toggleMute(app: app.identity)
        } label: {
            Image(systemName: AudioMixerComponent.muteSymbol(isMuted: isMuted))
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    Circle()
                        .fill(isMuted ? Color.white.opacity(0.28) : Color.white.opacity(0.14))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .accessibilityLabel(
            isMuted
                ? String(localized: "Unmute", bundle: .module)
                : String(localized: "Mute", bundle: .module)
        )
    }

    private func outputButton(isReadOnly: Bool) -> some View {
        let outputs = Self.shownOutputUIDs(of: app, system: system)
        let output  = system.outputs.first { $0.uid == outputs.first }

        return Button {
            onOutputTap()
        } label: {
            AudioOutputIconView(icon: AudioOutputIcon.device(for: output))
                .font(.system(size: 8))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    Circle()
                        .fill(isPickerOpen ? Color.white.opacity(0.28) : Color.white.opacity(0.14))
                )
                .overlay(alignment: .topTrailing) {
                    if let badge = AudioMixerComponent.badge(selectedCount: outputs.count) {
                        Text(badge)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color(white: 0.15))
                            .padding(.horizontal, 2)
                            .background(Capsule().fill(.white))
                            .offset(x: 4, y: -3)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isReadOnly)
        .accessibilityLabel(String(localized: "Audio output", bundle: .module))
    }

    /// scroll moves the app's level for one scroll event, the way the system capsule does: a
    /// trackpad's inertia after the fingers lift is ignored, a burst ends with its phase, and a
    /// wheel, which has no phase, makes each notch a burst of its own.
    private func scroll(
        level    : Double,
        deltaY   : Double,
        isPrecise: Bool,
        phase    : NSEvent.Phase,
        momentum : NSEvent.Phase
    ) {
        guard momentum.isEmpty else { return }

        if deltaY != 0 {
            model.adjust(
                app: app.identity,
                to : VolumeGesture.scrolled(level, deltaY: deltaY, isPrecise: isPrecise)
            )
        }
        if phase.isEmpty || phase.contains(.ended) || phase.contains(.cancelled) {
            model.endAdjusting(app: app.identity)
        }
    }

    // MARK: - What the column shows

    /// level is the level the capsule fills to: the app's own, or full while read-only, since
    /// with capture refused the app plays at its native level whatever was asked.
    static func level(
        of app    : AudioAppState,
        isReadOnly: Bool
    ) -> Double {
        isReadOnly ? 1 : app.intent.gain
    }

    static func isMuted(
        _ app     : AudioAppState,
        isReadOnly: Bool
    ) -> Bool {
        !isReadOnly && app.intent.isMuted
    }

    /// isDashed is true for a request nothing enforces. A read-only column asked for nothing the
    /// user can see, so it is not dashed.
    static func isDashed(
        _ app     : AudioAppState,
        isReadOnly: Bool
    ) -> Bool {
        !isReadOnly && app.isIntentUnmet
    }

    /// offersReturnToNative is whether the context menu has its one item: only for an unmet
    /// request, and never while read-only, where every request is moot.
    static func offersReturnToNative(
        _ app     : AudioAppState,
        isReadOnly: Bool
    ) -> Bool {
        !isReadOnly && app.isIntentUnmet
    }

    /// shownOutputUIDs are the outputs the output button speaks for: where the app plays, or,
    /// while AudioHost reports none because it follows the system, the system's own.
    static func shownOutputUIDs(
        of app: AudioAppState,
        system: SystemAudioState
    ) -> [String] {
        app.effectiveOutputUIDs.isEmpty ? system.selectedUIDs : app.effectiveOutputUIDs
    }

    /// accessibilityValue is what VoiceOver reads after the app's name: the level, and why it may
    /// not hold.
    static func accessibilityValue(
        of app    : AudioAppState,
        isReadOnly: Bool
    ) -> String {
        let percent = "\(Int((level(of: app, isReadOnly: isReadOnly) * 100).rounded()))%"

        if isDashed(app, isReadOnly: isReadOnly) {
            return percent + ", " + String(localized: "Not applied", bundle: .module)
        }
        if app.isRecovering {
            return percent + ", " + String(localized: "Recovering", bundle: .module)
        }

        return percent
    }
}
