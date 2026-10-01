//
//  FileConversionFormat.swift
//  CascadeKit
//

import Foundation

/// FileConversionFormat names one broker-supported output format without exposing a command line.
public struct FileConversionFormat: Codable, Equatable, Sendable {

    public let id                  : String
    public let label               : String
    public let outputTypeIdentifier: String

    public init(
        id                  : String,
        label               : String,
        outputTypeIdentifier: String
    ) throws {
        self.id                   = id
        self.label                = label
        self.outputTypeIdentifier = outputTypeIdentifier

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)),
            "Invalid conversion format fields"
        )

        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id                  : values.decode(String.self, forKey: .id),
            label               : values.decode(String.self, forKey: .label),
            outputTypeIdentifier: values.decode(String.self, forKey: .outputTypeIdentifier)
        )
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(id),
            "Invalid conversion format ID"
        )
        try ContractValidation.require(
            !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && label.utf8.count <= 4_096,
            "Invalid conversion format label"
        )
        try FileWorkspaceWire.validateTypeIdentifier(outputTypeIdentifier)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id, label, outputTypeIdentifier
    }
}
