// swift-tools-version: 6.2
//
//  Package.swift
//  ServiceConsumer
//

import Foundation
import PackageDescription
guard let sdkPath = ProcessInfo.processInfo.environment["CASCADE_SDK_PATH"], sdkPath.hasPrefix("/"), !sdkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fatalError("Set CASCADE_SDK_PATH to an absolute public SDK package directory") }
let package = Package(name: "ServiceConsumer", platforms: [.macOS(.v14)],
 products: ["FocusSessionsExampleContract", "FocusSessionsExampleProvider", "ServiceConsumerProvider"].map { .library(name: $0, targets: [$0]) },
 dependencies: [.package(name: "PublicCascadeSDK", path: sdkPath)],
 targets: [
 .target(name: "FocusSessionsExampleContract", dependencies: [.product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"), .product(name: "CascadeContracts", package: "PublicCascadeSDK")]),
 .target(name: "FocusSessionsExampleProvider", dependencies: ["FocusSessionsExampleContract"] + [.product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"), .product(name: "CascadeContracts", package: "PublicCascadeSDK")]),
 .target(name: "ServiceConsumerProvider", dependencies: ["FocusSessionsExampleContract"] + [.product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"), .product(name: "CascadeContracts", package: "PublicCascadeSDK")]),
 .testTarget(name: "ServiceConsumerExampleTests", dependencies: ["FocusSessionsExampleContract", "FocusSessionsExampleProvider", "ServiceConsumerProvider"] + [.product(name: "CascadeAddonSDK", package: "PublicCascadeSDK"), .product(name: "CascadeContracts", package: "PublicCascadeSDK")], path: ".", exclude: ["Sources", "Package.swift", "README.md"], sources: ["Tests/ServiceConsumerExampleTests"], resources: [.copy("Manifests")])
 ], swiftLanguageModes: [.v6])
