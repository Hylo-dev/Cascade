//
//  PluginNodeContent.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginNodeContent draws a node without its modifiers: a `switch` over the tier-1 vocabulary,
/// with children drawn as `PluginNodeView`s. Time is drawn by SwiftUI itself, so a timer or a
/// relative date costs the plugin nothing, and a clock redraws itself at every minute boundary,
/// only while it is on screen. Controls read their optimistic value first and hand
/// every change to the store; a toggle with two children shows the first while off and the
/// second while on. An asset reserves its frame and draws nothing until the asset pipeline
/// exists; a tier-2 component draws through `PluginComponentView`.
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
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .animation(.smooth, value: context.date)
                }

            case .today:
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                }

            case .timer(let start, let end, let countsDown):
                if model.modifiers.contains(where: { if case .contentTransition(.numericText) = $0 { return true }; return false }) {
                    PluginTimerLabel(start: start, end: end, countsDown: countsDown, model: model)
                } else {
                    Text(timerInterval: start...end, countsDown: countsDown)
                }

            case .timerProgress(let start, let end):
                ProgressView(timerInterval: start...end, countsDown: false)

            case .progress(let value, let total, .linear):
                ProgressView(value: value, total: total)
                    .progressViewStyle(.linear)

            case .progress(let value, let total, .circular):
                ProgressView(value: value, total: total)
                    .progressViewStyle(.circular)

            case .button:
                Button {
                    store.press(model)
                } label: {
                    children
                }
                .buttonStyle(.plain)

            case .toggle(let isOn, _):
                let shown = model.optimistic?.bool ?? isOn

                Toggle(isOn: Binding(get: { shown }, set: { store.set(.bool($0), on: model) })) {
                    toggleLabel(isOn: shown)
                }
                .toggleStyle(PluginToggleStyle())

            case .slider(let value, let minimum, let maximum, let step, _):
                if let step {
                    Slider(value: thumb(value), in: minimum...maximum, step: step, onEditingChanged: released)
                } else {
                    Slider(value: thumb(value), in: minimum...maximum, onEditingChanged: released)
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

    /// thumb is the slider's position: the optimistic one while dragged or awaiting
    /// confirmation, the published one otherwise.
    private func thumb(_ published: Double) -> Binding<Double> {
        Binding(get: { model.optimistic?.number ?? published }, set: { store.drag($0, on: model) })
    }

    private func released(_ isEditing: Bool) {
        if !isEditing {
            store.release(model)
        }
    }
}
