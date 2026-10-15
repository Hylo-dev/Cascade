//
//  AudioMixerComponent.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

/// AudioMixerComponent is the tier-2 component audio.mixer, the whole body of the audio widget's
/// detail page. The page is only as tall as the notch's ordinary expanded surface, so it is laid
/// out around the hardware notch (`pluginPageObstruction`) instead of under a title bar. In the
/// notch's left shoulder, beside the back button, sits one row: "Audio" and the level. Below the
/// shoulder, the global column (the level as a capsule, with the output button and the mute
/// button beside it), a divider, and the apps area: a horizontal row of `AudioAppColumn`s, one
/// per app that plays audio, or, until one does, a line saying where they will appear. When the
/// system has refused audio capture the line becomes a button to System Settings, above the
/// columns if there are any, which are then read-only.
///
/// The output buttons, the system's and each app's, open the output selector in the apps area,
/// beside the global column. Which selector is open is local state of this view: nothing outside
/// it cares, and nothing is kept once the page closes. A press on a capsule or on the empty apps
/// area closes it; Escape is not handled here, since the detail page already takes it to close
/// the whole page.
///
/// The page tells the model whether it is on screen, because AudioHost runs while the mixer is
/// visible, even if every app is untouched, and rests otherwise.
///
/// It draws the same live system state the volume bar does, through the same capsule, so a drag
/// or a scroll feels identical in both places. With no model, or before the first reading, it
/// draws nothing, as the page behind it has nothing to offer yet.
struct AudioMixerComponent: View {

    /// PickerTarget is whose output selector the apps area shows.
    enum PickerTarget: Equatable {

        case system
        case app(AudioAppIdentity)

        /// app is the app a selector belongs to, nil for the system's own.
        var app: AudioAppIdentity? {
            guard case .app(let identity) = self else { return nil }

            return identity
        }
    }

    /// emptyAppsText is the apps area's empty state, which is also its localization key.
    static let emptyAppsText = "Apps appear here when they play audio"

    /// captureSettingsAddress opens the pane where the user can allow audio capture.
    static let captureSettingsAddress = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    /// titleLeadingInset leaves the back button's room: its 4 pt inset, its 24 pt and a gap.
    static let titleLeadingInset: CGFloat = 30

    /// titleMinimumScale lets the title shrink a little rather than truncate. The row ends at the
    /// hardware notch, and "Audio 100%" only just fits beside it: a wider font setting or a
    /// longer translation of "Audio" would otherwise cut the level to "1…".
    static let titleMinimumScale: CGFloat = 0.85

    /// bandHeightWithoutObstruction is the title row's height where no notch covers the top: the
    /// back button and its insets.
    static let bandHeightWithoutObstruction: CGFloat = 32

    private static let buttonSize  : CGFloat = 20

    /// litColumns is how many app columns light the glass. The glass takes eight lights from
    /// the whole notch: one is the global volume's, up to three are the Music cover's, and four
    /// app lights fill the rest without crowding it.
    static let litColumns = 4

    /// reveal is the fade and slide of the page around the capsule: short, and a beat after the
    /// glide starts, so the eye follows the capsule.
    private static let reveal = Animation.spring(response: 0.38, dampingFraction: 0.9).delay(0.06)

    /// revealTravel is how far the controls beside the capsule slide out from it as they appear,
    /// so the page opens from the capsule rather than popping in around it.
    private static let revealTravel: CGFloat = 14

    @Environment(\.pluginComponentServices)
    private var services

    @Environment(\.pluginPageObstruction)
    private var obstruction

    @State
    private var picker: PickerTarget?

    /// isRevealed fades in everything but the global capsule when the page opens from the
    /// widget, so the capsule, gliding in, arrives first and the rest settles around it. Opened
    /// any other way the page is simply there.
    @State
    private var isRevealed = true

    @State
    private var icons = AudioAppIconCache()

    /// areColumnsOverflowing is whether the app columns are wider than their area, so the row
    /// scrolls; it is read from the scroll view's geometry only when that changes.
    @State
    private var areColumnsOverflowing = false

    var body: some View {
        Group {
            if let model = services?.audio, let system = model.system {
                mixer(model: model, system: system)
            } else {
                Color.clear
            }
        }
        .onAppear {
            services?.audio?.setMixerVisible(true)
            reveal()
        }
        .onDisappear {
            services?.audio?.setMixerVisible(false)
        }
        .onChange(of: services?.audio?.apps) {
            closePickerOfAbsentApp()
        }
    }

    private func mixer(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        let band = Self.bandHeight(obstruction: obstruction)

        return VStack(alignment: .leading, spacing: 0) {
            titleRow(
                level: system.level,
                band : band
            )
            .opacity(isRevealed ? 1 : 0)

            HStack(spacing: 10) {
                AudioGlobalVolumeControl(
                    role           : .mixer,
                    widthRatio     : 1,
                    model          : model,
                    system         : system,
                    showsPercentage: false,
                    onClick        : {
                        picker = nil
                    }
                )
                .aspectRatio(AudioVolumeCapsuleMetrics.aspect, contentMode: .fit)
                .frame(maxHeight: .infinity)

                Group {
                    VStack(spacing: 10) {
                        outputButton(system: system)
                        muteButton(model: model, system: system)
                    }
                    .frame(maxHeight: .infinity)

                    Rectangle()
                        .fill(Color(white: 0.2))
                        .frame(width: 1)
                        .padding(.vertical, 4)

                    appsArea(model: model, system: system)
                }
                .opacity(isRevealed ? 1 : 0)
                .offset(x: isRevealed ? 0 : -Self.revealTravel)
            }
            .padding(.top, 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    /// reveal hides the page around the capsule and brings it back on the next main-actor turn,
    /// once the hidden state has been drawn, when the capsule is arriving from the widget.
    private func reveal() {
        guard services?.audio?.capsuleHandoff.isArriving(.mixer) == true else { return }

        var hidden = Transaction()
        hidden.disablesAnimations = true
        withTransaction(hidden) {
            isRevealed = false
        }
        Task { @MainActor in
            withAnimation(Self.reveal) {
                isRevealed = true
            }
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

            Text("\(Int((level * 100).rounded()))%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(Self.titleMinimumScale)
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
        let icon   = AudioOutputIcon.device(for: output)

        return Button {
            picker = picker == .system ? nil : .system
        } label: {
            AudioOutputIconView(icon: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(
                    Circle()
                        .fill(picker == .system ? Color.white.opacity(0.28) : Color.white.opacity(0.14))
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

    private func appsArea(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    picker = nil
                }

            appsContent(model: model, system: system)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// appsContent is what the apps area shows: an open selector over everything, else the
    /// capture banner when the system refused capture, and the columns, or the empty line when
    /// there are none and nothing to say instead.
    @ViewBuilder
    private func appsContent(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        if let picker {
            AudioOutputPicker(
                model  : model,
                app    : picker.app,
                onClose: {
                    self.picker = nil
                }
            )
            .frame(maxHeight: .infinity)
        } else {
            let isDenied = model.areAppsReadOnly

            VStack(spacing: 6) {
                if isDenied {
                    captureBanner
                }

                if !model.apps.isEmpty {
                    columns(model: model, system: system)
                } else if !isDenied {
                    Text(String(localized: "Apps appear here when they play audio", bundle: .module))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// columns lays the apps side by side. It scrolls only when they do not fit: with room to
    /// spare a horizontal swipe does nothing, not even the rubber band. The first `litColumns`
    /// light the glass while nothing overflows; once the row scrolls the lights would stay where
    /// the columns were, so none of them do.
    private func columns(
        model : AudioMixerModel,
        system: SystemAudioState
    ) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 6) {
                ForEach(Array(model.apps.enumerated()), id: \.element.identity) { index, app in
                    AudioAppColumn(
                        app         : app,
                        system      : system,
                        model       : model,
                        icons       : icons,
                        isPickerOpen: picker == .app(app.identity),
                        isLit       : index < Self.litColumns && !areColumnsOverflowing,
                        onClick     : {
                            picker = nil
                        },
                        onOutputTap : {
                            picker = picker == .app(app.identity) ? nil : .app(app.identity)
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentSize.width > geometry.containerSize.width + 0.5
        } action: { _, isOverflowing in
            areColumnsOverflowing = isOverflowing
        }
        .frame(maxHeight: .infinity)
    }

    /// captureBanner is the one line that replaces the empty state when the system refused audio
    /// capture: it says what to allow, and the line itself opens the pane where to allow it.
    private var captureBanner: some View {
        Button {
            if let address = URL(string: Self.captureSettingsAddress) {
                NSWorkspace.shared.open(address)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")

                Text(String(localized: "Allow audio capture in System Settings", bundle: .module))
                    .underline()
            }
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .buttonStyle(.plain)
    }

    /// closePickerOfAbsentApp closes an app's selector when the app stops playing: there is
    /// nothing left to choose for, and it must not reopen when the app comes back.
    private func closePickerOfAbsentApp() {
        guard
            case .app(let identity) = picker,
            let apps = services?.audio?.apps,
            !apps.contains(where: { $0.identity == identity })
        else { return }

        picker = nil
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
