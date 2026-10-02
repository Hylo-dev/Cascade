//
//  PluginNodeContent.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginNodeContent draws a node without its modifiers: a `switch` over the tier-1 vocabulary,
/// with children drawn as `PluginNodeView`s. Time is drawn by SwiftUI itself, so a timer or a
/// relative date costs the plugin nothing, and a clock or a date of today, `PluginClockView` and
/// `PluginTodayView`, redraws itself at every minute boundary, only while it is on screen, in
/// the zone the `timeZone` modifier sets; no other node reads the zone or the locale.
/// A timer progress is the kernel's own bar, `PluginTimerProgressBar`, which steps instead of
/// redrawing every frame as SwiftUI's does, and a linear progress the same bar standing still,
/// its fraction safe to take because the contract keeps the value within a positive total.
/// Controls read their optimistic value first and hand every change to the store, unless the
/// widget board is editing, which `PluginControlGate` tells them; a toggle with two children
/// shows the first while off and the second while on. An asset reserves its frame
/// and draws nothing until the asset pipeline exists; a tier-2 component draws through
/// `PluginComponentView`.
struct PluginNodeContent: View {

    let model: PluginNodeModel
    let store: PluginNodeStore

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
                Text(timerInterval: start...end, countsDown: countsDown)

            case .timerProgress(let start, let end):
                PluginTimerProgressBar(start: start, end: end)

            case .progress(let value, let total, .linear):
                PluginProgressBar(fraction: value / total)

            case .progress(let value, let total, .circular):
                ProgressView(value: value, total: total)
                    .progressViewStyle(.circular)

            case .button:
                PluginControlGate { isEditingWidgets in
                    Button {
                        if !isEditingWidgets {
                            store.press(model)
                        }
                    } label: {
                        children
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

            case .slider(let value, let minimum, let maximum, let step, _):
                PluginControlGate { isEditingWidgets in
                    if let step {
                        Slider(
                            value           : thumb(value, isEditingWidgets: isEditingWidgets),
                            in              : minimum...maximum,
                            step            : step,
                            onEditingChanged: released(isEditingWidgets: isEditingWidgets)
                        )
                    } else {
                        Slider(
                            value           : thumb(value, isEditingWidgets: isEditingWidgets),
                            in              : minimum...maximum,
                            onEditingChanged: released(isEditingWidgets: isEditingWidgets)
                        )
                    }
                }

            case .asset:
                Color.clear

            case .component(let id, let version, let parameters):
                PluginComponentView(id: id, version: version, parameters: parameters)
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(model.children, id: \.self) { id in
            if let child = store.model(id) {
                PluginNodeView(model: child, store: store)
            }
        }
    }

    /// toggleLabel is what a toggle shows for its state, the optimistic one first, as a SwiftUI
    /// toggle's label reads its own state: with two children, the first while off and the second
    /// while on; with any other children, all of them, dimmed while off.
    @ViewBuilder
    private func toggleLabel(isOn: Bool) -> some View {
        if model.children.count == 2, let child = store.model(model.children[isOn ? 1 : 0]) {
            PluginNodeView(model: child, store: store)
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
            set: { isOn in
                if !isEditingWidgets {
                    store.set(.bool(isOn), on: model)
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
            set: { value in
                if !isEditingWidgets {
                    store.drag(value, on: model)
                }
            }
        )
    }

    /// released sends the value a slider was let go at. Let go while the widget board is
    /// editing, a drag begun before sends nothing and its thumb goes back to the published value.
    private func released(isEditingWidgets: Bool) -> (Bool) -> Void {
        { isDragging in
            guard !isDragging else { return }

            if isEditingWidgets {
                store.cancelDrag(model)
            } else {
                store.release(model)
            }
        }
    }
}
