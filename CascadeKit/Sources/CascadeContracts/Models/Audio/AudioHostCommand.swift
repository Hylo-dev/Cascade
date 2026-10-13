//
//  AudioHostCommand.swift
//  CascadeKit
//

import Foundation

/// AudioHostCommand is what the mixer tells AudioHost to do. `replaceIntents` carries the
/// whole set and is sent when a connection starts, so a restarted AudioHost converges on what
/// the user chose without having to remember anything; `setIntent` and `returnToNative` are the
/// deltas after that.
///
/// The set travels as a list of entries, not as a dictionary: a dictionary keyed by a struct
/// would encode as a flat key/value array nobody can validate, while a list of `{identity,
/// intent}` objects is checked field by field and rejects a repeated app.
public enum AudioHostCommand: Codable, Equatable, Sendable {

    public static let maximumIntents = 256

    case replaceIntents([AudioAppIdentity: AudioAppIntent])
    case setIntent(AudioAppIdentity, AudioAppIntent)
    case returnToNative(AudioAppIdentity)

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind      = try container.decode(Kind.self, forKey: .kind)

        switch kind {
            case .replaceIntents:
                let entries = try container.decode([Entry].self, forKey: .intents)
                try ContractValidation.require(entries.count <= Self.maximumIntents, "Too many audio intents")

                let intents = Dictionary(entries.map { ($0.identity, $0.intent) }) { first, _ in first }
                try ContractValidation.require(intents.count == entries.count, "Duplicate audio intents")
                self = .replaceIntents(intents)

            case .setIntent:
                self = .setIntent(
                    try container.decode(AudioAppIdentity.self, forKey: .identity),
                    try container.decode(AudioAppIntent.self, forKey: .intent)
                )

            case .returnToNative:
                self = .returnToNative(try container.decode(AudioAppIdentity.self, forKey: .identity))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
            case .replaceIntents(let intents):
                try ContractValidation.require(intents.count <= Self.maximumIntents, "Too many audio intents")

                try container.encode(Kind.replaceIntents, forKey: .kind)
                try container.encode(
                    intents.map { Entry(identity: $0.key, intent: $0.value) },
                    forKey: .intents
                )

            case .setIntent(let identity, let intent):
                try container.encode(Kind.setIntent, forKey: .kind)
                try container.encode(identity, forKey: .identity)
                try container.encode(intent, forKey: .intent)

            case .returnToNative(let identity):
                try container.encode(Kind.returnToNative, forKey: .kind)
                try container.encode(identity, forKey: .identity)
        }
    }

    private enum Kind: String, Codable {

        case replaceIntents
        case setIntent
        case returnToNative
    }

    private struct Entry: Codable {

        let identity: AudioAppIdentity
        let intent  : AudioAppIntent
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case kind
        case intents
        case identity
        case intent
    }
}
