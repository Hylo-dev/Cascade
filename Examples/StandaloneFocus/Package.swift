// swift-tools-version: 6.2
//
//  Package.swift
//  StandaloneFocus
//

import Foundation
import PackageDescription

// Explicit local public SDK development reference, not a released remote SDK.
guard let sdkPath = ProcessInfo.processInfo.environment["CASCADE_SDK_PATH"],
    sdkPath.hasPrefix("/"), !sdkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
else { fatalError("Set CASCADE_SDK_PATH to an absolute public SDK package directory") }

let package = Package(
    name: "StandaloneFocus",
    platforms: [.macOS(.v14)],
    products: [.library(name: "StandaloneFocusProvider", targets: ["StandaloneFocusProvider"])],
    dependencies: [.package(name: "PublicCascadeSDK", path: sdkPath)],
    targets: [
        .target(
            name: "StandaloneFocusProvider",
            dependencies: [
                .product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"),
                .product(name: "CascadeContracts", package: "PublicCascadeSDK"),
            ]
        ),
        .testTarget(
            name: "StandaloneFocusProviderTests",
            dependencies: [
                "StandaloneFocusProvider",
                .product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"),
                .product(name: "CascadeContracts", package: "PublicCascadeSDK"),
            ],
            resources: [.copy("Manifest.json")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
