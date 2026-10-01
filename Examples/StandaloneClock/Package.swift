// swift-tools-version: 6.2
//
//  Package.swift
//  StandaloneClock
//

import Foundation
import PackageDescription

guard let sdkPath = ProcessInfo.processInfo.environment["CASCADE_SDK_PATH"],
      sdkPath.hasPrefix("/"),
      !sdkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
else { fatalError("Set CASCADE_SDK_PATH to an absolute public SDK package directory") }

let package = Package(
    name              : "StandaloneClock",
    platforms         : [.macOS(.v15)],
    products          : [.library(name: "StandaloneClockProvider", targets: ["StandaloneClockProvider"])],
    dependencies      : [.package(name: "PublicCascadeSDK", path: sdkPath)],
    targets           : [
        .target(
            name        : "StandaloneClockProvider",
            dependencies: [
                .product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"),
                .product(name: "CascadeContracts", package: "PublicCascadeSDK"),
            ]
        ),
        .testTarget(
            name        : "StandaloneClockProviderTests",
            dependencies: [
                "StandaloneClockProvider",
                .product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"),
                .product(name: "CascadeContracts", package: "PublicCascadeSDK"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
