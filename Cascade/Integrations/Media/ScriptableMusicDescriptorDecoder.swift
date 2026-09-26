//
//  ScriptableMusicDescriptorDecoder.swift
//  Cascade
//

import CoreServices
import Foundation

/// ScriptableMusicDescriptorDecoder converts native scripting descriptors into
/// small Sendable values. Missing fields remain unknown; the native descriptor
/// objects never leave the background reader that owns their lifetime.
nonisolated enum ScriptableMusicDescriptorDecoder {
    static func metadata(
        _ properties: NSAppleEventDescriptor,
        source: ScriptableMusicSource
    ) -> ScriptableTrackMetadata {
        let identifierCode = source == .music ? "pPIS" : "ID  "
        let identifier = properties.forKeyword(code(identifierCode))?.stringValue
        let favoriteDescriptor = properties.forKeyword(code("pLov"))
        let favorite = favoriteDescriptor.flatMap { $0.descriptorType == typeBoolean ? $0.booleanValue : nil }
        return ScriptableTrackMetadata(
            identifier: identifier.flatMap { $0.isEmpty ? nil : $0 },
            title     : properties.forKeyword(code("pnam"))?.stringValue ?? "",
            artist    : properties.forKeyword(code("pArt"))?.stringValue ?? "",
            duration  : properties.forKeyword(code("pDur"))?.doubleValue,
            favorite  : favorite
        )
    }

    static func playbackState(_ value: OSType) -> ScriptablePlaybackState {
        switch value {
        case code("kPSP"): .playing
        case code("kPSp"): .paused
        case code("kPSF"), code("kPSR"): .scrubbing
        default: .stopped
        }
    }

    private static func code(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}
