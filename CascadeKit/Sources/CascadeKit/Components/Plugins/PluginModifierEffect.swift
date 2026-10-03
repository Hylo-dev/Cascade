//
//  PluginModifierEffect.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginModifierEffect applies one plugin modifier with the SwiftUI modifier it mirrors.
struct PluginModifierEffect: ViewModifier {

    let modifier: PluginModifier
    let layer   : PluginNodeModel?
    let store   : PluginNodeStore

    @Environment(\.accessibilityReduceMotion)
    private var reducesMotion

    func body(content: Content) -> some View {
        switch modifier {
            case .font(let font):
                content
                    .font(font.swiftUI)

            case .foregroundStyle(.color(let color)):
                content
                    .foregroundStyle(color.swiftUI)

            case .foregroundStyle(.hierarchical(let level)):
                content
                    .foregroundStyle(level.swiftUI)

            case .foregroundStyle(.gradient(let colors)):
                content
                    .foregroundStyle(LinearGradient(colors: colors.map(\.swiftUI), startPoint: .leading, endPoint: .trailing))

            case .frame(let width, let height, let maxWidth, let maxHeight, let alignment):
                content
                    .frame(width: width.map { CGFloat($0) }, height: height.map { CGFloat($0) }, alignment: alignment.swiftUI)
                    .frame(maxWidth: maxWidth?.swiftUI, maxHeight: maxHeight?.swiftUI, alignment: alignment.swiftUI)

            case .padding(let edges, let length):
                content
                    .padding(edges.swiftUI, length.map { CGFloat($0) })

            case .opacity(let value):
                content
                    .opacity(value)

            case .clipShape(.circle):
                content
                    .clipShape(Circle())

            case .clipShape(.capsule):
                content
                    .clipShape(Capsule())

            case .clipShape(.roundedRectangle(let radius)):
                content
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))

            case .lineLimit(let lines):
                content
                    .lineLimit(lines)

            case .minimumScaleFactor(let factor):
                content
                    .minimumScaleFactor(factor)

            case .contentTransition(.numericText(let countsDown)):
                content
                    .contentTransition(.numericText(countsDown: countsDown))

            case .contentTransition(.symbolEffect):
                content
                    .contentTransition(reducesMotion ? .identity : .symbolEffect(.automatic))

            case .transition(let transition):
                content
                    .transition(transition.swiftUI)

            case .accessibilityLabel(let label):
                content
                    .accessibilityLabel(Text(verbatim: label))

            case .overlay(let alignment):
                content
                    .overlay(alignment: alignment.swiftUI) { layerView }

            case .background(let alignment):
                content
                    .background(alignment: alignment.swiftUI) { layerView }
        }
    }

    @ViewBuilder
    private var layerView: some View {
        if let layer {
            PluginNodeView(model: layer, store: store)
        }
    }
}
