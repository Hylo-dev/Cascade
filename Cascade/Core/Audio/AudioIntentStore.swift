//
//  AudioIntentStore.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// AudioIntentStore keeps what the user asked of each app, so a restart of Cascade, of AudioHost
/// or of the app itself finds the same volumes waiting. It is a request log, not a mirror of
/// reality: an intent stays stored while its output device is unplugged or its app is closed,
/// because the user's choice outlives both.
///
/// The set is one JSON value in `UserDefaults`, a list of `{identity, intent}` entries like the
/// wire form, and a neutral intent is never written: it asks for nothing, so storing it would
/// only make AudioHost start for no reason. An entry that no longer decodes is dropped alone; one
/// bad entry must not cost the user every other volume.
///
/// Reading and writing touch the disk's preferences, so the service calls them on its own queue,
/// never on the main thread.
nonisolated final class AudioIntentStore: Sendable {

    // UserDefaults is documented as safe to use from any thread, but the SDK does not mark it
    // Sendable; the store only reads and writes one key and never replaces the object.
    nonisolated(unsafe) private let defaults: UserDefaults

    private let key: String

    init(
        defaults: UserDefaults,
        key     : String = "audioAppIntents"
    ) {
        self.defaults = defaults
        self.key      = key
    }

    /// load returns the stored intents, neutral ones excluded.
    func load() -> [AudioAppIdentity: AudioAppIntent] {
        guard
            let data    = defaults.data(forKey: key),
            let entries = try? JSONDecoder().decode([Lossy].self, from: data)
        else { return [:] }

        var intents: [AudioAppIdentity: AudioAppIntent] = [:]
        for entry in entries.compactMap(\.entry).prefix(AudioHostCommand.maximumIntents) where !entry.intent.isNeutral {
            intents[entry.identity] = entry.intent
        }

        return intents
    }

    /// save replaces the stored set with `intents`, leaving the neutral ones out.
    func save(_ intents: [AudioAppIdentity: AudioAppIntent]) {
        let entries = intents
            .filter { !$0.value.isNeutral }
            .map { Entry(identity: $0.key, intent: $0.value) }

        guard let data = try? JSONEncoder().encode(entries) else { return }

        defaults.set(data, forKey: key)
    }

    private struct Entry: Codable {

        let identity: AudioAppIdentity
        let intent  : AudioAppIntent
    }

    /// Lossy decodes one entry or, when it does not decode, nothing, so the list around it still
    /// loads.
    private struct Lossy: Decodable {

        let entry: Entry?

        init(from decoder: any Decoder) throws {
            entry = try? Entry(from: decoder)
        }
    }
}
