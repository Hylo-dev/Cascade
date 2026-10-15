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
/// timers and no animation loop. A drag past either end stretches the pill like rubber, towards
/// the finger: up from its bottom edge past 100%, down from its top edge past 0%. The stretch
/// follows the finger without animation and springs back, bouncing, on release.
struct AudioVolumeCapsule: View {

    /// Appearance is how the empty part of the pill is drawn. `groove` sinks it into the notch:
    /// the global volume, which belongs to the notch like the other widgets. `clearGlass` is a
    /// pane of glass the notch shows through, with a dimmed fill: the per-app capsules, thin
    /// and many, beside the global one, which a row of opaque pearl columns would outshine.
    enum Appearance {

        case groove
        case clearGlass
    }

    /// iconInkOnFill is the light blue the icon takes where the white level fill is behind it,
    /// sRGB (0, 198, 234), matching the user's reference. Anywhere else the icon is white.
    static let iconInkOnFill = Color(
        red  : 0,
        green: 198.0 / 255.0,
        blue : 234.0 / 255.0
    )

    private static let percentageInset: CGFloat = 10

    /// maximumStretch is the most the pill grows past an end, as a share of its height; the rubber
    /// band approaches it and never reaches it. narrowing is how much of that growth the width
    /// loses, so the stretched pill thins a little as rubber does. release is the spring back.
    private static let maximumStretch: CGFloat = 0.14
    private static let narrowing     : CGFloat = 0.35
    static let release               = Animation.spring(response: 0.4, dampingFraction: 0.45)

    /// widthRatio below one keeps the reference proportions inside the given frame, centred (the
    /// grid widget passes 0.6); one or more fills what it is given, as the mixer does. The
    /// press still covers the whole frame, so a thin pill is no harder to grab.
    let widthRatio     : CGFloat
    let level          : Double
    let isMuted        : Bool
    let icon           : AudioOutputIcon?
    /// iconOpacity dims the icon alone, for the unavailable look: the pill stays as it is.
    let iconOpacity    : Double
    /// isDashed draws the rim as a dashed line, for a level the user asked for and nothing
    /// enforces: the pill says so instead of promising a control.
    var isDashed       : Bool = false
    /// appearance is the groove of the global volume, or the clear glass of the mixer's per-app
    /// capsules (`Appearance`).
    var appearance     : Appearance = .groove
    let showsPercentage: Bool
    /// pushedOvershoot is a stretch the owner drives, in points past an end (positive past the
    /// top): the scroll wheel's, which the capsule cannot see. A drag's own overshoot wins.
    var pushedOvershoot: CGFloat = 0
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

    /// overshoot is how far the drag has gone past an end, in points (positive past the top), and
    /// stretchAnchor the edge the pill stretches from. The anchor changes only with a non-zero
    /// overshoot, so it holds still while the pill springs back to zero.
    @State
    private var overshoot: CGFloat = 0

    @State
    private var stretchAnchor: UnitPoint = .bottom

    var body: some View {
        GeometryReader { geometry in
            let metrics    = AudioVolumeCapsuleMetrics(
                availableWidth : geometry.size.width,
                availableHeight: geometry.size.height,
                widthRatio     : widthRatio
            )
            let height     = metrics.height
            let fillHeight = height * CGFloat(min(1, max(0, level)))

            ZStack(alignment: .bottom) {
                let past    = overshoot != 0 ? overshoot : pushedOvershoot
                let stretch = Self.rubberBand(overshoot: past, height: height) / Swift.max(height, 1)

                body(metrics: metrics, fillHeight: fillHeight)
                    .scaleEffect(
                        x     : 1 - stretch * Self.narrowing,
                        y     : 1 + stretch,
                        anchor: stretchAnchor
                    )

                if let icon {
                    iconLayer(
                        icon   : icon,
                        metrics: metrics,
                        ink    : Self.iconInk(
                            fillHeight: fillHeight,
                            reach     : metrics.iconInset,
                            isMuted   : isMuted
                        )
                    )
                    .offset(
                        y: Self.iconShift(
                            stretch   : stretch,
                            height    : height,
                            iconCentre: metrics.iconCentre,
                            fromBottom: stretchAnchor == .bottom
                        )
                    )
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
            .frame(width: metrics.width, height: height)
            .frame(width: geometry.size.width, height: geometry.size.height)
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
            .onChange(of: pushedOvershoot) { _, pushed in
                if pushed != 0 {
                    stretchAnchor = pushed > 0 ? .bottom : .top
                }
            }
        }
    }

    /// The pill is a groove cut into the notch, not an object laid on it. The other widgets are
    /// type and symbols on the notch's own surface, so a pill with a body and a lit rim of its own
    /// read as a separate button. The empty track is the notch's material sunk a little: almost
    /// black, shaded under its top edge as a groove is, with light caught only by its lower lip.
    /// The fill is the one lit thing in it, a pearl white curved across its width, so it reads as
    /// glass resting in the groove even when the level is full.
    ///
    /// All of it is painted, not sampled: a backdrop blur over the notch's black would blur
    /// nothing and still cost an offscreen pass on every frame of a drag. The gradients are built
    /// once, so a level change allocates nothing for them.
    private static let wellBody = LinearGradient(
        colors    : [Color(white: 0.05), Color(white: 0.12)],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let wellShade = LinearGradient(
        stops     : [
            .init(color: .black.opacity(0.55), location: 0),
            .init(color: .black.opacity(0.15), location: 0.12),
            .init(color: .clear,               location: 0.3)
        ],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let wellLip = LinearGradient(
        stops     : [
            .init(color: .clear,               location: 0),
            .init(color: .clear,               location: 0.55),
            .init(color: .white.opacity(0.20), location: 1)
        ],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let fillCurve = LinearGradient(
        stops     : [
            .init(color: .white.opacity(0.35), location: 0),
            .init(color: .clear,               location: 0.45),
            .init(color: .black.opacity(0.14), location: 1)
        ],
        startPoint: .leading,
        endPoint  : .trailing
    )

    private static let fillLit = LinearGradient(
        colors    : [Color(white: 0.96), Color(white: 0.82)],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let glassBody = LinearGradient(
        colors    : [.white.opacity(0.10), .white.opacity(0.05)],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let glassSheen = LinearGradient(
        stops     : [
            .init(color: .white.opacity(0.18), location: 0),
            .init(color: .clear,               location: 0.35)
        ],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let glassRim = LinearGradient(
        stops     : [
            .init(color: .white.opacity(0.35), location: 0),
            .init(color: .white.opacity(0.08), location: 0.4),
            .init(color: .white.opacity(0.18), location: 1)
        ],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let fillSubdued = LinearGradient(
        colors    : [Color(white: 0.72), Color(white: 0.58)],
        startPoint: .top,
        endPoint  : .bottom
    )

    private static let fillMuted = LinearGradient(
        colors    : [Color(white: 0.60), Color(white: 0.46)],
        startPoint: .top,
        endPoint  : .bottom
    )

    /// body(metrics:fillHeight:) is the pill itself, without the icon: the groove, the fill and
    /// the lip. It alone stretches while the user adjusts, so the icon keeps its size and its place.
    private func body(
        metrics   : AudioVolumeCapsuleMetrics,
        fillHeight: CGFloat
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius)

        let isGlass = appearance == .clearGlass

        return ZStack(alignment: .bottom) {
            shape
                .fill(isGlass ? Self.glassBody : Self.wellBody)

            Rectangle()
                .fill(isMuted ? Self.fillMuted : (isGlass ? Self.fillSubdued : Self.fillLit))
                .overlay(Self.fillCurve)
                .frame(height: fillHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)

            shape
                .fill(isGlass ? Self.glassSheen : Self.wellShade)
        }
        .clipShape(shape)
        .overlay {
            if isDashed {
                shape
                    .strokeBorder(
                        .white.opacity(0.55),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash     : [3, 2]
                        )
                    )
            } else {
                shape
                    .strokeBorder(
                        isGlass ? Self.glassRim : Self.wellLip,
                        lineWidth: 1
                    )
            }
        }
    }

    /// iconLayer is the icon at its place in the pill, inked whole.
    ///
    /// The geometry group is what keeps the icon on the pill. SwiftUI pushes a parent's position
    /// changes down to the leaf that draws, and the leaf animates them with its own transaction.
    /// The symbol animates its waves with `.animation(_:value: icon)`, so on a flick, where the
    /// level jumps in the same update the pill starts to stretch, the icon's shift took the
    /// symbol's slow ease instead of following the finger, and then missed the spring back.
    /// Grouped, the icon moves as one with the pill's transaction, and the symbol's animation
    /// stays inside the glyph.
    private func iconLayer(
        icon   : AudioOutputIcon,
        metrics: AudioVolumeCapsuleMetrics,
        ink    : Color
    ) -> some View {
        AudioOutputIconView(
            icon: icon,
            ink : ink
        )
        .geometryGroup()
        .font(.system(size: metrics.symbolFontSize))
        .foregroundStyle(ink)
        .opacity(iconOpacity)
        .frame(width: metrics.iconSize, height: metrics.iconSize)
        .padding(.bottom, metrics.iconInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// iconShift moves the icon with the stretched pill without stretching the glyph: its centre
    /// goes where the scale takes that point of the pill. Stretched from the bottom edge, it rises
    /// by its own height above that edge times the stretch; from the top edge, it drops by its
    /// distance from the top times the stretch. Negative is up.
    static func iconShift(
        stretch   : CGFloat,
        height    : CGFloat,
        iconCentre: CGFloat,
        fromBottom: Bool
    ) -> CGFloat {
        fromBottom
            ? -iconCentre * stretch
            : (height - iconCentre) * stretch
    }

    /// rubberBand turns the points dragged past an end into the points the pill grows: about one
    /// for one at first, then less and less, approaching `maximumStretch` of the height, as a
    /// scroll view's rubber band does.
    static func rubberBand(
        overshoot: CGFloat,
        height   : CGFloat
    ) -> CGFloat {
        let limit = Swift.max(height, 0) * maximumStretch
        guard limit > 0 else { return 0 }

        let distance = Swift.abs(overshoot)
        return limit * (1 - 1 / (distance * 0.55 / limit + 1))
    }

    /// iconInk inks the whole icon: light blue as soon as the white fill reaches the icon's bottom
    /// edge (`reach`), and white while it does not: over the glass, or over the grey fill of a muted level, which
    /// is not white.
    static func iconInk(
        fillHeight: CGFloat,
        reach     : CGFloat,
        isMuted   : Bool
    ) -> Color {
        !isMuted && fillHeight > reach ? iconInkOnFill : .white
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

        let past = CGFloat(current.overshoot(at: value.translation))
        if past != 0 {
            stretchAnchor = past > 0 ? .bottom : .top
        }
        overshoot = past

        if case .level(let chosen) = outcome {
            onLevel(chosen)
        }
    }

    private func handleEnd(_ value: DragGesture.Value) {
        defer {
            gesture    = nil
            pressStart = nil
            withAnimation(Self.release) {
                overshoot = 0
            }
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
