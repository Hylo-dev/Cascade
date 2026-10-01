//
//  PluginWidgetSurface.swift
//  CascadeKit
//

import Foundation

/// PluginWidgetSurface declares that a feature can fill a widget slot, in the sizes it lists.
/// The user picks the size and the position; a plugin never places itself.
public struct PluginWidgetSurface: Codable, Equatable, Sendable {

    public let sizes: [PluginWidgetSize]

    public init(sizes: [PluginWidgetSize]) throws {
        self.sizes = sizes

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        sizes         = try container.decode([PluginWidgetSize].self, forKey: .sizes)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require((1...8).contains(sizes.count), "A widget declares one to eight sizes")
        try ContractValidation.require(Set(sizes).count == sizes.count, "Duplicate widget sizes")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case sizes
    }
}
