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
    platforms: [
        .macOS(.v14) // Floor: Sonoma. @Observable, CADisplayLink, safeAreaInsets.
    ],
    products: [
        .library(
            name   : "CascadeKit",
            targets: ["CascadeKit"]
        ),
    ],
    targets: [
        .target(
            name         : "CascadeKit",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        ),
        .testTarget(
            name        : "CascadeKitTests",
            dependencies: ["CascadeKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
