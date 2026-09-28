//
//  FakeVolumeController.swift
//  Cascade
//

#if VOLUME_MONITOR_TESTS
import Foundation
import AppKit

nonisolated final class FakeVolumeController: SystemVolumeControlling {
    var succeeds = true
    var commandCount = 0
    var supportsVolume: Bool { true }
    func snapshot() -> SystemVolumeSnapshot? { nil }
    func perform(_ command: VolumeKeyCommand, fineStep: Bool) -> Bool {
        commandCount += 1
        return succeeds
    }
}

#endif
