//
//  MusicControlSymbol.swift
//  Cascade
//

import SwiftUI

/// SF Symbols retain their native metrics. Each skip arrow moves separately;
/// the outgoing arrow is recycled only while invisible, so there are never
/// more than the original two arrows on screen.
struct MusicControlSymbol: View {

    let symbol : String
    let size   : CGFloat
    var trigger = 0

    var reduceMotion = false

    private var image: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
    }

    var body: some View {
        if !reduceMotion && (symbol == "forward.fill" || symbol == "backward.fill") {
            image
                .hidden()
                .overlay {
                    GeometryReader { geometry in
                        let direction: CGFloat = symbol == "forward.fill" ? 1 : -1
                        let bounds    = geometry.size
                        let glyph     = Image(systemName: "play.fill")
                        let font      = Font.system(size: size * 0.94, weight: .regular)

                        Color.clear
                            .keyframeAnimator(
                                initialValue: SkipMotion(),
                                trigger     : trigger
                            ) { _, motion in
                                // Match the tighter optical spacing of the native double-arrow glyph.
                                let pitch = bounds.width * 0.45

                                ZStack {

                                    ForEach(0..<2) { half in
                                        let isFront = half == (direction > 0 ? 1 : 0)

                                        glyph
                                            .font(font)
                                            .scaleEffect(x: direction, y: 1)
                                            .frame(width: pitch, height: bounds.height)
                                            .offset(
                                                x: (CGFloat(half) - 0.5) * pitch
                                                    + direction * pitch * (isFront
                                                        ? motion.recycledOffset
                                                        : motion.advance)
                                            )
                                            .opacity(isFront ? motion.recycledOpacity : 1)
                                    }
                                }
                                .frame(width: bounds.width, height: bounds.height)
                                .clipped()
                            } keyframes: { _ in
                                KeyframeTrack(\.advance) {
                                    CubicKeyframe(
                                        CGFloat(1),
                                        duration     : 0.32,
                                        startVelocity: 0,
                                        endVelocity  : 0
                                    )
                                    MoveKeyframe(CGFloat.zero)
                                }

                                KeyframeTrack(\.recycledOffset) {
                                    CubicKeyframe(CGFloat(1), duration: 0.12)
                                    MoveKeyframe(CGFloat(-2))
                                    CubicKeyframe(
                                        CGFloat(-1),
                                        duration     : 0.20,
                                        startVelocity: 0,
                                        endVelocity  : 0
                                    )
                                    MoveKeyframe(CGFloat.zero)
                                }

                                KeyframeTrack(\.recycledOpacity) {
                                    LinearKeyframe(0.0, duration: 0.10)
                                    LinearKeyframe(0.0, duration: 0.06)
                                    LinearKeyframe(1.0, duration: 0.16)
                                }
                            }
                    }
                }
        } else {
            // A symbol swap is an insertion, not a content transition: SwiftUI
            // renders a content transition, even a plain crossfade, on the GPU,
            // holding ~50 MB of graphics memory for two seconds after every
            // play or pause. The blurred, scaled replacement costs nothing.
            ZStack {

                image
                    .id(symbol)
                    .transition(reduceMotion ? .identity : AnyTransition(.blurReplace))
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: symbol)
        }
    }
}

private struct SkipMotion {

    var advance        : CGFloat = 0
    var recycledOffset : CGFloat = 0
    var recycledOpacity: Double = 1
}
