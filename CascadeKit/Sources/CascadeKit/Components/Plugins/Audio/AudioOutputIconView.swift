//
//  AudioOutputIconView.swift
//  CascadeKit
//

import SwiftUI

/// AudioOutputIconView draws what `AudioOutputIcon` decided: the speaker with the waves the level
/// reaches, the muted speaker, or a system symbol, the Bluetooth product's included. It is a
/// switch and nothing more; the choice was made, and tested, away from any view. A symbol takes
/// its colour from the capsule, which inks it for the fill it sits on.
///
/// The speaker behaves as the system's own volume does. It shows a wave for each third of the
/// level (`AudioOutputIcon.speakerWaveCount`) and holds still between the thresholds, however
/// the level moves. When one is crossed, the new wave fades in, or the last one out, and the
/// icon, which stays centred, glides to its new width, both on one smooth animation: the body
/// moves only then, and never creeps with the level. The waves are a lighter tone of the body
/// (hierarchical rendering), and so is the slash of the muted speaker. Going to and from mute is
/// a magic replace: the slash is drawn off as the speaker comes back, and drawn on as it goes.
///
/// Each wave is its own layer: the speaker with that many waves, with the speaker one wave
/// shorter cut out of it, so the layer holds that wave alone and fades on its own. A symbol's
/// frame is wider than its ink, so the cut is by the glyph, not by a width. The layers are
/// placed at the leading edge by `SpeakerWavesLayout`, whose width follows the animated count.
struct AudioOutputIconView: View {

    /// muting is the slash coming on or off.
    private static let muting = Animation.smooth(duration: 0.4)

    /// waving is a wave coming in or going out, with the glide of the icon to its new width.
    private static let waving = Animation.smooth(duration: 0.3)

    /// slashTone is how much of the ink the mute slash takes: the system draws it a lighter grey
    /// than the speaker it crosses.
    private static let slashTone = 0.5

    let icon: AudioOutputIcon

    /// ink is the colour the capsule gives the speaker; without one, as for the output buttons'
    /// symbols, the environment's style applies.
    var ink: Color? = nil

    /// body keeps the speaker's states in one branch: a `switch` with a case for the level and
    /// one for mute would be two views, and going from one to the other would swap them instead
    /// of replacing the symbol.
    var body: some View {
        if case .symbol(let name) = icon {
            Image(systemName: AudioOutputSymbol.installedName(for: name))
        } else {
            speaker
        }
    }

    /// speaker is the body, or the slashed body when muted, and the three wave layers over it.
    private var speaker: some View {
        let isMuted = icon == .muted
        let count   = Self.waveCount(of: icon)
        let tone    = ink.map(AnyShapeStyle.init) ?? AnyShapeStyle(.foreground)

        return SpeakerWavesLayout(shownWaves: Double(count)) {
            Image(systemName: isMuted ? "speaker.slash.fill" : AudioOutputIcon.speakerSymbol(waves: 0))
                .symbolRenderingMode(isMuted ? .palette : .hierarchical)
                .foregroundStyle(
                    isMuted ? AnyShapeStyle(tone.opacity(Self.slashTone)) : tone,
                    tone
                )
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .animation(Self.muting, value: isMuted)

            ForEach(1...3, id: \.self) { wave in
                Self.wave(wave, tone: tone)
                    .opacity(wave <= count ? 1 : 0)
            }
        }
        .animation(Self.waving, value: count)
    }

    /// wave is the layer that holds the `index`th wave alone: the speaker with that many waves,
    /// with the speaker one wave shorter cut out.
    private static func wave(
        _ index: Int,
        tone   : AnyShapeStyle
    ) -> some View {
        Image(systemName: AudioOutputIcon.speakerSymbol(waves: index))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tone)
            .mask(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle()

                    Image(systemName: AudioOutputIcon.speakerSymbol(waves: index - 1))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.black)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .accessibilityHidden(true)
    }

    /// waveCount is how many waves show: none while muted.
    private static func waveCount(of icon: AudioOutputIcon) -> Int {
        guard case .speaker(let level) = icon else { return 0 }

        return AudioOutputIcon.speakerWaveCount(level: level)
    }
}

/// SpeakerWavesLayout lays the body and its wave layers out at the leading edge and reports the
/// width of the speaker with `shownWaves` waves. The count is animatable, so when a wave comes
/// in the reported width grows smoothly from one symbol's width to the next, and the frame
/// around the layout, which centres it, glides the body left; nothing moves between changes.
/// The subviews are the body first, then the speakers with one, two and three waves, so each
/// one's ideal size is a symbol's width, measured by SwiftUI in the capsule's font.
private struct SpeakerWavesLayout: Layout {

    var shownWaves: Double

    var animatableData: Double {
        get { shownWaves }
        set { shownWaves = newValue }
    }

    func sizeThatFits(
        proposal   : ProposedViewSize,
        subviews   : Subviews,
        cache      : inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard !sizes.isEmpty else { return .zero }

        let shown = Swift.min(Swift.max(shownWaves, 0), Double(sizes.count - 1))
        let lower = Int(shown.rounded(.down))
        let upper = Swift.min(lower + 1, sizes.count - 1)
        let reach = CGFloat(shown - Double(lower))
        let width = sizes[lower].width + (sizes[upper].width - sizes[lower].width) * reach

        return CGSize(
            width : width,
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(
        in bounds  : CGRect,
        proposal   : ProposedViewSize,
        subviews   : Subviews,
        cache      : inout ()
    ) {
        for subview in subviews {
            subview.place(
                at      : CGPoint(x: bounds.minX, y: bounds.midY),
                anchor  : .leading,
                proposal: .unspecified
            )
        }
    }
}
