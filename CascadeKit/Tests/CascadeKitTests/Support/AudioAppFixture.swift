//
//  AudioAppFixture.swift
//  CascadeKit
//

import CascadeContracts
@testable import CascadeKit

/// AudioAppFixture builds the contract values the per-app tests feed the model. The contract
/// initializers validate and throw, so each helper forwards the throw and the tests mark it
/// with `try`.
enum AudioAppFixture {

    static func identity(_ bundleID: String) throws -> AudioAppIdentity {
        try AudioAppIdentity(bundleID: bundleID)
    }

    static func intent(
        gain      : Double = 1,
        isMuted   : Bool = false,
        outputUIDs: [String] = []
    ) throws -> AudioAppIntent {
        try AudioAppIntent(gain: gain, isMuted: isMuted, outputUIDs: outputUIDs)
    }

    static func app(
        _ bundleID         : String,
        name               : String? = nil,
        intent             : AudioAppIntent = .neutral,
        enforcement        : AudioAppEnforcement = .native,
        effectiveOutputUIDs: [String] = []
    ) throws -> AudioAppSnapshot {
        try AudioAppSnapshot(
            identity           : identity(bundleID),
            displayName        : name ?? bundleID,
            intent             : intent,
            enforcement        : enforcement,
            effectiveOutputUIDs: effectiveOutputUIDs
        )
    }

    static func snapshot(
        _ apps        : [AudioAppSnapshot],
        generation    : UInt64 = 1,
        captureAllowed: Bool? = nil
    ) throws -> AudioHostSnapshot {
        try AudioHostSnapshot(
            generation    : generation,
            apps          : apps,
            captureAllowed: captureAllowed
        )
    }
}
