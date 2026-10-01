//
//  ContentNode.swift
//  CascadeKit
//

import Foundation

/// ContentNode is a validated value in the version 1 addon protocol.
public struct ContentNode: Codable, Equatable, Sendable {

    public let accessibilityLabel: String?
    public let actionPayload     : Data?
    public let clockFormat       : ClockFormat?
    public let kind              : Kind
    public let text              : String?
    public let assetID           : String?
    public let value             : Double?
    public let deadline          : Date?
    public let actionID          : String?
    public let children          : [ContentNode]?
    public let fileWorkspace     : FileWorkspacePresentation?

    public init(
        kind              : Kind,
        text              : String?,
        assetID           : String?,
        value             : Double?,
        deadline          : Date?,
        actionID          : String?,
        children          : [ContentNode]?,
        accessibilityLabel: String? = nil,
        actionPayload     : Data? = nil,
        clockFormat       : ClockFormat? = nil,
        fileWorkspace     : FileWorkspacePresentation? = nil
    ) throws {
        self.accessibilityLabel = accessibilityLabel
        self.actionPayload      = actionPayload
        self.clockFormat        = clockFormat
        self.kind               = kind
        self.text               = text
        self.assetID            = assetID
        self.value              = value
        self.deadline           = deadline
        self.actionID           = actionID
        self.children           = children
        self.fileWorkspace      = fileWorkspace

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        var remainingNodes = 128
        try self.init(
            from          : decoder,
            depth         : 1,
            remainingNodes: &remainingNodes
        )
    }

    /// init shares one tree budget across siblings before any child value is materialized.
    private init(
        from decoder  : any Decoder,
        depth         : Int,
        remainingNodes: inout Int
    ) throws {
        try ContractValidation.require(
            depth <= 8 && remainingNodes > 0,
            "Content tree exceeds depth or node count"
        )
        remainingNodes -= 1

        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container      = try decoder.container(keyedBy: CodingKeys.self)
        accessibilityLabel = try container.decodeIfPresent(
            String.self,
            forKey: .accessibilityLabel
        )
        actionPayload      = try container.decodeIfPresent(Data.self, forKey: .actionPayload)
        clockFormat        = try container.decodeIfPresent(ClockFormat.self, forKey: .clockFormat)
        kind               = try container.decode(Kind.self, forKey: .kind)
        text               = try container.decodeIfPresent(String.self, forKey: .text)
        assetID            = try container.decodeIfPresent(String.self, forKey: .assetID)
        value              = try container.decodeIfPresent(Double.self, forKey: .value)
        deadline           = try container.decodeIfPresent(Date.self, forKey: .deadline)
        actionID           = try container.decodeIfPresent(String.self, forKey: .actionID)
        fileWorkspace      = try container.decodeIfPresent(
            FileWorkspacePresentation.self,
            forKey: .fileWorkspace
        )

        if container.contains(.children), try !container.decodeNil(forKey: .children) {
            var values = try container.nestedUnkeyedContainer(forKey: .children)
            try ContractValidation.require(
                values.count.map { $0 <= remainingNodes } ?? true,
                "Content tree exceeds depth or node count"
            )

            var decoded: [ContentNode] = []
            if let count = values.count { decoded.reserveCapacity(count) }

            while !values.isAtEnd {
                try ContractValidation.require(
                    depth < 8 && remainingNodes > 0,
                    "Content tree exceeds depth or node count"
                )

                let child = try ContentNode(
                    from          : values.superDecoder(),
                    depth         : depth + 1,
                    remainingNodes: &remainingNodes
                )
                decoded.append(child)
            }

            children = decoded
        } else {
            children = nil
        }

        try validate()
    }

    public func validate() throws {
        if let accessibilityLabel {
            try ContractValidation.require(
                !accessibilityLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && accessibilityLabel.utf8.count <= 4096,
                "Invalid node accessibility label"
            )
        }

        try ContractValidation.require(
            kind == .image || accessibilityLabel == nil,
            "Unexpected accessibility field"
        )
        try ContractValidation.require(
            kind == .action || actionPayload == nil,
            "Unexpected action payload"
        )
        try ContractValidation.require(kind == .clock || clockFormat == nil, "Unexpected clock format")
        try ContractValidation.require(
            kind == .fileWorkspace || fileWorkspace == nil,
            "Unexpected file workspace payload"
        )
        try ContractValidation.require(
            (actionPayload?.count ?? 0) <= 4096,
            "Action payload exceeds 4 KiB"
        )

        if kind == .image {
            try ContractValidation.require(
                accessibilityLabel != nil,
                "Image requires accessible label"
            )
        }

        if kind == .action {
            try ContractValidation.require(
                !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                "Button requires accessible label"
            )
        }

        if kind == .symbol {
            try ContractValidation.require(
                text.map {
                    $0.utf8.count <= 128
                        && $0.range(of: "^[a-z0-9]+([.][a-z0-9]+)*$", options: .regularExpression) != nil
                } ?? false,
                "Symbol must be a system symbol name; URLs are forbidden"
            )
        }

        try ContractValidation.require((text?.utf8.count ?? 0) <= 4096, "Text exceeds 4 KiB")
        try ContractValidation.require(
            assetID.map(ContractValidation.identifier) ?? true,
            "Invalid asset ID"
        )
        try ContractValidation.require(
            actionID.map(ContractValidation.identifier) ?? true,
            "Invalid action ID"
        )
        try ContractValidation.require((children?.count ?? 0) <= 128, "Too many children")

        if let deadline { try ContractValidation.finite(deadline) }

        if let value {
            try ContractValidation.require(
                value.isFinite && (0...1).contains(value),
                "Invalid progress"
            )
        }

        switch kind {
            case .text, .symbol:
                try ContractValidation.require(
                    text != nil && assetID == nil && value == nil && deadline == nil && actionID == nil
                        && children == nil && fileWorkspace == nil,
                    "Invalid text or symbol node"
                )

            case .image:
                try ContractValidation.require(
                    assetID != nil && text == nil && value == nil && deadline == nil && actionID == nil
                        && children == nil && fileWorkspace == nil,
                    "Invalid image node"
                )

            case .row, .column:
                try ContractValidation.require(
                    children != nil && text == nil && assetID == nil && value == nil && deadline == nil
                        && actionID == nil && fileWorkspace == nil,
                    "Invalid layout node"
                )

            case .progress:
                try ContractValidation.require(
                    value != nil && text == nil && assetID == nil && deadline == nil && actionID == nil
                        && children == nil && fileWorkspace == nil,
                    "Invalid progress node"
                )

            case .countdown:
                try ContractValidation.require(
                    deadline != nil && text == nil && assetID == nil && value == nil && actionID == nil
                        && children == nil && fileWorkspace == nil,
                    "Invalid countdown node"
                )

            case .clock:
                try ContractValidation.require(
                    text == nil && assetID == nil && value == nil && deadline == nil && actionID == nil
                        && children == nil && fileWorkspace == nil,
                    "Invalid clock node"
                )

            case .action:
                try ContractValidation.require(
                    actionID != nil && text != nil && assetID == nil && value == nil && deadline == nil
                        && children == nil && fileWorkspace == nil,
                    "Invalid action node"
                )

            case .fileWorkspace:
                try ContractValidation.require(
                    fileWorkspace != nil && text == nil && assetID == nil && value == nil && deadline == nil
                        && actionID == nil && children == nil,
                    "Invalid file workspace node"
                )
                try fileWorkspace?.validate()
        }

        var count = 0
        try validateTree(depth: 1, count: &count)
    }

    public enum Kind: String, Codable, Sendable {

        case text, symbol, image, row, column, progress, countdown, clock, action, fileWorkspace
    }

    func validateTree(
        depth: Int,
        count: inout Int
    ) throws {
        count += 1
        try ContractValidation.require(
            depth <= 8 && count <= 128,
            "Content tree exceeds depth or node count"
        )

        for child in children ?? [] { try child.validateTree(depth: depth + 1, count: &count) }
    }

    var referencedAssets: Set<String> {
        var result = Set(children?.flatMap { $0.referencedAssets } ?? [])
        if let assetID { result.insert(assetID) }
        if let fileWorkspace { result.formUnion(fileWorkspace.referencedAssets) }

        return result
    }

    var actionIdentifiers: [String] {
        (actionID.map { [$0] } ?? []) + (fileWorkspace?.actionIdentifiers ?? [])
            + (children?.flatMap(\.actionIdentifiers) ?? [])
    }

    var containsFileWorkspace: Bool {
        kind == .fileWorkspace || (children?.contains(where: \.containsFileWorkspace) ?? false)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case accessibilityLabel
        case actionPayload
        case clockFormat
        case kind
        case text
        case assetID
        case value
        case deadline
        case actionID
        case children
        case fileWorkspace
    }
}
