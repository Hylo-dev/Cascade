//
//  VolumeMediaKey.swift
//  Cascade
//

/// VolumeMediaKey decodes the public IOKit auxiliary key event representation.
nonisolated struct VolumeMediaKey: Equatable, Sendable {

    let command  : VolumeKeyCommand
    let isPressed: Bool
    let isRepeat : Bool

    init(
        command  : VolumeKeyCommand,
        isPressed: Bool,
        isRepeat : Bool = false
    ) {
        self.command   = command
        self.isPressed = isPressed
        self.isRepeat  = isRepeat
    }

    static func decode(
        subtype: Int16,
        data   : Int
    ) -> VolumeMediaKey? {
        guard subtype == 8 else { return nil }

        let command: VolumeKeyCommand
        switch (data >> 16) & 0xFFFF {
            case 0 : command = .increase
            case 1 : command = .decrease
            case 7 : command = .toggleMute
            default: return nil
        }

        let state = (data >> 8) & 0xFF
        guard state == 0xA || state == 0xB else { return nil }

        return VolumeMediaKey(
            command  : command,
            isPressed: state == 0xA,
            isRepeat : data & 0xFF != 0
        )
    }
}
