//
//  PluginNodeContent.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginNodeContent draws a node without its modifiers: a `switch` over the tier-1 vocabulary,
/// with children drawn as `PluginNodeView`s. Time is drawn by SwiftUI itself, so a timer or a
/// relative date costs the plugin nothing. Controls read their optimistic value first and hand
/// every change to the store. A tier-2 component and an asset reserve their frame and draw
/// nothing until the component and the asset pipeline exist.
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

            case .timer(let start, let end, let countsDown):
                Text(timerInterval: start...end, countsDown: countsDown)

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
                Toggle(isOn: Binding(get: { model.optimistic?.bool ?? isOn }, set: { store.set(.bool($0), on: model) })) {
                    children
                }
                .toggleStyle(PluginToggleStyle())

            case .slider(let value, let minimum, let maximum, let step, _):
                if let step {
                    Slider(value: thumb(value), in: minimum...maximum, step: step, onEditingChanged: released)
                } else {
                    Slider(value: thumb(value), in: minimum...maximum, onEditingChanged: released)
                }

            case .asset, .component:
                Color.clear
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
