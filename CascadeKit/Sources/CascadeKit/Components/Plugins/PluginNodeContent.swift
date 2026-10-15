//
//  PluginNodeContent.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import SwiftUI

/// PluginNodeContent draws a node without its modifiers: a `switch` over the tier-1 vocabulary,
/// with children drawn as `PluginNodeView`s. Time is drawn by the kernel, so a timer or a
/// relative date costs the plugin nothing, and a clock or a date of today, `PluginClockView` and
/// `PluginTodayView`, redraws itself at every minute boundary, only while it is on screen, in
/// the zone the `timeZone` modifier sets; no other node reads the zone or the locale. A timer
/// and a countdown roll the digits that change with `RollingDigitsLabel`, in the font and color
/// of the node's own modifiers, redrawn only when their text changes; the font and color are
/// resolved once per body, outside the timeline's closure, so a tick builds no `NSFont`.
/// A timer progress is the kernel's own bar, `PluginTimerProgressBar`, which steps instead of
/// redrawing every frame as SwiftUI's does, and a linear progress the same bar standing still,
/// its fraction safe to take because the contract keeps the value within a positive total.
/// Controls read their optimistic value first and hand every change to the store, unless the
/// widget board is editing, which `PluginControlGate` tells them; a toggle with two children
/// shows the first while off and the second while on. An asset reserves its frame and draws
/// nothing until the asset pipeline exists; a tier-2 component draws through
/// `PluginComponentView`.
struct PluginNodeContent: View {

    let model        : PluginNodeModel
    let store        : PluginNodeStore
    var optionsOrigin: PluginOptionsOrigin? = nil

    var body: some View {
        switch model.kind {
            case .vStack(let alignment, let spacing):
                VStack(alignment: alignment.swiftUI, spacing: spacing.map { CGFloat($0) }) {
                    children
                }

            case .hStack(let alignment, let spacing):
                HStack(alignment: alignment.swiftUI, spacing: spacing.map { CGFloat($0) }) {
                    children
                }

            case .zStack(let alignment):
                ZStack(alignment: alignment.swiftUI) {
                    children
                }

            case .regions:
                ZStack {
                    children
                }

            case .viewThatFits(let axes):
                ViewThatFits(in: axes.swiftUI) {
                    children
                }

            case .spacer(let minLength):
                Spacer(minLength: minLength.map { CGFloat($0) })

            case .text(let text):
                Text(verbatim: text)

            case .symbol(let name):
                Image(systemName: name)

            case .shape(.circle):
                Circle()

            case .shape(.capsule):
                Capsule()

            case .shape(.roundedRectangle(let radius)):
                RoundedRectangle(cornerRadius: radius, style: .continuous)

            case .date(let date, let style):
                Text(date, style: style.swiftUI)

            case .clock:
                PluginClockView()

            case .today:
                PluginTodayView()

            case .timer(let start, let end, let countsDown):
                let font  = timeFont
                let color = timeColor

                TimelineView(TimerTimelineSchedule(start: start, end: end)) { context in
                    RollingDigitsLabel(
                        text      : TimerText.text(
                            start     : start,
                            end       : end,
                            countsDown: countsDown,
                            at        : context.date
                        ),
                        font      : font,
                        color     : color,
                        countsDown: countsDown
                    )
                }

            case .countdown(let end, .compact):
                let font  = timeFont
                let color = timeColor

                TimelineView(CompactCountdownSchedule(end: end)) { context in
                    RollingDigitsLabel(
                        text      : CompactCountdown.text(remaining: end.timeIntervalSince(context.date)),
                        font      : font,
                        color     : color,
                        countsDown: true
                    )
                }

            case .countdown(let end, .hoursMinutes):
                let font  = timeFont
                let color = timeColor

                TimelineView(HoursMinutesCountdownSchedule(end: end)) { context in
                    RollingDigitsLabel(
                        text      : HoursMinutesCountdown.text(remaining: end.timeIntervalSince(context.date)),
                        font      : font,
                        color     : color,
                        countsDown: true
                    )
                }

            case .timerProgress(let start, let end):
                PluginTimerProgressBar(start: start, end: end)

            case .progress(let value, let total, .linear):
                PluginProgressBar(fraction: value / total)

            case .progress(let value, let total, .circular):
                ProgressView(value: value, total: total)
                    .progressViewStyle(.circular)

            case .button:
                PluginControlGate { isEditingWidgets in
                    Button { [optionsOrigin] in
                        if !isEditingWidgets {
                            store.press(model, optionsOrigin: optionsOrigin)
                        }
                    } label: {
                        children
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

            case .toggle(let isOn, _):
                let shown = model.optimistic?.bool ?? isOn

                PluginControlGate { isEditingWidgets in
                    Toggle(isOn: switched(shown, isEditingWidgets: isEditingWidgets)) {
                        toggleLabel(isOn: shown)
                    }
                    .toggleStyle(PluginToggleStyle())
                }

            case .slider(let value, let minimum, let maximum, let step, .ruler(let labelEvery, let labels), _) where step != nil:
                PluginControlGate { isEditingWidgets in
                    PluginRulerSlider(
                        value     : thumb(value, isEditingWidgets: isEditingWidgets),
                        minimum   : minimum,
                        maximum   : maximum,
                        step      : step ?? 1,
                        labelEvery: labelEvery,
                        labels    : labels,
                        tint      : Color(nsColor: timeColor),
                        released  : released(isEditingWidgets: isEditingWidgets),
                        cancelled : {
                            store.cancelDrag(model)
                        }
                    )
                }

            case .slider(let value, let minimum, let maximum, let step, _, _):
                PluginControlGate { isEditingWidgets in
                    PluginStandardSlider(
                        value   : thumb(value, isEditingWidgets: isEditingWidgets),
                        minimum : minimum,
                        maximum : maximum,
                        step    : step,
                        released: released(isEditingWidgets: isEditingWidgets)
                    )
                }

            case .sliderValue(let sliderID):
                PluginSliderValueText(
                    store   : store,
                    sliderID: sliderID
                )

            case .asset:
                Color.clear

            case .component(let id, let version, let parameters):
                PluginComponentView(id: id, version: version, parameters: parameters)
        }
    }

    /// timeFont is the font of the node's own `.font` modifier, the innermost one winning as in
    /// SwiftUI, always with monospaced digits: a rolling label must not shift when a digit
    /// changes. An ancestor's font does not reach an AppKit label, so a time node carries its own.
    private var timeFont: NSFont {
        let described = model.modifiers.lazy.compactMap { modifier -> PluginFont? in
            if case .font(let font) = modifier { font } else { nil }
        }.first

        return (described?.nsFont ?? .monospacedDigitSystemFont(ofSize: 11, weight: .regular)).monospacingDigits
    }

    /// timeColor is the color of the node's own `.foregroundStyle(.color)` modifier, white
    /// when it has none or a style that is not a plain color. A ruler slider is tinted by it too.
    private var timeColor: NSColor {
        let described = model.modifiers.lazy.compactMap { modifier -> PluginColor? in
            if case .foregroundStyle(.color(let color)) = modifier { color } else { nil }
        }.first

        return described?.nsColor ?? .white
    }

    @ViewBuilder
    private var children: some View {
        ForEach(model.children, id: \.self) { id in
            if let child = store.model(id) {
                PluginNodeView(
                    model        : child,
                    store        : store,
                    optionsOrigin: optionsOrigin
                )
            }
        }
    }

    /// toggleLabel is what a toggle shows for its state, the optimistic one first, as a SwiftUI
    /// toggle's label reads its own state: with two children, the first while off and the second
    /// while on; with any other children, all of them, dimmed while off.
    @ViewBuilder
    private func toggleLabel(isOn: Bool) -> some View {
        if model.children.count == 2, let child = store.model(model.children[isOn ? 1 : 0]) {
            PluginNodeView(
                model        : child,
                store        : store,
                optionsOrigin: optionsOrigin
            )
        } else {
            children
                .opacity(isOn ? 1 : 0.5)
        }
    }

    /// switched is a toggle's state: the one shown, and a change sent to the store, unless the
    /// widget board is editing.
    private func switched(
        _ shown         : Bool,
        isEditingWidgets: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { shown },
            set: { [optionsOrigin] isOn in
                if !isEditingWidgets {
                    store.set(
                        .bool(isOn),
                        on           : model,
                        optionsOrigin: optionsOrigin
                    )
                }
            }
        )
    }

    /// thumb is the slider's position: the optimistic one while dragged or awaiting
    /// confirmation, the published one otherwise. While the widget board is editing, a drag
    /// moves nothing.
    private func thumb(
        _ published     : Double,
        isEditingWidgets: Bool
    ) -> Binding<Double> {
        Binding(
            get: { model.optimistic?.number ?? published },
            set: { [optionsOrigin] value in
                if !isEditingWidgets {
                    store.drag(
                        value,
                        on           : model,
                        optionsOrigin: optionsOrigin
                    )
                }
            }
        )
    }

    /// released sends the value a slider was let go at, with the animation it settles in. Let go
    /// while the widget board is editing, a drag begun before sends nothing and its thumb goes
    /// back to the published value.
    private func released(isEditingWidgets: Bool) -> (Animation?) -> Void {
        { [optionsOrigin] animation in
            if isEditingWidgets {
                store.cancelDrag(model)
            } else {
                store.release(
                    model,
                    optionsOrigin: optionsOrigin,
                    animation    : animation
                )
            }
        }
    }
}
