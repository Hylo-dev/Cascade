//
//  VolumeKeyRouter.swift
//  Cascade
//

import Foundation

/// VolumeKeyRouter couples key suppression to successful device writes.
/// Native fallback silences nearby observation because CoreAudio does not
/// identify a change's source. The monotonic deadline is checked only on events;
/// no timer wakes the process to expire it.
nonisolated struct VolumeKeyRouter {

    private var nativeFallbackDeadline: TimeInterval = 0
    private var handledKeys           : Set<VolumeKeyCommand> = []
    private var forwardedKeys         : Set<VolumeKeyCommand> = []

    var allowsObservedNotice: Bool {
        allowsObservedNotice(at: ProcessInfo.processInfo.systemUptime)
    }

    func allowsObservedNotice(at timestamp: TimeInterval) -> Bool {
        timestamp >= nativeFallbackDeadline
    }

    mutating func route(
        _ key     : VolumeMediaKey,
        eligible  : Bool,
        fineStep  : Bool,
        controller: any SystemVolumeControlling,
        timestamp : TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard key.isPressed else {
            if forwardedKeys.remove(key.command) != nil {
                nativeFallbackDeadline = timestamp + 0.6
                handledKeys.remove(key.command)
                return false
            }

            return handledKeys.remove(key.command) != nil
        }
        guard !forwardedKeys.contains(key.command) else {
            nativeFallbackDeadline = timestamp + 0.6
            return false
        }

        if key.command == .toggleMute, key.isRepeat {
            return handledKeys.contains(.toggleMute)
        }

        guard eligible, controller.perform(key.command, fineStep: fineStep) else {
            nativeFallbackDeadline = timestamp + 0.6
            forwardedKeys.insert(key.command)
            handledKeys.remove(key.command)
            return false
        }

        nativeFallbackDeadline = 0
        handledKeys.insert(key.command)
        return true
    }
}
