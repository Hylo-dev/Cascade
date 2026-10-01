//
//  VolumePlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// VolumePlugin is Cascade's volume notice as a plugin. The kernel's volume source, beside the key
/// tap, decides which changes deserve a notice and numbers them; the plugin shows one whenever the
/// number moves. Cascade's menu previews it through the `preview` action, which leaves the
/// baseline alone.
public final class VolumePlugin: PluginProvider {

    public static let id      = PluginID(rawValue: "com.cascade.volume")!
    public static let feature = "volume"
    public static let preview = "preview"

    private let reducer = Mutex(VolumeAnnouncementReducer())

    public init() {}

    public func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginVolumeState(source), reducer.withLock({ $0.receive(state) }) else { return try PluginOutput() }

                return try PluginOutput(publications: [VolumeNotice.publication(for: state)])

            case .action(let action) where action.action == Self.preview:
                return try PluginOutput(publications: [VolumeNotice.publication(for: PluginVolumeState(percentage: 65, isMuted: false, announcement: 0))])

            default:
                return try PluginOutput()
        }
    }
}
