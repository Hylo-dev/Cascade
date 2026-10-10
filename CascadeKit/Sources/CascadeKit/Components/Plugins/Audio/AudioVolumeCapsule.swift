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
                            ink(
                                covering  : metrics.iconInset + metrics.iconSize / 2,
                                fillHeight: fillHeight
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

    /// ink is dark where the white fill reaches the point and light where the glass shows, so an
    /// icon or a percentage stays legible at any level. The icon is judged by its centre and the
    /// percentage by its top, where a reading starts to matter.
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
