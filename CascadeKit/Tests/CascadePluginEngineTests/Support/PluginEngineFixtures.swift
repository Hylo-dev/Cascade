//
//  PluginEngineFixtures.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

@testable import CascadePluginEngine

/// PluginEngineFixtures builds what the engine tests share: a clock with one widget and nothing
/// to listen to, and a music player with an activity, a widget, the now-playing source, an
/// Automation permission, the scrubber component and three controls.
enum PluginEngineFixtures {

    static let clockID = PluginID(rawValue: "com.cascade.clock")!
    static let musicID = PluginID(rawValue: "com.cascade.music")!
    static let radioID = PluginID(rawValue: "com.cascade.radio")!
    static let start   = PluginInstant(
        wall     : Date(timeIntervalSince1970: 1_800_000_000),
        monotonic: .seconds(1_000)
    )

    static func clock() throws -> PluginManifest {
        try manifest(
            clockID,
            entryPoint: "ClockPlugin",
            features  : [
                PluginFeature(
                    id      : "time",
                    surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 2, rows: 1)]))
                ),
            ]
        )
    }

    static func music(_ id: PluginID = musicID) throws -> PluginManifest {
        try manifest(
            id,
            entryPoint: "MusicPlugin",
            features  : [
                PluginFeature(
                    id         : "now-playing",
                    surfaces   : PluginSurfaces(
                        activity: PluginPlainSurface(),
                        widget  : PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 2, rows: 1)])
                    ),
                    sources    : ["media.nowPlaying"],
                    components : [PluginComponentReference(id: "media.scrubber", version: 1)],
                    permissions: ["automation.music"],
                    actions    : ["next", "togglePlayback", "setVolume"]
                ),
            ]
        )
    }

    static func manifest(
        _ id      : PluginID,
        entryPoint: String,
        features  : [PluginFeature]
    ) throws -> PluginManifest {
        try PluginManifest(
            manifestVersion: 2,
            id             : id,
            version        : "1.0.0",
            compatibility  : PluginCompatibility(
                macOS          : "15.0",
                cascadeProtocol: PluginProtocolVersion(major: 2, minimumMinor: 0)
            ),
            execution      : PluginExecution(entryPoint: entryPoint),
            sourceApp      : nil,
            requires       : [],
            features       : features,
            resources      : PluginResources(profile: .eventDriven)
        )
    }

    static func text(_ value: String) throws -> PluginDocument {
        try PluginDocument(root: PluginNode(.text(value)))
    }

    /// controls is a now-playing face whose button, toggle, slider and title carry explicit ids,
    /// so their identities are `#next:button`, `#play:toggle`, `#volume:slider`, `#title:text`.
    static func controls() throws -> PluginDocument {
        try PluginDocument(
            root: PluginNode(
                .hStack(alignment: .center, spacing: nil),
                children: [
                    PluginNode(.button(action: "next"), id: "next"),
                    PluginNode(.toggle(isOn: true, action: "togglePlayback"), id: "play"),
                    PluginNode(.slider(value: 0.5, minimum: 0, maximum: 1, step: nil, action: "setVolume"), id: "volume"),
                    PluginNode(.text("Song"), id: "title"),
                ]
            )
        )
    }

    static func nowPlaying(_ title: String) throws -> PluginSourceEvent {
        try PluginSourceEvent(source: "media.nowPlaying", fields: ["title": .string(title)])
    }

    static func power(charging: Bool) throws -> PluginSourceEvent {
        try PluginSourceEvent(source: "power", fields: ["charging": .bool(charging)])
    }

    static func kernel(
        sources: Set<String> = ["media.nowPlaying"],
        policy : any PluginHealthPolicy = StandardHealthPolicy()
    ) -> PluginKernel {
        PluginKernel(
            capabilities: PluginHostCapabilities(sources: sources, services: [], components: ["media.scrubber"]),
            policy      : policy
        )
    }

    static func output(
        _ feature : String,
        _ surface : PluginSurfaceKind,
        _ document: PluginDocument?,
        staleAfter: Double? = nil
    ) throws -> PluginOutput {
        try PluginOutput(publications: [publication(feature, surface, document, staleAfter: staleAfter)])
    }

    /// publication builds one publication, giving an activity the shape the contract demands: its
    /// document becomes the first of four regions, and the attributes ride along.
    static func publication(
        _ feature : String,
        _ surface : PluginSurfaceKind,
        _ document: PluginDocument?,
        staleAfter: Double? = nil
    ) throws -> PluginPublication {
        guard surface == .activity, let document else {
            return try PluginPublication(feature: feature, surface: surface, document: document, staleAfter: staleAfter)
        }

        let regions = PluginNode(.regions, children: [document.root] + (1..<4).map { PluginNode(.text("region \($0)")) })

        return try PluginPublication(
            feature   : feature,
            surface   : surface,
            document  : PluginDocument(root: regions),
            staleAfter: staleAfter,
            activity  : PluginActivityAttributes(startedAt: start.wall, relevance: 0.5, accessibilityLabel: "Activity")
        )
    }

    static func result(
        _ output: PluginOutput?,
        cpuTime : Duration = .milliseconds(1)
    ) -> PluginExecutionResult {
        PluginExecutionResult(output: output, cpuTime: cpuTime)
    }
}
