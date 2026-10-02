//
//  SoundPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// SoundPlugin is the volume widget: the output level as the kernel's bar and a percentage, or a
/// struck speaker while muted. It reads the `volume` source the volume alerts read too, and keeps
/// only what it shows, the level and whether it is muted: the announcement counter is the alerts'
/// business, so a state that moves only the counter publishes nothing. The source's baseline
/// knows no level yet, and the widget waits for one rather than draw a level it does not know. A
/// refresh, which comes at start and after a restart, gets the last level again; the plugin never
/// asks for a wake. PluginHost runs it on one thread, so the lock is never contended.
final class SoundPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.sound")!
    static let feature = "sound"

    private let last = Mutex<PluginVolumeState?>(nil)

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginVolumeState(source), state.percentage != nil else { return try PluginOutput() }

                let shown   = PluginVolumeState(percentage: state.percentage, isMuted: state.isMuted, announcement: 0)
                let changed = last.withLock { last in
                    defer { last = shown }
                    return last != shown
                }
                guard changed else { return try PluginOutput() }

                return try PluginOutput(publications: [SoundFace.publication(for: shown)])

            case .refresh:
                guard let shown = last.withLock({ $0 }) else { return try PluginOutput() }

                return try PluginOutput(publications: [SoundFace.publication(for: shown)])

            default:
                return try PluginOutput()
        }
    }
}
