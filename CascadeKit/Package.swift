// swift-tools-version: 6.2
//
//  Package.swift
//  CascadeKit
//

import PackageDescription

/// CascadeKit is the Dynamic Notch engine, extracted from the app shell so its
/// public surface is an enforced module boundary — the app (and, later,
/// decoupled widgets) can only reach what the package marks `public`.
///
/// The target opts into main-actor-by-default isolation to mirror the host app
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`): UI and coordination are
/// main-actor without ceremony, while the pure value/logic types are marked
/// `nonisolated` so the background-worker path can still use them.
let package = Package(
    name: "CascadeKit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15)  // Floor: Sequoia. Mutex and Atomic, @Observable, CADisplayLink, safeAreaInsets.
    ],
    products: [
        .executable(name: "cascade-addon", targets: ["CascadeAddonTool"]),
        .library(
            name   : "CascadePresentation",
            targets: ["CascadePresentation"]
        ),
        .library(
            name   : "CascadeAddonSDK",
            targets: ["CascadeAddonSDK"]
        ),
        .library(
            name: "CascadeContracts",
            targets: ["CascadeContracts"]
        ),
        .library(
            name: "CascadeRuntime",
            targets: ["CascadeRuntime"]
        ),
        .library(
            name: "CascadeKit",
            targets: ["CascadeKit"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "CascadeAddonTool",
            dependencies: ["CascadeContracts"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CascadeAddonToolTests",
            dependencies: ["CascadeAddonTool"],
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadePresentation",
            dependencies: ["CascadeContracts"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadeAddonSDK",
            dependencies: ["CascadeContracts", "CascadePresentation"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CascadePresentationTests",
            dependencies: ["CascadePresentation", "CascadeAddonSDK"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadeContracts",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CascadeContractsTests",
            dependencies: ["CascadeContracts"],
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadeRuntime",
            dependencies: ["CascadeContracts"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CascadeRuntimeTests",
            dependencies: ["CascadeRuntime", "CascadeContracts", "CascadeAddonSDK"],
            resources: [.process("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadePluginSDK",
            dependencies: ["CascadeContracts"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadePluginEngine",
            dependencies: ["CascadeContracts", "CascadePluginSDK"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CascadePluginEngineTests",
            dependencies: ["CascadePluginEngine", "CascadePluginSDK", "CascadeContracts"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "CascadeKit",
            dependencies: ["CascadeContracts", "CascadePresentation", "CascadePluginEngine"],
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name: "CascadeKitTests",
            dependencies: ["CascadeKit", "CascadeContracts", "CascadePresentation", "CascadeRuntime", "CascadePluginEngine"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
