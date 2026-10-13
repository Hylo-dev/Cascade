//
//  AudioPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK

/// AudioPlugin is the system audio on the grid: the volume bar as a 1x2 widget and the mixer as
/// the detail a click on it opens. Both are one component each, drawn by the kernel from the
/// audio service the app offers, so the documents never change: the plugin answers a refresh
/// with the same two publications and has nothing to say to any other event. The level, the
/// output and every command live in the service, which costs nothing while the volume is still.
public final class AudioPlugin: PluginProvider {

    public static let id      = PluginID(rawValue: "com.cascade.audio")!
    public static let feature = "audio"

    public init() {}

    public func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        guard case .refresh = event else { return try PluginOutput() }

        return try PluginOutput(publications: [
            Self.publication(surface: .widget, component: "audio.volumeBar"),
            Self.publication(surface: .detail, component: "audio.mixer"),
        ])
    }

    private static func publication(
        surface  : PluginSurfaceKind,
        component: String
    ) throws -> PluginPublication {
        try PluginPublication(
            feature : feature,
            surface : surface,
            document: PluginDocument(
                root: Component(
                    id        : component,
                    version   : 1,
                    parameters: [:]
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        )
    }
}
