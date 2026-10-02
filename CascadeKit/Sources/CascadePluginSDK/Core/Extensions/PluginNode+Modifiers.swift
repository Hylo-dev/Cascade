//
//  PluginNode+Modifiers.swift
//  CascadeKit
//

import CascadeContracts

/// PluginNode+Modifiers gives a node SwiftUI's modifier syntax. Every method returns a copy with
/// one modifier appended, so a chain lists them in the order SwiftUI applies them, which is the
/// order the kernel applies them in. `overlay` and `background` also append their content as the
/// node's next layer, which is how the contract pairs them, and `id(_:)` sets the explicit
/// identity rather than adding a modifier. Each call copies the node's arrays: a plugin builds
/// its tree once per publication, never per frame, so the copies are not worth avoiding.
extension PluginNode {

    public func font(_ font: PluginFont) -> PluginNode {
        appending(.font(font))
    }

    public func foregroundStyle(_ color: PluginColor) -> PluginNode {
        appending(.foregroundStyle(.color(color)))
    }

    public func foregroundStyle(_ hierarchy: PluginHierarchy) -> PluginNode {
        appending(.foregroundStyle(.hierarchical(hierarchy)))
    }

    public func foregroundStyle(_ foreground: PluginForeground) -> PluginNode {
        appending(.foregroundStyle(foreground))
    }

    /// frame takes SwiftUI's fixed and flexible frames in one call: whatever is not given stays
    /// nil, so `.frame(maxWidth: .infinity)` only fills the width.
    public func frame(
        width    : Double? = nil,
        height   : Double? = nil,
        maxWidth : PluginDimension? = nil,
        maxHeight: PluginDimension? = nil,
        alignment: PluginAlignment = .center
    ) -> PluginNode {
        appending(
            .frame(
                width    : width,
                height   : height,
                maxWidth : maxWidth,
                maxHeight: maxHeight,
                alignment: alignment
            )
        )
    }

    /// padding(_:_:) pads `edges`, by the system's default length when none is given.
    public func padding(
        _ edges : PluginEdges = .all,
        _ length: Double? = nil
    ) -> PluginNode {
        appending(.padding(edges, length: length))
    }

    public func padding(_ length: Double) -> PluginNode {
        appending(.padding(.all, length: length))
    }

    public func opacity(_ opacity: Double) -> PluginNode {
        appending(.opacity(opacity))
    }

    public func clipShape(_ shape: PluginShape) -> PluginNode {
        appending(.clipShape(shape))
    }

    public func lineLimit(_ limit: Int) -> PluginNode {
        appending(.lineLimit(limit))
    }

    public func minimumScaleFactor(_ factor: Double) -> PluginNode {
        appending(.minimumScaleFactor(factor))
    }

    public func contentTransition(_ transition: PluginContentTransition) -> PluginNode {
        appending(.contentTransition(transition))
    }

    public func transition(_ transition: PluginTransition) -> PluginNode {
        appending(.transition(transition))
    }

    public func accessibilityLabel(_ label: String) -> PluginNode {
        appending(.accessibilityLabel(label))
    }

    /// overlay draws its content over the node. Several nodes are laid over each other in a
    /// `ZStack` with the same alignment, as SwiftUI does with an overlay of several views.
    public func overlay(
        alignment: PluginAlignment = .center,
        @PluginNodeBuilder content: () -> [PluginNode]
    ) -> PluginNode {
        appending(.overlay(alignment: alignment), layer: Self.layer(content(), alignment: alignment))
    }

    /// background draws its content behind the node, several nodes in a `ZStack` like `overlay`.
    public func background(
        alignment: PluginAlignment = .center,
        @PluginNodeBuilder content: () -> [PluginNode]
    ) -> PluginNode {
        appending(.background(alignment: alignment), layer: Self.layer(content(), alignment: alignment))
    }

    /// id gives the node an explicit identity, so the kernel treats it as a new node when the id
    /// changes and as the same one wherever it moves, as SwiftUI's `.id()` does.
    public func id(_ id: String) -> PluginNode {
        PluginNode(
            kind,
            id       : id,
            modifiers: modifiers,
            children : children,
            layers   : layers
        )
    }

    private func appending(
        _ modifier: PluginModifier,
        layer     : PluginNode? = nil
    ) -> PluginNode {
        PluginNode(
            kind,
            id       : id,
            modifiers: modifiers + [modifier],
            children : children,
            layers   : layer.map { layers + [$0] } ?? layers
        )
    }

    private static func layer(
        _ nodes  : [PluginNode],
        alignment: PluginAlignment
    ) -> PluginNode {
        nodes.count == 1 ? nodes[0] : PluginNode(.zStack(alignment: alignment), children: nodes)
    }
}
