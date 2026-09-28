//
//  SystemVolumeControlling.swift
//  Cascade
//



/// SystemVolumeControlling hides synchronous CoreAudio access behind a worker
/// queue. A failed command must return false so the original key reaches macOS.
nonisolated protocol SystemVolumeControlling: AnyObject {
    var supportsVolume: Bool { get }
    func snapshot() -> SystemVolumeSnapshot?
    func perform(
        _ command: VolumeKeyCommand,
        fineStep : Bool
    ) -> Bool
}
