//
//  MediaLiveActivity.swift
//  Cascade
//

import AppKit
import CascadeKit
import Observation
import SwiftUI

/// Metadata invalidates the activity; PCM frames only update the small bar view.
/// Capture and artwork decoding exist only while the host presents this session.
@MainActor
final class MediaLiveActivity: NotchLiveActivity {
    let id = "cascade.now-playing.\(UUID().uuidString)"
    let sourceID = "cascade.media"
    let privacy: NotchActivityPrivacy = .standard
    let lifetime: NotchActivityLifetime
    private(set) var contentRevision: UInt64 = 0
    var expandedContentHeight: CGFloat { 144 }
    var compactPreferredSideWidth: CGFloat? { 40 }
    var accessibilityLabel: String {
        "\(snapshot.title), di \(snapshot.artist), \(snapshot.isPlaying ? "in riproduzione" : "in pausa")"
    }

    private var snapshot: NowPlayingSnapshot
    private var context: LiveActivityContext?
    private let send: (MediaCommand, NowPlayingSnapshot) async throws -> Void
    private let spectrum: (any AudioSpectrumMonitoring)?
    private let visual = MusicVisualState()
    private let presentation: MusicPlaybackPresentation
    private var decodedArtworkData: Data?
    private var audioEnabled: Bool
    private var spectrumTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private let spacebar = MusicSpacebarTap()

    init(snapshot: NowPlayingSnapshot,
         lifetime: NotchActivityLifetime = NotchActivityLifetime(),
         spectrum: (any AudioSpectrumMonitoring)? = nil,
         audioEnabled: Bool = true,
         send: @escaping (MediaCommand, NowPlayingSnapshot) async throws -> Void) {
        self.snapshot = snapshot
        self.presentation = MusicPlaybackPresentation(snapshot: snapshot)
        self.lifetime = lifetime
        self.spectrum = spectrum
        self.audioEnabled = audioEnabled
        self.send = send
        spacebar.onToggle = { [weak self] in self?.toggleFromSpacebar() }
    }

    func update(_ snapshot: NowPlayingSnapshot) {
        guard snapshot != self.snapshot else { return }
        let old = self.snapshot
        self.snapshot = snapshot
        presentation.receive(snapshot)
        if context != nil {
            if old.artworkData != snapshot.artworkData { loadArtwork() }
            if old.isPlaying != snapshot.isPlaying || old.sourceBundleIdentifier != snapshot.sourceBundleIdentifier { restartSpectrum() }
        }
        contentRevision &+= 1
        context?.invalidate()
    }

    func setAudioEnabled(_ enabled: Bool) {
        guard audioEnabled != enabled else { return }
        audioEnabled = enabled
        restartSpectrum()
    }
    func retryAudioCapture() { restartSpectrum() }

    /// Retain the last cover as a widget when the player ends its session.
    /// Commands need a fresh player snapshot; old track metadata cannot authorize them.
    func markPlaybackStopped() {
        let stoppedAt = Date.now
        update(NowPlayingSnapshot(
            sourceBundleIdentifier: snapshot.sourceBundleIdentifier,
            title                 : snapshot.title,
            artist                : snapshot.artist,
            isPlaying             : false,
            duration              : snapshot.duration,
            elapsed               : snapshot.position(at: stoppedAt),
            timestamp             : stoppedAt,
            capabilities          : [],
            artworkData           : snapshot.artworkData,
            trackIdentifier       : snapshot.trackIdentifier,
            isFavorite            : snapshot.isFavorite
        ))
    }

    func activate(in context: LiveActivityContext) {
        let wasVisible = self.context != nil
        self.context = context
        guard !wasVisible else { return }
        loadArtwork()
        restartSpectrum()
    }

    func suspend() {
        context = nil
        spacebar.stop()
        spectrumTask?.cancel()
        spectrumTask = nil
        spectrum?.stop()
        artworkTask?.cancel()
        artworkTask = nil
        // Keep one decoded thumbnail for immediate reopening. Capture and
        // decoding tasks still stop while hidden.
        visual.bands = AudioSpectrumFrame.silence.bands
    }

    func makeCompactLeadingView(in context: NotchActivityViewContext) -> AnyView {
        let size = max(0, min(22, context.availableSize.width, context.availableSize.height))
        return AnyView(
            MusicArtwork(visual: visual, size: size, isCompact: true)
                .frame(width: context.availableSize.width, height: context.availableSize.height, alignment: .trailing)
                .accessibilityLabel(accessibilityLabel)
        )
    }
    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            MusicSpectrumBars(visual: visual, width: min(25, context.availableSize.width), height: min(18, context.availableSize.height), isCompact: true)
                .frame(width: context.availableSize.width, height: context.availableSize.height, alignment: .leading)
        )
    }
    func makeMinimalView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            MusicSpectrumBars(
                visual   : visual,
                width    : min(25, context.availableSize.width),
                height   : min(18, context.availableSize.height),
                isCompact: true
            )
            .frame(width: context.availableSize.width, height: context.availableSize.height)
        )
    }
    func makeExpandedView(in context: NotchActivityViewContext) -> AnyView {
        let displayed = snapshot
        // Reference: 198 px artwork / 33 px title glyphs. The same title at
        // 15 pt renders 22 px tall at 2×, so its matching artwork is 66 pt.
        let artworkSize = max(0, min(66, (context.availableSize.width - (context.hardwareNotchWidth ?? 0)) / 2))
        return AnyView(MusicActivityContent(presentation: presentation, visual: visual, artworkSize: artworkSize, isStale: context.isStale, spacebar: spacebar, send: { [send] command in
            try await send(command, displayed)
        })
            .frame(width: context.availableSize.width, height: context.availableSize.height, alignment: .top)
            .accessibilityElement(children: .contain).accessibilityLabel(accessibilityLabel))
    }

    /// toggleFromSpacebar is the play/pause button pressed from the keyboard:
    /// the same immediate feedback, sent for the track shown right now rather
    /// than the one the view last rendered.
    private func toggleFromSpacebar() {
        let displayed = presentation.displayed
        guard displayed.capabilities.contains(.togglePlayback),
              let id = presentation.begin(.togglePlayback, capability: .togglePlayback) else { return }
        Task(priority: .userInitiated) { [weak self, send] in
            do {
                try await send(.togglePlayback, displayed)
                self?.presentation.succeed(id)
            } catch {
                self?.presentation.fail(id)
            }
        }
    }

    private func restartSpectrum() {
        spectrumTask?.cancel()
        spectrumTask = nil
        spectrum?.stop()
        visual.bands = AudioSpectrumFrame.silence.bands
        guard context != nil, snapshot.isPlaying, audioEnabled, let spectrum else { return }
        let stream = spectrum.start(sourceBundleIdentifier: snapshot.sourceBundleIdentifier)
        spectrumTask = Task { [weak self] in
            for await frame in stream {
                guard !Task.isCancelled, let self, self.context != nil else { return }
                self.visual.bands = frame.bands
            }
        }
    }

    private func loadArtwork() {
        guard decodedArtworkData != snapshot.artworkData || visual.artwork == nil else { return }
        artworkTask?.cancel()
        decodedArtworkData = nil
        visual.artwork = nil
        visual.pausedArtwork = nil
        visual.palette = [.gray, .gray]
        visual.artworkColors = []
        guard let data = snapshot.artworkData else { return }
        artworkTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .utility) { MusicArtworkDecoder.decode(data) }.value
            guard !Task.isCancelled, let self, self.context != nil, let decoded else { return }
            self.decodedArtworkData = data
            self.visual.artwork = NSImage(cgImage: decoded.image, size: NSSize(width: decoded.image.width, height: decoded.image.height))
            self.visual.pausedArtwork = NSImage(cgImage: decoded.pausedImage, size: NSSize(width: decoded.pausedImage.width, height: decoded.pausedImage.height))
            self.visual.artworkColors = decoded.colors
            let colors = decoded.colors.map {
                Color(red: $0.red, green: $0.green, blue: $0.blue)
            }
            self.visual.palette = colors.count == 1 ? colors + colors : colors
        }
    }
}

/// MusicVisualState shares a cover palette between the static light and PCM bars.
@MainActor
@Observable
final class MusicVisualState {
    var artwork: NSImage?
    var pausedArtwork: NSImage?
    var bands = AudioSpectrumFrame.silence.bands
    var palette: [Color] = [.gray, .gray]
    var artworkColors: [MusicArtworkColor] = []
}

private struct MusicArtwork: View {
    let visual: MusicVisualState
    let size: CGFloat
    var isCompact = false
    var isPlaying = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let artwork = isPlaying ? visual.artwork : visual.pausedArtwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: size * 0.2).fill(.white.opacity(0.10))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.45, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .background {
            MusicArtworkLight(visual: visual, artworkSize: size, isCompact: isCompact)
                .opacity(isPlaying ? 1 : 0)
        }
        .scaleEffect(isPlaying ? 1 : 0.92)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPlaying)
        .accessibilityHidden(true)
    }
}

/// MusicArtworkLight diffuses the artwork's rounded-square silhouette using
/// concentric contours. Their cumulative alpha falls smoothly to zero at the
/// outer edge, keeping the glow bounded and independent of layer blur clipping.
private struct MusicArtworkLight: View {
    let visual     : MusicVisualState
    let artworkSize: CGFloat
    let isCompact  : Bool

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        if visual.artwork != nil && !reduceTransparency {
            let lightSize = isCompact ? artworkSize * 1.28 : artworkSize + 48
            Canvas { context, size in
                let spread = (lightSize - artworkSize) / 2
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: visual.palette),
                    startPoint: .zero,
                    endPoint  : CGPoint(x: size.width, y: size.height)
                )
                var accumulatedAlpha: CGFloat = 0
                for index in stride(from: 31, through: 0, by: -1) {
                    let progress = CGFloat(index) / 32
                    let outset = spread * CGFloat(index + 1) / 32
                    let alpha = 0.45 * pow(1 - progress, 2)
                    // Compensate for source-over compositing so each contour
                    // reaches its intended opacity instead of adding a rim.
                    context.opacity = (alpha - accumulatedAlpha) / (1 - accumulatedAlpha)
                    let bounds = CGRect(origin: .zero, size: size)
                        .insetBy(dx: spread - outset, dy: spread - outset)
                    let contour = RoundedRectangle(
                        cornerRadius: artworkSize * 0.2 + outset,
                        style       : .continuous
                    )
                    context.fill(contour.path(in: bounds), with: shading)
                    accumulatedAlpha = alpha
                }
            }
            .frame(width: lightSize, height: lightSize)
            .opacity(isCompact ? 0.18 : 0.65)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// MusicSpectrumBars uses one album gradient across all six measured bands.
/// The resting height equals the width, so silence resolves into round dots.
private struct MusicSpectrumBars: View {
    let visual: MusicVisualState
    let width : CGFloat
    let height: CGFloat
    var isCompact = false

    @Environment(\.displayScale)
    private var displayScale
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        let scale = max(1, displayScale)
        let barWidth = (max(0, min(2.4, width / 12, height)) * scale).rounded() / scale
        let stride = max(0, (width - barWidth) / 5)
        let bars = LinearGradient(
            colors    : visual.palette,
            startPoint: .leading,
            endPoint  : .trailing
        )
        .mask {
            ZStack(alignment: .topLeading) {
                ForEach(0..<6) { index in
                    let barHeight = max(barWidth, (height * CGFloat(visual.bands[index]) * scale).rounded() / scale)
                    Capsule(style: .circular)
                        .frame(
                            width : barWidth,
                            height: barHeight
                        )
                        // Equal dimensions alone are not enough at this size:
                        // fractional origins rasterize circles as flattened dots.
                        .offset(
                            x: (CGFloat(index) * stride * scale).rounded() / scale,
                            y: ((height - barHeight) / 2 * scale).rounded() / scale
                        )
                }
            }
            .frame(width: max(0, width), height: max(0, height), alignment: .topLeading)
        }
        .frame(width: max(0, width), height: max(0, height))

        bars
            .background {
                if isCompact && !reduceTransparency {
                    bars.blur(radius: 1.2).opacity(0.2).allowsHitTesting(false)
                }
            }
        .animation(reduceMotion ? nil : .linear(duration: 1.0 / 30), value: visual.bands)
        .accessibilityHidden(true)
    }
}

private struct MusicActivityContent: View {
    let presentation: MusicPlaybackPresentation
    private var snapshot: NowPlayingSnapshot { presentation.displayed }
    let visual: MusicVisualState
    let artworkSize: CGFloat
    let isStale: Bool
    let spacebar: MusicSpacebarTap
    let send: (MediaCommand) async throws -> Void
    private var pendingCapability: MediaCommandCapabilities? { presentation.pendingCapability }
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    private var commandError: String? { presentation.commandError }
    @State private var isScrubbing = false
    @State private var scrubPosition: Double = 0
    @State private var previousTrackTrigger = 0
    @State private var nextTrackTrigger = 0

    private var isSending: Bool { pendingCapability != nil }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                MusicArtwork(visual: visual, size: artworkSize, isPlaying: snapshot.isPlaying)
                    .frame(height: 66, alignment: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Text(snapshot.artist).font(.system(size: 13, weight: .regular)).foregroundStyle(.white.opacity(0.55))
                }
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                MusicSpectrumBars(visual: visual, width: 29, height: 27)
            }
            if let duration = snapshot.duration {
                Group {
                    if snapshot.isPlaying && !isStale {
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            progress(at: timeline.date, duration: duration)
                        }
                    } else {
                        progress(at: snapshot.timestamp, duration: duration)
                    }
                }.frame(height: 18)
            } else {
                Text("In diretta").font(.callout).foregroundStyle(.secondary).frame(height: 18)
            }
            HStack(spacing: 0) {
                control(snapshot.isFavorite == true ? "star.fill" : "star", label: snapshot.isFavorite == true ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti", command: .toggleFavorite, capability: .favorite, size: 19, subdued: true)
                Spacer(minLength: 12)
                control("backward.fill", label: "Brano precedente", command: .previousTrack, capability: .previousTrack, size: 25)
                Spacer(minLength: 12)
                control(snapshot.isPlaying ? "pause.fill" : "play.fill", label: snapshot.isPlaying ? "Pausa" : "Riproduci", command: .togglePlayback, capability: .togglePlayback, size: 30)
                Spacer(minLength: 12)
                control("forward.fill", label: "Brano successivo", command: .nextTrack, capability: .nextTrack, size: 25)
                Spacer(minLength: 12)
                AudioOutputPicker().frame(width: 36, height: 36)
            }.frame(height: 36)
        }
        .foregroundStyle(.white)
        .background {
            MusicGlassLightEmitter(visual: visual, isPlaying: snapshot.isPlaying && !isStale)
        }
        // The space bar plays and pauses only while this player is on screen.
        .onAppear { spacebar.start() }
        .onDisappear { spacebar.stop() }
        .overlay(alignment: .bottom) {
            if let commandError {
                Text(commandError).font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 8).background(.black).offset(y: 13)
            }
        }
    }

    private func control(_ symbol: String, label: String, command: MediaCommand, capability: MediaCommandCapabilities, size: CGFloat, subdued: Bool = false) -> some View {
        let supported = snapshot.capabilities.contains(capability) && !isStale
        let isPending = pendingCapability == capability
        return Button { perform(command, capability: capability) } label: {
            MusicControlSymbol(
                symbol: symbol,
                size: size,
                trigger: capability == .nextTrack ? nextTrackTrigger : previousTrackTrigger,
                reduceMotion: reduceMotion
            )
                .foregroundStyle(.white.opacity(supported ? (subdued ? 0.6 : 1) : 0.25))
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(MusicControlButtonStyle())
        .disabled(!supported || isSending)
        .accessibilityLabel(label)
        .accessibilityValue(isPending ? "Comando in corso" : "")
        .help(supported ? label : "\(label): non disponibile in questo player")
    }

    private func progress(at date: Date, duration: TimeInterval) -> some View {
        let position = isScrubbing ? scrubPosition : snapshot.position(at: date)
        return HStack(spacing: 8) {
            Text(timestamp(position)).frame(minWidth: 32, alignment: .leading)
            MusicProgressSlider(
                position : position,
                duration : duration,
                isEnabled: snapshot.capabilities.contains(.seek) && !isStale && !isSending,
                onPreview: { value in
                    scrubPosition = value
                    isScrubbing = true
                },
                onCommit: { value in
                    isScrubbing = false
                    perform(.seek(value), capability: .seek)
                },
                onCancel: { isScrubbing = false },
                trackIdentity: [snapshot.sourceBundleIdentifier, snapshot.trackIdentifier ?? "", snapshot.title, snapshot.artist]
            )
            Text("−" + timestamp(duration - position)).frame(minWidth: 38, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .regular)).monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
    }

    private func perform(
        _ command: MediaCommand,
        capability: MediaCommandCapabilities
    ) {
        guard let id = presentation.begin(command, capability: capability) else { return }
        switch command {
        case .nextTrack: nextTrackTrigger &+= 1
        case .previousTrack: previousTrackTrigger &+= 1
        default: break
        }
        Task(priority: .userInitiated) { @MainActor in
            do {
                try await send(command)
                presentation.succeed(id)
            } catch {
                presentation.fail(id)
            }
        }
    }
    private func timestamp(_ seconds: TimeInterval) -> String {
        let value = Int(min(86_400, max(0, seconds)))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

/// A brief press response precedes the symbol's one-shot animation. Neither
/// feedback depends on the player reply or delays command dispatch.
private struct MusicControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
