//
//  FileConversionJobSnapshot.swift
//  CascadeKit
//

import Foundation

/// FileConversionJobSnapshot reports a bounded job result without private paths or error text.
public struct FileConversionJobSnapshot: Codable, Equatable, Sendable {

    public enum State: String, Codable, Equatable, Sendable {

        case queued, running, completed, failed, cancelled, interrupted
    }

    public let id       : UUID
    public let state    : State
    public let progress : Double?
    public let resultIDs: [UUID]

    public init(
        id       : UUID,
        state    : State,
        progress : Double?,
        resultIDs: [UUID]
    ) throws {
        self.id        = id
        self.state     = state
        self.progress  = progress
        self.resultIDs = resultIDs

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown conversion job field"
        )

        let values  = try decoder.container(keyedBy: CodingKeys.self)
        let results = try BoundedContractArray.decode(
            UUID.self,
            from   : values.superDecoder(forKey: .resultIDs),
            maximum: 32
        )

        try self.init(
            id       : values.decode(UUID.self, forKey: .id),
            state    : values.decode(State.self, forKey: .state),
            progress : values.decodeIfPresent(Double.self, forKey: .progress),
            resultIDs: results
        )
    }

    public func validate() throws {
        try FileWorkspaceWire.validateIDs(resultIDs, requiresNonempty: false)

        if let progress {
            try ContractValidation.require(
                progress.isFinite && (0...1).contains(progress),
                "Invalid conversion progress"
            )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id, state, progress, resultIDs
    }
}
