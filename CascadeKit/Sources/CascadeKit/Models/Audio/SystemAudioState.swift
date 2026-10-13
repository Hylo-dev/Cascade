//
//  SystemAudioState.swift
//  CascadeKit
//

/// SystemAudioState is one reading of the system output, as the audio service saw it.
///
/// `level` and `isMuted` belong to the device named by `defaultDeviceID`, a HAL id that changes
/// when the user switches output. Anyone acting on the level must carry that id with the command,
/// so a late command for the old device is dropped instead of landing on the new one.
/// `selectedUIDs` is the system output: one uid for a plain default, several while the
/// multi-output is active, the clock device first.
nonisolated public struct SystemAudioState: Equatable, Sendable {

    public let level          : Double
    public let isMuted        : Bool
    public let supportsVolume : Bool
    public let outputs        : [AudioOutputDevice]
    public let selectedUIDs   : [String]
    public let defaultDeviceID: UInt32

    public init(
        level          : Double,
        isMuted        : Bool,
        supportsVolume : Bool,
        outputs        : [AudioOutputDevice],
        selectedUIDs   : [String],
        defaultDeviceID: UInt32
    ) {
        self.level           = level
        self.isMuted         = isMuted
        self.supportsVolume  = supportsVolume
        self.outputs         = outputs
        self.selectedUIDs    = selectedUIDs
        self.defaultDeviceID = defaultDeviceID
    }

    /// replacing returns the same reading with a different level, mute or selection: the
    /// optimistic state the model shows before the service confirms.
    func replacing(
        level       : Double? = nil,
        isMuted     : Bool? = nil,
        selectedUIDs: [String]? = nil
    ) -> SystemAudioState {
        SystemAudioState(
            level          : level ?? self.level,
            isMuted        : isMuted ?? self.isMuted,
            supportsVolume : supportsVolume,
            outputs        : outputs,
            selectedUIDs   : selectedUIDs ?? self.selectedUIDs,
            defaultDeviceID: defaultDeviceID
        )
    }
}
