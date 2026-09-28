//
//  ScriptableMusicAppleEventReader.swift
//  Cascade
//

import CascadeKit
import CoreServices
import Foundation

/// ScriptableMusicAppleEventReader uses the players' native AppleEvent
/// dictionaries. It never loads MediaRemote or runs an interpreter. macOS
/// Automation authorization is checked silently on reads. The separate access
/// request is used by startup setup and the menu's retry action.
actor ScriptableMusicAppleEventReader: ScriptableMusicReading {

    private struct ArtworkCache {

        let identity: String
        let data    : Data
    }

    private var artwork: [ScriptableMusicSource: ArtworkCache] = [:]

    func requestAccess(_ target: ScriptablePlayerTarget) throws {
        try authorize(target, request: true)
    }

    func reset() {
        artwork.removeAll()
    }

    func discardArtwork(_ source: ScriptableMusicSource) {
        artwork[source] = nil
    }

    /// read has one bounded AppleEvent budget for all metadata. Optional
    /// artwork has its own small budget and can never discard valid playback.
    func read(_ target: ScriptablePlayerTarget) async throws -> NowPlayingSnapshot? {
        try Task.checkCancellation()
        try authorize(target, request: false)

        let deadline  = Date.now.addingTimeInterval(3)
        let stateCode = try getProperty(
            "pPlS",
            target  : target,
            deadline: deadline
        ).enumCodeValue
        let state = ScriptableMusicDescriptorDecoder.playbackState(stateCode)
        guard state != .stopped else {
            artwork[target.source] = nil
            return nil
        }

        let track = try getProperty(
            "pTrk",
            target  : target,
            deadline: deadline
        )
        let properties = try getProperty(
            "pALL",
            of      : track,
            target  : target,
            deadline: deadline
        )
        let metadata = ScriptableMusicDescriptorDecoder.metadata(properties, source: target.source)
        let position = try getProperty(
            "pPos",
            target  : target,
            deadline: deadline
        ).doubleValue
        let timestamp = Date.now

        // A player can advance between events. Re-read identity before handing
        // data across the actor boundary; the next notification triggers retry.
        let currentTrack = try getProperty(
            "pTrk",
            target  : target,
            deadline: deadline
        )
        guard currentTrack.data == track.data else { throw ScriptableMusicError.trackChanged }

        var artworkData = artwork[target.source].flatMap {
            $0.identity == metadata.identity ? $0.data : nil
        }
        if artworkData == nil {
            artwork[target.source] = nil

            if target.source == .music {
                let artworkDeadline = Date.now.addingTimeInterval(1)
                if let firstArtwork = Self.element(
                    "cArt",
                    index    : 1,
                    container: track
                ),
                   let raw = try? getProperty(
                       "pRaw",
                       of      : firstArtwork,
                       target  : target,
                       deadline: artworkDeadline
                   ) {
                    artworkData = ScriptableMusicArtwork.thumbnail(raw.data)
                }
            } else if let url = properties.forKeyword(Self.code("aUrl"))?.stringValue {
                artworkData = try? await ScriptableMusicArtwork.spotifyArtwork(url)
            }

            try Task.checkCancellation()
            if let artworkData {
                artwork[target.source] = ArtworkCache(
                    identity: metadata.identity,
                    data    : artworkData
                )
            }
        }

        return metadata.snapshot(
            source     : target.source,
            state      : state,
            elapsed    : position,
            timestamp  : timestamp,
            artworkData: artworkData
        )
    }

    /// send checks track identity before destructive-to-position or favorite
    /// commands. It never updates UI optimistically; the provider performs a
    /// fresh read after a successful command even if the player emits no event.
    func send(
        _ command    : MediaCommand,
        to target    : ScriptablePlayerTarget,
        expectedTrack: String?
    ) throws {
        try Task.checkCancellation()
        try authorize(target, request: false)

        let deadline = Date.now.addingTimeInterval(3)
        switch command {
            case .togglePlayback:
                _ = try perform(
                    eventClass: target.source == .music ? "hook" : "spfy",
                    eventID   : "PlPs",
                    target    : target,
                    deadline  : deadline
                )

            case .previousTrack:
                _ = try perform(
                    eventClass: target.source == .music ? "hook" : "spfy",
                    eventID   : "Prev",
                    target    : target,
                    deadline  : deadline
                )

            case .nextTrack:
                _ = try perform(
                    eventClass: target.source == .music ? "hook" : "spfy",
                    eventID   : "Next",
                    target    : target,
                    deadline  : deadline
                )

            case .seek(let seconds):
                guard seconds.isFinite else {
                    throw ScriptableMusicError.unavailable("Posizione di riproduzione non valida.")
                }

                let (_, metadata) = try currentMetadata(target, deadline: deadline)
                guard expectedTrack == metadata.identity else {
                    throw ScriptableMusicError.trackChanged
                }

                let duration = metadata.duration.map { target.source == .spotify ? $0 / 1_000 : $0 }
                guard let duration, duration.isFinite, duration > 0 else {
                    throw ScriptableMusicError.unavailable(
                        "Questo contenuto non consente di cambiare posizione."
                    )
                }

                try setProperty(
                    "pPos",
                    value   : NSAppleEventDescriptor(double: min(duration, max(0, seconds))),
                    target  : target,
                    deadline: deadline
                )

            case .toggleFavorite:
                guard target.source == .music else {
                    throw ScriptableMusicError.unavailable("Questo lettore non espone i preferiti.")
                }

                let (track, metadata) = try currentMetadata(target, deadline: deadline)
                guard expectedTrack == metadata.identity else {
                    throw ScriptableMusicError.trackChanged
                }
                guard let favorite = metadata.favorite else {
                    throw ScriptableMusicError.unavailable(
                        "Il lettore non ha fornito lo stato dei preferiti."
                    )
                }

                try setProperty(
                    "pLov",
                    of      : track,
                    value   : NSAppleEventDescriptor(boolean: !favorite),
                    target  : target,
                    deadline: deadline
                )
        }
    }

    private func currentMetadata(
        _ target: ScriptablePlayerTarget,
        deadline: Date
    ) throws -> (NSAppleEventDescriptor, ScriptableTrackMetadata) {
        let track = try getProperty(
            "pTrk",
            target  : target,
            deadline: deadline
        )
        let properties = try getProperty(
            "pALL",
            of      : track,
            target  : target,
            deadline: deadline
        )

        return (track, ScriptableMusicDescriptorDecoder.metadata(properties, source: target.source))
    }

    /// authorize never treats permission denial as an empty player. Passing
    /// false cannot display a prompt, including during application launch.
    private func authorize(
        _ target: ScriptablePlayerTarget,
        request : Bool
    ) throws {
        let address = NSAppleEventDescriptor(processIdentifier: target.processIdentifier)
        let result  = AEDeterminePermissionToAutomateTarget(
            address.aeDesc,
            typeWildCard,
            typeWildCard,
            request
        )
        guard result == noErr else {
            if result == errAEEventNotPermitted || result == errAEEventWouldRequireUserConsent {
                throw ScriptableMusicError.permissionRequired(target.source)
            }
            throw ScriptableMusicError.unavailable(
                "\(target.source.displayName) non è disponibile (\(result))."
            )
        }
    }

    private func getProperty(
        _ name      : String,
        of container: NSAppleEventDescriptor? = nil,
        target      : ScriptablePlayerTarget,
        deadline    : Date
    ) throws -> NSAppleEventDescriptor {
        let object = try Self.property(name, container: container)

        return try perform(
            eventClass  : "core",
            eventID     : "getd",
            directObject: object,
            target      : target,
            deadline    : deadline
        )
    }

    private func setProperty(
        _ name      : String,
        of container: NSAppleEventDescriptor? = nil,
        value       : NSAppleEventDescriptor,
        target      : ScriptablePlayerTarget,
        deadline    : Date
    ) throws {
        let object = try Self.property(name, container: container)

        _ = try perform(
            eventClass  : "core",
            eventID     : "setd",
            directObject: object,
            value       : value,
            target      : target,
            deadline    : deadline
        )
    }

    /// perform is the only synchronous IO entry point. The reader actor keeps
    /// it off the main actor, and a total operation deadline bounds unresponsive
    /// players rather than multiplying a timeout by the number of properties.
    private func perform(
        eventClass  : String,
        eventID     : String,
        directObject: NSAppleEventDescriptor? = nil,
        value       : NSAppleEventDescriptor? = nil,
        target      : ScriptablePlayerTarget,
        deadline    : Date
    ) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            throw ScriptableMusicError.unavailable("\(target.source.displayName) non risponde.")
        }

        let event = NSAppleEventDescriptor(
            eventClass      : Self.code(eventClass),
            eventID         : Self.code(eventID),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: target.processIdentifier),
            returnID        : AEReturnID(kAutoGenerateReturnID),
            transactionID   : AETransactionID(kAnyTransactionID)
        )
        if let directObject { event.setParam(directObject, forKeyword: keyDirectObject) }
        if let value { event.setParam(value, forKeyword: keyAEData) }

        let reply: NSAppleEventDescriptor
        do {
            reply = try event.sendEvent(
                options: [.waitForReply, .neverInteract, .dontRecord],
                timeout: min(1, remaining)
            )
        } catch {
            let error = error as NSError
            if error.code == Int(errAEEventNotPermitted) {
                throw ScriptableMusicError.permissionRequired(target.source)
            }
            throw ScriptableMusicError.unavailable(
                "\(target.source.displayName) non risponde (\(error.code))."
            )
        }

        let errorNumber = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        guard errorNumber == 0 else {
            if errorNumber == errAEEventNotPermitted {
                throw ScriptableMusicError.permissionRequired(target.source)
            }
            throw ScriptableMusicError.unavailable(
                "\(target.source.displayName) non ha completato la richiesta (\(errorNumber))."
            )
        }

        return reply.paramDescriptor(forKeyword: keyDirectObject) ?? NSAppleEventDescriptor.null()
    }

    private static func property(
        _ name   : String,
        container: NSAppleEventDescriptor?
    ) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(
            NSAppleEventDescriptor(typeCode: typeProperty),
            forKeyword: AEKeyword(keyAEDesiredClass)
        )
        record.setDescriptor(
            container ?? NSAppleEventDescriptor.null(),
            forKeyword: AEKeyword(keyAEContainer)
        )
        record.setDescriptor(
            NSAppleEventDescriptor(enumCode: OSType(formPropertyID)),
            forKeyword: AEKeyword(keyAEKeyForm)
        )
        record.setDescriptor(
            NSAppleEventDescriptor(typeCode: code(name)),
            forKeyword: AEKeyword(keyAEKeyData)
        )

        guard let result = record.coerce(toDescriptorType: typeObjectSpecifier) else {
            throw ScriptableMusicError.unavailable("Impossibile preparare la richiesta al lettore.")
        }
        return result
    }

    private static func element(
        _ name   : String,
        index    : Int32,
        container: NSAppleEventDescriptor
    ) -> NSAppleEventDescriptor? {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(
            NSAppleEventDescriptor(typeCode: code(name)),
            forKeyword: AEKeyword(keyAEDesiredClass)
        )
        record.setDescriptor(
            container,
            forKeyword: AEKeyword(keyAEContainer)
        )
        record.setDescriptor(
            NSAppleEventDescriptor(enumCode: OSType(formAbsolutePosition)),
            forKeyword: AEKeyword(keyAEKeyForm)
        )
        record.setDescriptor(
            NSAppleEventDescriptor(int32: index),
            forKeyword: AEKeyword(keyAEKeyData)
        )

        return record.coerce(toDescriptorType: typeObjectSpecifier)
    }

    private static func code(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
