//
//  PluginDocument+Validation.swift
//  CascadeKit
//

import Foundation

extension PluginDocument {

    /// validate enforces every limit and every value's range, then encodes the document once to
    /// check its real size, so a document the SDK accepts in process always fits on the wire.
    /// That costs one encoding per publication, at human frequency. A decoded document skips
    /// the encoding: `decode` already bounded the bytes it came from.
    public func validate() throws {
        try validateStructure()
        try ContractValidation.bytes(self, maximum: Self.maximumBytes)
    }

    /// validateStructure checks the limits and ranges in one depth-first walk that stops at the
    /// first violation, so rejecting a document costs at most the node budget.
    func validateStructure() throws {
        try ContractValidation.require(schema == Self.schemaVersion, "Unsupported document schema")
        try ContractValidation.require(glassLights.count <= GlassLight.maximumCount, "Too many glass lights")

        var budget = ValidationBudget()
        try Self.visit(root, depth: 1, budget: &budget)
    }

    /// componentReferences lists the tier-2 components the document shows, for the kernel to
    /// compare with what the publishing feature declared.
    public var componentReferences: Set<PluginComponentReference> {
        var references = Set<PluginComponentReference>()
        var pending    = [root]

        while let node = pending.popLast() {
            if case .component(let id, let version, _) = node.kind,
               let reference = try? PluginComponentReference(id: id, version: version) {
                references.insert(reference)
            }
            pending.append(contentsOf: node.children)
            pending.append(contentsOf: node.layers)
        }

        return references
    }

    private static func visit(
        _ node: PluginNode,
        depth : Int,
        budget: inout ValidationBudget
    ) throws {
        budget.nodes += 1

        try ContractValidation.require(budget.nodes <= maximumNodes, "Document exceeds \(maximumNodes) nodes")
        try ContractValidation.require(depth <= maximumDepth, "Document deeper than \(maximumDepth)")
        try ContractValidation.require(
            node.kind.takesChildren || node.children.isEmpty,
            "A \(node.kind.name) node takes no children"
        )
        try ContractValidation.require(
            node.kind != .regions || depth == 1 && node.children.count == 3,
            "Regions are a document's root, with three regions"
        )
        try ContractValidation.require(
            node.modifiers.count <= maximumModifiers,
            "A node takes at most \(maximumModifiers) modifiers"
        )
        try ContractValidation.require(
            node.modifiers.count(where: \.isLayer) == node.layers.count,
            "Every overlay and background needs exactly one layer"
        )

        if let id = node.id {
            try ContractValidation.require(ContractValidation.identifier(id), "Invalid node ID")
            try ContractValidation.require(budget.explicitIDs.insert(id).inserted, "Duplicate node ID")
        }

        try validate(kind: node.kind)
        for modifier in node.modifiers {
            try validate(modifier: modifier)
        }

        for child in node.children + node.layers {
            try visit(child, depth: depth + 1, budget: &budget)
        }
    }

    private static func validate(kind: PluginNodeKind) throws {
        switch kind {
            case .vStack(_, let spacing), .hStack(_, let spacing):
                try length(spacing)

            case .zStack, .clock, .today, .regions:
                break

            case .spacer(let minimumLength):
                try length(minimumLength)

            case .text(let text):
                try ContractValidation.require(text.utf8.count <= 4_096, "Text exceeds 4 KiB")

            case .symbol(let name):
                try ContractValidation.require(ContractValidation.identifier(name), "Invalid symbol name")

            case .asset(let id):
                try ContractValidation.require(ContractValidation.identifier(id), "Invalid asset ID")

            case .shape(let shape):
                try validate(shape: shape)

            case .date(let date, _):
                try ContractValidation.finite(date)

            case .timer(let start, let end, _), .timerProgress(let start, let end):
                try ContractValidation.finite(start)
                try ContractValidation.finite(end)
                try ContractValidation.require(start <= end, "A timer ends before it starts")

            case .progress(let value, let total, _):
                try ContractValidation.require(
                    total.isFinite && total > 0 && value.isFinite && (0...total).contains(value),
                    "Invalid progress"
                )

            case .button(let action), .toggle(_, let action):
                try ContractValidation.require(ContractValidation.identifier(action), "Invalid action ID")

            case .slider(let value, let minimum, let maximum, let step, let action):
                try ContractValidation.require(ContractValidation.identifier(action), "Invalid action ID")
                try ContractValidation.require(
                    minimum.isFinite && maximum.isFinite && minimum < maximum
                        && value.isFinite && (minimum...maximum).contains(value),
                    "Invalid slider range"
                )
                try ContractValidation.require(
                    step.map { $0.isFinite && $0 > 0 && $0 <= maximum - minimum } ?? true,
                    "Invalid slider step"
                )

            case .component(let id, let version, let parameters):
                try ContractValidation.require(ContractValidation.identifier(id) && version >= 1, "Invalid component")
                try ContractValidation.require(parameters.count <= 16, "Too many component parameters")

                for (key, value) in parameters {
                    try ContractValidation.require(ContractValidation.identifier(key), "Invalid component parameter")
                    try validate(value: value)
                }
        }
    }

    private static func validate(modifier: PluginModifier) throws {
        switch modifier {
            case .font(let font):
                try ContractValidation.require((font.style == nil) != (font.size == nil), "A font has a style or a size")
                try ContractValidation.require(
                    font.size.map { $0.isFinite && (1...200).contains($0) } ?? true,
                    "Invalid font size"
                )

            case .foregroundStyle(.color(let color)):
                try validate(color: color)

            case .foregroundStyle(.hierarchical):
                break

            case .foregroundStyle(.gradient(let colors)):
                try ContractValidation.require((2...4).contains(colors.count), "A gradient has two to four colors")
                for color in colors {
                    try validate(color: color)
                }

            case .frame(let width, let height, let maximumWidth, let maximumHeight, _):
                try length(width)
                try length(height)
                try dimension(maximumWidth)
                try dimension(maximumHeight)

            case .padding(_, let paddingLength):
                try length(paddingLength)

            case .opacity(let opacity):
                try ContractValidation.require(opacity.isFinite && (0...1).contains(opacity), "Invalid opacity")

            case .clipShape(let shape):
                try validate(shape: shape)

            case .lineLimit(let lines):
                try ContractValidation.require((1...16).contains(lines), "Invalid line limit")

            case .minimumScaleFactor(let factor):
                try ContractValidation.require(factor.isFinite && factor > 0 && factor <= 1, "Invalid scale factor")

            case .transition(.move(let edges)):
                try ContractValidation.require(
                    [.top, .bottom, .leading, .trailing].contains(edges),
                    "A move transition takes one edge"
                )

            case .accessibilityLabel(let label):
                try ContractValidation.require(label.utf8.count <= 512, "Accessibility label exceeds 512 bytes")

            case .contentTransition, .transition, .overlay, .background:
                break
        }
    }

    private static func validate(shape: PluginShape) throws {
        if case .roundedRectangle(let cornerRadius) = shape {
            try length(cornerRadius)
        }
    }

    private static func validate(color: PluginColor) throws {
        try ContractValidation.require(
            [color.red, color.green, color.blue, color.opacity].allSatisfy { $0.isFinite && (0...1).contains($0) },
            "Invalid color"
        )
    }

    private static func validate(value: PluginValue) throws {
        switch value {
            case .string(let text):
                try ContractValidation.require(text.utf8.count <= 256, "Component parameter exceeds 256 bytes")

            case .number(let number):
                try ContractValidation.require(number.isFinite, "Component parameter is not finite")

            case .bool:
                break
        }
    }

    /// length accepts a missing length or a finite one from 0 to 10,000 points.
    private static func length(_ value: Double?) throws {
        try ContractValidation.require(
            value.map { $0.isFinite && (0...10_000).contains($0) } ?? true,
            "Invalid length"
        )
    }

    private static func dimension(_ value: PluginDimension?) throws {
        if case .points(let points) = value {
            try length(points)
        }
    }
}

/// ValidationBudget is what one validation walk has spent so far.
private struct ValidationBudget {

    var nodes       = 0
    var explicitIDs = Set<String>()
}
