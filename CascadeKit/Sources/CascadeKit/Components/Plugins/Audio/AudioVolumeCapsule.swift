//
//  AudioVolumeCapsule.swift
//  CascadeKit
//

import SwiftUI

/// AudioVolumeCapsule is the volume control's look and its press: a dark glass capsule that fills
/// with white from the bottom up as the level rises, the output icon sitting inside the fill. The
/// widget draws one and the mixer reuses it, so both feel the same under the finger. The pill's
/// width is a ratio of the frame (`AudioVolumeCapsuleMetrics`), and everything inside scales
/// with it.
///
/// It owns no model. The level comes in, and what the user does goes out through three closures:
/// `onLevel` for each level a drag chooses, `onEnd` once when a drag lets go, and `onClick` for a
/// press that stayed put and was released before the hold duration. `VolumeGesture` decides which
/// is which. The drag is simultaneous, so the tile's own press still sees the hold that starts
/// editing, and a hold neither clicks nor moves the level.
///
/// A level change redraws only the fill's height and the ink; the capsule is not rebuilt. No
/// timers and no animation loop: the only animation is the `.snappy` swell while the user adjusts,
/// driven by `isAdjusting` alone, so dragging the level never animates frame by frame.
struct AudioVolumeCapsule: View {

    /// iconInkOnFill is the light blue the icon takes where the white level fill is behind it,
    /// sRGB (0, 198, 234), matching the user's reference. Anywhere else the icon is white.
    static let iconInkOnFill = Color(
        red  : 0,
        green: 198.0 / 255.0,
        blue : 234.0 / 255.0
    )

    private static let percentageInset: CGFloat = 10

    /// widthRatio is how much of the given width the pill draws, centred. The grid widget passes
    /// 0.6, a thinner pill in the same slots; the mixer passes 1 and fills what it is given. The
    /// press still covers the whole frame, so a thin pill is no harder to grab.
    let widthRatio     : CGFloat
    let level          : Double
    let isMuted        : Bool
    let icon           : AudioOutputIcon?
    /// iconOpacity dims the icon alone, for the unavailable look: the pill stays as it is.
    let iconOpacity    : Double
    let isAdjusting    : Bool
    let showsPercentage: Bool
    let onLevel        : (Double) -> Void
    let onEnd          : () -> Void
    let onClick        : (() -> Void)?

    /// gesture and pressStart are the press in progress, from its first change to its release.
    /// They are plain values, so the view allocates nothing for them however often its parent
    /// rebuilds it; writing them only invalidates the body during a press, when the level is
    /// redrawing it anyway.
    @State
    private var gesture: VolumeGesture?

    @State
    private var pressStart: ContinuousClock.Instant?

    var body: some View {
        GeometryReader { geometry in
            let metrics    = AudioVolumeCapsuleMetrics(
                availableWidth: geometry.size.width,
                widthRatio    : widthRatio
            )
            let height     = geometry.size.height
            let fillHeight = height * CGFloat(min(1, max(0, level)))

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .fill(Color(white: 0.33))

                Rectangle()
                    .fill(isMuted ? Color(white: 0.56) : .white)
                    .frame(height: fillHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))

                if let icon {
                    AudioOutputIconView(icon: icon)
                        .font(.system(size: metrics.symbolFontSize))
                        .foregroundStyle(
                            Self.iconInk(
                                fillHeight: fillHeight,
                                centre    : metrics.iconInset + metrics.iconSize / 2,
                                isMuted   : isMuted
                            )
                        )
                        .opacity(iconOpacity)
                        .frame(width: metrics.iconSize, height: metrics.iconSize)
                        .padding(.bottom, metrics.iconInset)
                }
            }
            .overlay(alignment: .top) {
                if showsPercentage {
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: metrics.percentageFontSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ink(covering: height - Self.percentageInset, fillHeight: fillHeight))
                        .padding(.top, Self.percentageInset)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.cornerRadius)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .scaleEffect(isAdjusting ? 1.05 : 1)
            .animation(.snappy, value: isAdjusting)
            .frame(width: metrics.width, height: height)
            .frame(width: geometry.size.width, height: height)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleChange(value, travel: Double(height))
                    }
                    .onEnded { value in
                        handleEnd(value)
                    }
            )
        }
    }

    /// iconInk is light blue where the white fill reaches the icon's centre, and white where it
    /// does not: over the glass, or over the grey fill of a muted level, which is not white.
    static func iconInk(
        fillHeight: CGFloat,
        centre    : CGFloat,
        isMuted   : Bool
    ) -> Color {
        !isMuted && fillHeight >= centre ? iconInkOnFill : .white
    }

    /// ink is dark where the white fill reaches the point and light where the glass shows, so a
    /// percentage stays legible at any level, judged by its top, where a reading starts to matter.
    /// The icon has its own ink, `iconInk`.
    private func ink(
        covering point: CGFloat,
        fillHeight    : CGFloat
    ) -> Color {
        fillHeight >= point ? Color(white: 0.15) : .white
    }

    private func handleChange(
        _ value: DragGesture.Value,
        travel : Double
    ) {
        let now     = ContinuousClock.now
        let start   = pressStart ?? now
        var current = gesture ?? VolumeGesture(startLevel: level, travel: travel)

        let outcome = current.move(to: value.translation, elapsed: now - start)
        gesture    = current
        pressStart = start

        if case .level(let chosen) = outcome {
            onLevel(chosen)
        }
    }

    private func handleEnd(_ value: DragGesture.Value) {
        defer {
            gesture    = nil
            pressStart = nil
        }
        guard var current = gesture, let start = pressStart else { return }

        let outcome = current.end(
            translation: value.translation,
            elapsed    : ContinuousClock.now - start
        )
        switch outcome {
            case .click:
                onClick?()

            case .level(let chosen):
                onLevel(chosen)
                onEnd()

            case .none:
                break
        }
    }
}
