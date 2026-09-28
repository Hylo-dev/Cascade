//
//  MusicActivityContent.swift
//  Cascade
//

import AppKit
import CascadeKit
import SwiftUI

struct MusicActivityContent: View {

    let presentation: MusicPlaybackPresentation

    private var snapshot: NowPlayingSnapshot { presentation.displayed }

    let visual     : MusicVisualState
    let artworkSize: CGFloat
    let isStale    : Bool
    let spacebar   : MusicSpacebarTap
    let send       : (MediaCommand) async throws -> Void

    private var pendingCapability: MediaCommandCapabilities? { presentation.pendingCapability }

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private var commandError: String? { presentation.commandError }

    @State
    private var isScrubbing          = false
    @State
    private var scrubPosition       : Double = 0
    @State
    private var previousTrackTrigger = 0
    @State
    private var nextTrackTrigger     = 0

    private var isSending: Bool { pendingCapability != nil }

    /// The track the text belongs to; a new one animates the title and artist.
    private var trackIdentity: String {
        [snapshot.sourceBundleIdentifier, snapshot.trackIdentifier ?? snapshot.title, snapshot.artist]
            .joined(separator: "\u{1f}")
    }

    var body: some View {
        VStack(spacing: 12) {

            HStack(spacing: 16) {

                MusicArtwork(
                    visual   : visual,
                    size     : artworkSize,
                    isPlaying: snapshot.isPlaying,
                    isStale  : isStale
                )
                .frame(height: 66, alignment: .bottom)

                // The outgoing title and artist rise and blur away as the new
                // pair rises into place; both overlap for the transition.
                ZStack(alignment: .leading) {

                    VStack(alignment: .leading, spacing: 4) {

                        Text(snapshot.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)

                        Text(snapshot.artist)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .id(trackIdentity)
                    .transition(MusicTrackTransition.text(reduceMotion: reduceMotion))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(
                    MusicTrackTransition.animation(reduceMotion: reduceMotion),
                    value: trackIdentity
                )

                MusicSpectrumBars(
                    visual: visual,
                    width : 29,
                    height: 27
                )
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
                }
                .frame(height: 18)
            } else {
                Text("In diretta")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(height: 18)
            }

            HStack(spacing: 0) {

                control(
                    snapshot.isFavorite == true ? "star.fill" : "star",
                    label     : snapshot.isFavorite == true ? "Rimuovi dai preferiti" : "Aggiungi ai preferiti",
                    command   : .toggleFavorite,
                    capability: .favorite,
                    size      : 19,
                    subdued   : true
                )

                Spacer(minLength: 12)

                control(
                    "backward.fill",
                    label     : "Brano precedente",
                    command   : .previousTrack,
                    capability: .previousTrack,
                    size      : 25
                )

                Spacer(minLength: 12)

                control(
                    snapshot.isPlaying ? "pause.fill" : "play.fill",
                    label     : snapshot.isPlaying ? "Pausa" : "Riproduci",
                    command   : .togglePlayback,
                    capability: .togglePlayback,
                    size      : 30
                )

                Spacer(minLength: 12)

                control(
                    "forward.fill",
                    label     : "Brano successivo",
                    command   : .nextTrack,
                    capability: .nextTrack,
                    size      : 25
                )

                Spacer(minLength: 12)

                AudioOutputPicker()
                    .frame(width: 36, height: 36)
            }
            .frame(height: 36)
        }
        .foregroundStyle(.white)
        // The space bar plays and pauses only while this player is on screen.
        .onAppear { spacebar.start() }
        .onDisappear { spacebar.stop() }
        .overlay(alignment: .bottom) {
            if let commandError {
                Text(commandError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .background(.black)
                    .offset(y: 13)
            }
        }
    }

    private func control(
        _ symbol  : String,
        label     : String,
        command   : MediaCommand,
        capability: MediaCommandCapabilities,
        size      : CGFloat,
        subdued   : Bool = false
    ) -> some View {
        let supported = snapshot.capabilities.contains(capability) && !isStale
        let isPending = pendingCapability == capability

        return Button { perform(command, capability: capability) } label: {
            MusicControlSymbol(
                symbol      : symbol,
                size        : size,
                trigger     : capability == .nextTrack ? nextTrackTrigger : previousTrackTrigger,
                reduceMotion: reduceMotion
            )
            .foregroundStyle(.white.opacity(supported ? (subdued ? 0.6 : 1) : 0.25))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(MusicControlButtonStyle())
        .disabled(!supported || isSending)
        .accessibilityLabel(label)
        .accessibilityValue(isPending ? "Comando in corso" : "")
        .help(supported ? label : "\(label): non disponibile in questo player")
    }

    private func progress(
        at date : Date,
        duration: TimeInterval
    ) -> some View {
        let position = isScrubbing ? scrubPosition : snapshot.position(at: date)
        // Only the digits that change roll, up for the elapsed time and down
        // for the remaining one, once a second; never while scrubbing.
        let rolls = !isScrubbing && !reduceMotion

        return HStack(spacing: 8) {

            MusicTimeLabel(
                text      : timestamp(position),
                countsDown: false,
                animates  : rolls
            )
            .frame(minWidth: 32, alignment: .leading)
            .accessibilityLabel(timestamp(position))

            MusicProgressSlider(
                position     : position,
                duration     : duration,
                isEnabled    : snapshot.capabilities.contains(.seek) && !isStale && !isSending,
                onPreview    : { value in
                    scrubPosition = value
                    isScrubbing   = true
                },
                onCommit     : { value in
                    isScrubbing = false
                    perform(.seek(value), capability: .seek)
                },
                onCancel     : { isScrubbing = false },
                trackIdentity: [
                    snapshot.sourceBundleIdentifier,
                    snapshot.trackIdentifier ?? "",
                    snapshot.title,
                    snapshot.artist
                ]
            )

            MusicTimeLabel(
                text      : "−" + timestamp(duration - position),
                countsDown: true,
                animates  : rolls
            )
            .frame(minWidth: 38, alignment: .trailing)
            .accessibilityLabel("−" + timestamp(duration - position))
        }
        .font(.system(size: 11, weight: .regular))
        .monospacedDigit()
        .foregroundStyle(.white.opacity(0.55))
    }

    private func perform(
        _ command : MediaCommand,
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
