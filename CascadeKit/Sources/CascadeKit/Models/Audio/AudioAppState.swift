//
//  AudioAppState.swift
//  CascadeKit
//

import CascadeContracts

/// AudioAppState is one app column as the mixer draws it: AudioHost's report on the app, with the
/// user's latest gesture laid over it until the next report confirms or replaces it. `intent` is
/// what the user asked, `enforcement` is how far AudioHost got, and `effectiveOutputUIDs` is
/// where the sound actually goes; the three are kept apart so the column never claims a control
/// the app does not have.
///
/// The optimistic edits (`replacing`) build the intent through the contract's validating
/// initializer. The values come from an intent that was already valid and from a gain the model
/// clamped, so it cannot refuse; if it ever did, the unchanged intent is kept, which shows the
/// previous state instead of inventing one.
nonisolated public struct AudioAppState: Equatable, Sendable {

    public let identity           : AudioAppIdentity
    public let displayName        : String
    public let intent             : AudioAppIntent
    public let enforcement        : AudioAppEnforcement
    public let effectiveOutputUIDs: [String]

    /// isIntentUnmet is true when the user asked for something and the app plays natively anyway:
    /// AudioHost could not apply it (`notApplied`) or has not yet (`native`). The column draws
    /// its capsule dashed and offers "Return to native audio", so the control stops promising
    /// what it does not deliver. A neutral intent asks for nothing, so there is nothing unmet.
    public var isIntentUnmet: Bool {
        !intent.isNeutral && (enforcement == .notApplied || enforcement == .native)
    }

    /// isRecovering is true while AudioHost rebuilds the app's tap, which is audible natively in
    /// the meantime.
    public var isRecovering: Bool {
        enforcement == .recovering
    }

    public init(
        identity           : AudioAppIdentity,
        displayName        : String,
        intent             : AudioAppIntent,
        enforcement        : AudioAppEnforcement,
        effectiveOutputUIDs: [String]
    ) {
        self.identity            = identity
        self.displayName         = displayName
        self.intent              = intent
        self.enforcement         = enforcement
        self.effectiveOutputUIDs = effectiveOutputUIDs
    }

    public init(_ snapshot: AudioAppSnapshot) {
        self.init(
            identity           : snapshot.identity,
            displayName        : snapshot.displayName,
            intent             : snapshot.intent,
            enforcement        : snapshot.enforcement,
            effectiveOutputUIDs: snapshot.effectiveOutputUIDs
        )
    }

    /// replacing returns the same app with a different gain, mute or output selection: the
    /// optimistic state the model shows before AudioHost reports back.
    func replacing(
        gain      : Double? = nil,
        isMuted   : Bool? = nil,
        outputUIDs: [String]? = nil
    ) -> AudioAppState {
        let edited = (try? AudioAppIntent(
            gain      : gain ?? intent.gain,
            isMuted   : isMuted ?? intent.isMuted,
            outputUIDs: outputUIDs ?? intent.outputUIDs
        )) ?? intent

        return replacing(intent: edited)
    }

    func replacing(intent: AudioAppIntent) -> AudioAppState {
        AudioAppState(
            identity           : identity,
            displayName        : displayName,
            intent             : intent,
            enforcement        : enforcement,
            effectiveOutputUIDs: effectiveOutputUIDs
        )
    }

    func replacing(enforcement: AudioAppEnforcement) -> AudioAppState {
        AudioAppState(
            identity           : identity,
            displayName        : displayName,
            intent             : intent,
            enforcement        : enforcement,
            effectiveOutputUIDs: effectiveOutputUIDs
        )
    }
}
