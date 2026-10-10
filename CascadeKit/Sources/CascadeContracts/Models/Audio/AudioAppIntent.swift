//
//  AudioAppIntent.swift
//  CascadeKit
//

import Foundation

/// AudioAppIntent is what the user asked for one app: how loud, whether silent, and where it
/// should play. It is a request, never a promise: AudioHost reports what it managed to enforce
/// in `AudioAppSnapshot`. The neutral intent (full gain, not muted, system output) asks for
/// nothing, which lets AudioHost leave the app untouched instead of tapping it.
public struct AudioAppIntent: Codable, Equatable, Sendable {

    public static let maximumOutputs  = 8
    public static let maximumUIDBytes  = 256

    /// neutral asks for nothing. It is built through a private initializer because its
    /// values are known valid, and the throwing public one would force a `try!` here.
    public static let neutral = AudioAppIntent(gain: 1, isMuted: false, outputUIDs: [], isTrusted: true)

    public let gain      : Double
    public let isMuted   : Bool
    public let outputUIDs: [String]

    public var isNeutral: Bool { gain == 1 && !isMuted && outputUIDs.isEmpty }

    public init(
        gain      : Double,
        isMuted   : Bool,
        outputUIDs: [String]
    ) throws {
        self.gain       = gain
        self.isMuted    = isMuted
        self.outputUIDs = outputUIDs

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        gain          = try container.decode(Double.self, forKey: .gain)
        isMuted       = try container.decode(Bool.self, forKey: .isMuted)
        outputUIDs    = try container.decode([String].self, forKey: .outputUIDs)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(gain.isFinite && (0...1).contains(gain), "Audio gain out of range")
        try ContractValidation.require(outputUIDs.count <= Self.maximumOutputs, "Too many audio outputs")
        try ContractValidation.require(
            outputUIDs.allSatisfy { !$0.isEmpty && $0.utf8.count <= Self.maximumUIDBytes },
            "Invalid audio output UID"
        )
        try ContractValidation.unique(outputUIDs, "Duplicate audio outputs")
    }

    private init(
        gain      : Double,
        isMuted   : Bool,
        outputUIDs: [String],
        isTrusted : Bool
    ) {
        self.gain       = gain
        self.isMuted    = isMuted
        self.outputUIDs = outputUIDs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case gain
        case isMuted
        case outputUIDs
    }
}
