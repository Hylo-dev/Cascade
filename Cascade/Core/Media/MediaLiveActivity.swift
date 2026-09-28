//
//  MediaLiveActivity.swift
//  Cascade
//

import AppKit
import CascadeKit
import SwiftUI

/// MediaLiveActivity is invalidated by metadata changes; PCM frames only update
/// the small bar view.
/// Capture and artwork decoding exist only while the host presents this session.
@MainActor
final class MediaLiveActivity: NotchLiveActivity {

    let id       = "cascade.now-playing.\(UUID().uuidString)"
    let sourceID = "cascade.media"
    let privacy : NotchActivityPrivacy = .standard
    let lifetime: NotchActivityLifetime

    private(set) var contentRevision: UInt64 = 0

    var expandedContentHeight    : CGFloat { 144 }
    var compactPreferredSideWidth: CGFloat? { 40 }

    var accessibilityLabel: String {
        "\(snapshot.title), di \(snapshot.artist), \(snapshot.isPlaying ? "in riproduzione" : "in pausa")"
    }

    private var snapshot: NowPlayingSnapshot

    var sourceBundleIdentifier: String { snapshot.sourceBundleIdentifier }

    private var context: LiveActivityContext?

    private let send        : (MediaCommand, NowPlayingSnapshot) async throws -> Void
    private let spectrum    : (any AudioSpectrumMonitoring)?
    private let visual       = MusicVisualState()
    private let presentation: MusicPlaybackPresentation

    private var decodedArtworkData: Data?
    private var audioEnabled      : Bool
    private var spectrumTask      : Task<Void, Never>?
    private var spectrumPauseTask : Task<Void, Never>?
    private var artworkTask       : Task<Void, Never>?

    private let spacebar = MusicSpacebarTap()

    init(
        snapshot    : NowPlayingSnapshot,
        lifetime    : NotchActivityLifetime = NotchActivityLifetime(),
        spectrum    : (any AudioSpectrumMonitoring)? = nil,
        audioEnabled: Bool = true,
        send        : @escaping (MediaCommand, NowPlayingSnapshot) async throws -> Void
    ) {
        self.snapshot     = snapshot
        self.presentation = MusicPlaybackPresentation(snapshot: snapshot)
        self.lifetime     = lifetime
        self.spectrum     = spectrum
        self.audioEnabled = audioEnabled
        self.send         = send

        spacebar.onToggle = { [weak self] in self?.toggleFromSpacebar() }
    }

    func update(_ snapshot: NowPlayingSnapshot) {
        guard snapshot != self.snapshot else { return }

        let previous  = self.snapshot
        self.snapshot = snapshot
        presentation.receive(snapshot)

        if context != nil {
            if previous.artworkData != snapshot.artworkData { loadArtwork() }
            if previous.sourceBundleIdentifier != snapshot.sourceBundleIdentifier {
                restartSpectrum()
            } else if previous.isPlaying != snapshot.isPlaying {
                spectrumFollowPlayback()
            }
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

    /// markPlaybackStopped retains the last cover as a widget when the player ends its
    /// session.
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
        self.context   = context
        guard !wasVisible else { return }

        loadArtwork()
        restartSpectrum()
    }

    func suspend() {
        context = nil
        spacebar.stop()

        spectrumPauseTask?.cancel()
        spectrumPauseTask = nil

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
            MusicArtwork(
                visual   : visual,
                size     : size,
                isCompact: true
            )
            .frame(
                width    : context.availableSize.width,
                height   : context.availableSize.height,
                alignment: .trailing
            )
            .accessibilityLabel(accessibilityLabel)
        )
    }

    func makeCompactTrailingView(in context: NotchActivityViewContext) -> AnyView {
        AnyView(
            MusicSpectrumBars(
                visual   : visual,
                width    : min(25, context.availableSize.width),
                height   : min(18, context.availableSize.height),
                isCompact: true
            )
            .frame(
                width    : context.availableSize.width,
                height   : context.availableSize.height,
                alignment: .leading
            )
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

        return AnyView(
            MusicActivityContent(
                presentation: presentation,
                visual      : visual,
                artworkSize : artworkSize,
                isStale     : context.isStale,
                spacebar    : spacebar,
                send        : { [send] command in
                    try await send(command, displayed)
                }
            )
            .frame(
                width    : context.availableSize.width,
                height   : context.availableSize.height,
                alignment: .top
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
        )
    }

    /// toggleFromSpacebar is the play/pause button pressed from the keyboard:
    /// the same immediate feedback, sent for the track shown right now rather
    /// than the one the view last rendered.
    private func toggleFromSpacebar() {
        let displayed = presentation.displayed

        guard displayed.capabilities.contains(.togglePlayback),
              let id = presentation.begin(.togglePlayback, capability: .togglePlayback)
        else { return }

        Task(priority: .userInitiated) { [weak self, send] in
            do {
                try await send(.togglePlayback, displayed)
                self?.presentation.succeed(id)
            } catch {
                self?.presentation.fail(id)
            }
        }
    }

    /// spectrumFollowPlayback keeps the capture through a short pause. Every
    /// restart builds a private process tap, an aggregate device and an IO
    /// callback in Core Audio; toggling from the keyboard rebuilt them on each
    /// press. A pause now stops capture only once it has lasted a few seconds,
    /// and resuming inside that window keeps the running capture, which has
    /// meanwhile measured the pause's silence.
    private func spectrumFollowPlayback() {
        spectrumPauseTask?.cancel()
        spectrumPauseTask = nil

        guard !snapshot.isPlaying else {
            if spectrumTask == nil { restartSpectrum() }
            return
        }
        guard spectrumTask != nil else { return }

        spectrumPauseTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, !self.snapshot.isPlaying else { return }

            self.spectrumPauseTask = nil
            self.restartSpectrum()
        }
    }

    private func restartSpectrum() {
        spectrumPauseTask?.cancel()
        spectrumPauseTask = nil

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

    /// loadArtwork keeps the previous cover, palette and light until the next
    /// one is decoded, so a track change crossfades cover to cover rather than
    /// flashing the placeholder for the few milliseconds of a decode.
    private func loadArtwork() {
        guard decodedArtworkData != snapshot.artworkData || visual.artwork == nil else { return }

        artworkTask?.cancel()
        decodedArtworkData = nil

        guard let data = snapshot.artworkData else {
            clearArtwork()
            return
        }

        artworkTask = Task { [weak self] in
            let decoded = await Task.detached(priority: .utility) {
                MusicArtworkDecoder.decode(data)
            }.value
            guard !Task.isCancelled, let self, self.context != nil else { return }
            guard let decoded else {
                self.clearArtwork()
                return
            }

            self.decodedArtworkData = data
            self.visual.artwork     = NSImage(
                cgImage: decoded.image,
                size   : NSSize(width: decoded.image.width, height: decoded.image.height)
            )

            self.visual.artworkColors = decoded.colors
            self.visual.compactGlow   = decoded.glow.map {
                NSImage(
                    cgImage: $0,
                    size   : NSSize(
                        width : MusicArtworkDecoder.compactGlowSize,
                        height: MusicArtworkDecoder.compactGlowSize
                    )
                )
            }

            let colors = decoded.colors.map {
                Color(red: $0.red, green: $0.green, blue: $0.blue)
            }
            self.visual.palette = colors.count == 1 ? colors + colors : colors
        }
    }

    private func clearArtwork() {
        visual.artwork       = nil
        visual.compactGlow   = nil
        visual.palette       = [.gray, .gray]
        visual.artworkColors = []
    }
}
