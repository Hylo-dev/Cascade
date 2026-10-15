//
//  PluginRulerSlider.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginRulerSlider is the kernel's `ruler` slider: ticks, one per `step`, slide under a fixed
/// indicator while the user drags, as the iOS timer's do. The ticks already passed are full in
/// the tint, those ahead at 28 %; they are bottom-aligned and fall shorter and fainter with
/// their distance from the indicator; a label is written every `labelEvery` ticks and a filled
/// triangle marks the centre.
///
/// It is a control like the system slider and uses the same plumbing. The value is the node's
/// optimistic binding, so a drag moves the ticks at once and publications do not move them
/// meanwhile; the drag sends nothing, and the release sends one action, at the step the value
/// settles on. A plugin therefore never wakes while the ruler is dragged. At rest it costs
/// nothing, and it redraws only when the value or the size changes.
///
/// Reduce Motion turns the settling animation off: the release lands on its step in place.
/// VoiceOver sees one adjustable element that steps by `step` and reads the label of its value.
struct PluginRulerSlider: View {

    let value     : Binding<Double>
    let minimum   : Double
    let maximum   : Double
    let step      : Double
    let labelEvery: Int
    let labels    : PluginRulerLabels
    let tint      : Color

    /// released lets go of the control with the animation its value settles in, nil under
    /// Reduce Motion: it sends the one action. cancelled lets go without sending.
    let released  : (Animation?) -> Void
    let cancelled : () -> Void

    @State
    private var interaction = RulerInteraction()

    /// isHeld is true while a drag is under way. A `GestureState` resets by itself when the
    /// system cancels the gesture, which `onEnded` never reports, but it resets on a normal end
    /// too, in an order SwiftUI does not specify; the driver therefore looks again one main turn
    /// after the reset, and drops only a drag that no `onEnded` finished (`gestureStateReset`).
    @GestureState
    private var isHeld = false

    @StateObject
    private var labelCache = RulerLabelCache()

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// spacing is the distance between two ticks in points: thirteen of them make a quarter
    /// of an hour a comfortable thumb-width, and about twenty ticks, five hours, fit in the
    /// options page's 260 points.
    static let spacing = 13.0

    var body: some View {
        PluginRulerCanvas(
            position  : value.wrappedValue,
            minimum   : minimum,
            maximum   : maximum,
            step      : step,
            labelEvery: labelEvery,
            labels    : labels,
            tint      : tint,
            cache     : labelCache
        )
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: spoken))
        .accessibilityAdjustableAction { direction in
            switch direction {
                case .increment:
                    driver.adjust(1)

                case .decrement:
                    driver.adjust(-1)

                @unknown default:
                    break
            }
        }
        .onChange(of: isHeld) { wasHeld, isHeld in
            if wasHeld, !isHeld {
                driver.gestureStateReset()
            }
        }
        .onDisappear {
            driver.interrupted()
        }
    }

    /// driver is rebuilt at every body from the current bindings and holds no state of its own.
    private var driver: RulerGestureDriver {
        RulerGestureDriver(
            interaction: $interaction,
            value      : value,
            scale      : RulerScale(
                minimum: minimum,
                maximum: maximum,
                step   : step,
                spacing: Self.spacing
            ),
            animation  : reduceMotion ? nil : .snappy,
            released   : released,
            cancelled  : cancelled
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isHeld) { _, held, _ in
                held = true
            }
            .onChanged { gesture in
                driver.changed(translation: gesture.translation.width)
            }
            .onEnded { _ in
                driver.ended()
            }
    }

    private var spoken: String {
        labelCache.spoken(
            value : RulerGeometry.snapped(value.wrappedValue, minimum: minimum, maximum: maximum, step: step),
            labels: labels
        )
    }
}

/// PluginRulerCanvas draws the ruler in one `Canvas`. `position` is its animatable data, so the
/// settling animation of a release interpolates the value and redraws the ticks on the way,
/// where a `Canvas` alone would jump. It reads nothing but its arguments, so SwiftUI redraws it
/// only when one of them changes.
///
/// The drawing allocates only what a tick needs: `RulerGeometry.forEachTick` yields the visible
/// ticks one by one, with no array, and labels come from the view's cache.
private struct PluginRulerCanvas: View, Animatable {

    var position  : Double
    let minimum   : Double
    let maximum   : Double
    let step      : Double
    let labelEvery: Int
    let labels    : PluginRulerLabels
    let tint      : Color
    let cache     : RulerLabelCache

    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    private static let tickWidth       = 2.5
    private static let tickHeight      = 23.0
    private static let labelBand       = 15.0
    private static let indicatorWidth  = 10.0
    private static let indicatorHeight = 6.0
    private static let indicatorGap    = 2.5
    private static let upcomingAlpha   = 0.28
    private static let upcomingLabel   = 0.45

    var body: some View {
        Canvas { context, size in
            draw(into: &context, size: size)
        }
    }

    private func draw(
        into context: inout GraphicsContext,
        size        : CGSize
    ) {
        let centre   = size.width / 2
        let baseline = size.height - Self.indicatorHeight - Self.indicatorGap
        let tallest  = max(4, min(Self.tickHeight, baseline - Self.labelBand))
        let origin   = labels == .clockTime ? Double(TimeZone.current.secondsFromGMT()) : 0

        RulerGeometry.forEachTick(
            value  : position,
            minimum: minimum,
            maximum: maximum,
            step   : step,
            width  : size.width,
            spacing: PluginRulerSlider.spacing,
            origin : origin
        ) { tick in
            let height  = tallest * tick.heightFraction
            let opacity = tick.isPassed ? tick.alpha : tick.alpha * Self.upcomingAlpha
            let bar     = CGRect(
                x      : centre + tick.offset - Self.tickWidth / 2,
                y      : baseline - height,
                width  : Self.tickWidth,
                height : height
            )

            context.fill(
                Path(roundedRect: bar, cornerRadius: Self.tickWidth / 2),
                with: .color(tint.opacity(opacity))
            )

            guard tick.labelIndex % labelEvery == 0 else { return }

            let faded = tick.isPassed ? tick.alpha : tick.alpha * Self.upcomingLabel
            let label = Text(verbatim: cache.text(value: tick.value, labels: labels))
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint.opacity(faded))

            context.draw(
                context.resolve(label),
                at    : CGPoint(x: centre + tick.offset, y: 0),
                anchor: .top
            )
        }

        var indicator = Path()
        indicator.move(to: CGPoint(x: centre, y: size.height - Self.indicatorHeight))
        indicator.addLine(to: CGPoint(x: centre - Self.indicatorWidth / 2, y: size.height))
        indicator.addLine(to: CGPoint(x: centre + Self.indicatorWidth / 2, y: size.height))
        indicator.closeSubpath()
        context.fill(indicator, with: .color(tint))
    }
}
