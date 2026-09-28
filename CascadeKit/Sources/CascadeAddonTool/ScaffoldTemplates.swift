//
//  ScaffoldTemplates.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

enum ScaffoldTemplates {
    static func files(name: String, id: AddonID, sdkPath: String) throws -> [ScaffoldFile] {
        let target = name + "Addon"
        let provider = name + "Provider"
        let manifest: [String: Any] = [
            "manifestVersion": 1, "id": id.rawValue, "version": "0.1.0",
            "compatibility": ["macOS": ">=14.0", "cascadeProtocol": ["major": 1, "minimumMinor": 0]],
            "execution": ["owner": "cascade", "activation": "onDemand", "entryPoint": "provider"],
            "bundledLibraries": [], "REQUIRES": [], "PROVIDES": [], "features": [], "permissions": [],
            "resources": ["profile": "eventDriven", "requestedMemoryMiB": 16, "maximumConcurrentWork": 1, "background": "none"],
        ]
        var manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        _ = try AddonManifest.decode(manifestData)
        manifestData.append(10)
        let package = #"""
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(
            name: \#(swiftLiteral(target)),
            platforms: [.macOS(.v14)],
            products: [.library(name: \#(swiftLiteral(target)), targets: [\#(swiftLiteral(target))])],
            dependencies: [.package(name: "CascadeSDK", path: \#(swiftLiteral(sdkPath)))],
            targets: [
                .target(
                    name: \#(swiftLiteral(target)),
                    dependencies: [
                        .product(name: "CascadeAddonSDK", package: "CascadeSDK"),
                        .product(name: "CascadeContracts", package: "CascadeSDK"),
                    ]
                ),
                .testTarget(
                    name: \#(swiftLiteral(target + "Tests")),
                    dependencies: [
                        .target(name: \#(swiftLiteral(target))),
                        .product(name: "CascadeAddonSDK", package: "CascadeSDK"),
                        .product(name: "CascadeContracts", package: "CascadeSDK"),
                    ]
                ),
            ],
            swiftLanguageModes: [.v6]
        )
        """#
        let source = #"""
        import CascadeAddonSDK
        import CascadeContracts
        import Foundation

        /// Development source example. The host supplies publication identity.
        /// Transport, reconnect and revision restoration require a qualified runtime.
        public actor \#(provider): AddonProvider {
            private let addonID: AddonID
            private var revision: UInt64 = 0

            public init() throws {
                guard let id = AddonID(rawValue: \#(swiftLiteral(id.rawValue))) else {
                    throw AddonFailure(code: .invalidPayload, reason: "Invalid configured addon identity")
                }
                addonID = id
            }

            public func handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput {
                switch event {
                case .refresh(let publicationID):
                    try publicationID.validateOwner(addonID)
                    guard revision < UInt64.max else {
                        throw AddonFailure(code: .resourceDenied, reason: "Publication revision exhausted")
                    }
                    let document = try ContentDocument(
                        schemaVersion: 1,
                        root: .text(\#(swiftLiteral(name + " is ready"))),
                        accessibilityLabel: \#(swiftLiteral(name + " is ready")),
                        privacy: .publicContent,
                        assets: []
                    )
                    let content = try PresentationSet(
                        widget: document, compactLeading: nil, compactTrailing: nil, minimal: nil, expanded: nil
                    )
                    let publication = try Publication(
                        id: publicationID, revision: revision + 1, kind: .widget,
                        content: content, timeline: nil,
                        expiresAt: Date().addingTimeInterval(60), stalePolicy: .remove
                    )
                    let output = try ProviderOutput(
                        schemaVersion: 1, publications: [publication], operations: [], completion: nil, checkpoint: nil
                    )
                    revision += 1
                    return output
                case .stop:
                    return try ProviderOutput(
                        schemaVersion: 1, publications: [], operations: [], completion: nil, checkpoint: nil
                    )
                case .scheduled, .action, .serviceChanged, .serviceRequest:
                    throw AddonFailure(code: .invalidPayload, reason: "Event is unsupported by this source example")
                }
            }
        }
        """#
        let tests = #"""
        import CascadeAddonSDK
        import CascadeContracts
        import Foundation
        import Testing
        import \#(target)

        @Suite struct \#(provider)Tests {
            private func publicationID(owner: String = \#(swiftLiteral(id.rawValue))) throws -> PublicationID {
                PublicationID(addonID: try #require(AddonID(rawValue: owner)), instanceID: UUID(), sessionID: UUID())
            }

            private func context() throws -> AddonContext {
                try AddonContext(services: UnusedClients(), storage: UnusedClients(), generation: ConnectionGeneration(), grants: [])
            }

            @Test func refreshPublishesValidatedWidgetWithHostIdentityAndFiniteExpiry() async throws {
                let provider = try \#(provider)()
                let id = try publicationID()
                let before = Date()
                let output = try await provider.handle(.refresh(id), context: context())
                let after = Date()
                #expect(output.schemaVersion == 1 && output.publications.count == 1)
                let publication = try #require(output.publications.first)
                #expect(publication.id == id && publication.revision == 1 && publication.kind == .widget)
                #expect(publication.expiresAt.timeIntervalSince1970.isFinite)
                #expect(publication.expiresAt >= before.addingTimeInterval(60))
                #expect(publication.expiresAt <= after.addingTimeInterval(60))
                #expect(publication.stalePolicy == .remove && publication.timeline == nil)
                let document = try #require(publication.content?.widget)
                #expect(document.schemaVersion == 1 && document.root.kind == .text)
                #expect(document.root.text == \#(swiftLiteral(name + " is ready")))
                #expect(document.accessibilityLabel == \#(swiftLiteral(name + " is ready")))
                #expect(document.assets.isEmpty && document.privacy == .publicContent)
                #expect(output.operations.isEmpty && output.completion == nil && output.checkpoint == nil)
                try output.validateContext(authenticatedAddonID: id.addonID, expectedCompletion: nil, previousRevisions: [:])
                #expect(try ProviderOutput.decode(JSONEncoder().encode(output)) == output)
            }

            @Test func refreshAdvancesRevisionAcrossHostPublicationIDs() async throws {
                let provider = try \#(provider)()
                let firstID = try publicationID(), secondID = try publicationID()
                let first = try await provider.handle(.refresh(firstID), context: context())
                let second = try await provider.handle(.refresh(secondID), context: context())
                #expect(first.publications.first?.revision == 1)
                #expect(second.publications.first?.revision == 2 && second.publications.first?.id == secondID)
                let third = try await provider.handle(.refresh(firstID), context: context())
                try third.validateContext(authenticatedAddonID: firstID.addonID, expectedCompletion: nil,
                                          previousRevisions: [firstID: 1])
                #expect(third.publications.first?.revision == 3)
            }

            @Test func refusesForeignOwnerWithoutConsumingRevision() async throws {
                let provider = try \#(provider)()
                let configured = try publicationID()
                let foreignOwner = configured.addonID.rawValue == "org.scaffold.foreign" ? "org.scaffold.other" : "org.scaffold.foreign"
                let foreign = try publicationID(owner: foreignOwner)
                do {
                    _ = try await provider.handle(.refresh(foreign), context: context())
                    Issue.record("Foreign publication owner was accepted")
                } catch let failure as AddonFailure {
                    #expect(failure.code == .invalidPayload)
                }
                let output = try await provider.handle(.refresh(publicationID()), context: context())
                #expect(output.publications.first?.revision == 1)
            }

            @Test func stopReturnsEmptyOutputWithoutInventingCompletion() async throws {
                let provider = try \#(provider)()
                let id = try publicationID()
                _ = try await provider.handle(.refresh(id), context: context())
                let stopped = try await provider.handle(.stop(.hostStopping), context: context())
                #expect(stopped.schemaVersion == 1 && stopped.publications.isEmpty && stopped.operations.isEmpty)
                #expect(stopped.completion == nil && stopped.checkpoint == nil)
                let next = try await provider.handle(.refresh(id), context: context())
                #expect(next.publications.first?.revision == 2)
            }

            @Test func unsupportedEventsFailWithoutClaimingSuccess() async throws {
                let provider = try \#(provider)()
                let id = try publicationID()
                let action = try ActionRequest(schemaVersion: 1, requestID: UUID(), publicationID: id,
                                               actionID: "example", input: Data(), deadline: Date(), observedRevision: 0)
                let invocation = try ServiceInvocation(schemaVersion: 1, requestID: UUID(), contractID: "example.service",
                                                       operation: "read", payload: Data(), deadline: Date())
                let token = try Grant(
                    id: UUID(), owner: id.addonID, serviceID: "example.service",
                    scope: ServiceScope(featureID: "example", operation: "read"), expiresAt: Date(),
                    generation: ConnectionGeneration(),
                    cost: AddonResourceRequest(profile: .eventDriven, requestedMemoryMiB: 0, maximumConcurrentWork: 1, background: .none)
                )
                let response = try ServiceResponse(schemaVersion: 1, contractID: "example.service", operation: "read", payload: Data())
                let change = try ServiceEvent(subscriptionID: UUID(), token: token, response: response)
                for event in [AddonEvent.scheduled(eventID: "example"), .action(action), .serviceChanged(change), .serviceRequest(invocation)] {
                    do {
                        _ = try await provider.handle(event, context: context())
                        Issue.record("Unsupported event returned success")
                    } catch let failure as AddonFailure {
                        #expect(failure.code == .invalidPayload)
                    }
                }
                let output = try await provider.handle(.refresh(id), context: context())
                #expect(output.publications.first?.revision == 1)
            }
        }

        /// No broker or runtime is involved in these provider unit tests.
        /// Any accidental capability use fails instead of returning fake success.
        private struct UnusedClients: AddonServiceClient, AddonStorageClient {
            private var unavailable: AddonFailure {
                AddonFailure(code: .dependencyUnavailable, reason: "This example must not use broker capabilities")
            }
            func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse { throw unavailable }
            func subscribe(requirementID: String, grant: Grant) async throws -> UUID { throw unavailable }
            func unsubscribe(subscriptionID: UUID) async throws { throw unavailable }
            func read(key: String) async throws -> Data? { throw unavailable }
            func write(_ data: Data, key: String) async throws { throw unavailable }
            func remove(key: String) async throws { throw unavailable }
        }
        """#
        let readme = """
        # \(name) addon source example

        This source-only SwiftPM library implements the public AddonProvider protocol.
        It links only CascadeAddonSDK and CascadeContracts from your explicit local SDK path.
        Manifest.json is a validated development contract, not an installable package.
        Its provider entryPoint describes the intended contract; no executable is generated.

        Run `swift test` here to exercise the provider with unavailable capability clients.
        Refresh publishes a schema 1 widget under the host-supplied identity with a 60-second expiry.
        Foreign owners and unsupported events fail. Stop returns empty output.
        The actor maintains a single bounded revision counter for its in-memory lifetime.

        Native bootstrap and transport qualification, reconnect and revision restoration,
        developer-assigned signing identity, entitlements and packaging remain separate work.
        No signing credentials, launcher, installation, build or test run was performed by init.
        Do not treat these unit tests or manifest validation as runtime admission proof.
        """
        return [
            ScaffoldFile(path: "Manifest.json", data: manifestData),
            textFile("Package.swift", package),
            textFile("Sources/\(target)/\(provider).swift", source),
            textFile("Tests/\(target)Tests/\(provider)Tests.swift", tests),
            textFile("README.md", readme),
            textFile(".gitignore", ".build/\n.swiftpm/\n.DS_Store"),
        ]
    }

    /// swiftLiteral escapes scalars rather than using JSON escaping: Swift rejects
    /// JSON's \/ and \uXXXX, and a literal backslash must not introduce Swift
    /// interpolation.
    private static func swiftLiteral(_ value: String) -> String {
        var literal = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: literal += "\\\""
            case 0x5C: literal += "\\\\"
            case 0x0A: literal += "\\n"
            case 0x0D: literal += "\\r"
            case 0x09: literal += "\\t"
            case 0..<0x20, 0x7F...0x9F, 0x2028, 0x2029:
                literal += "\\u{\(String(scalar.value, radix: 16))}"
            default: literal.unicodeScalars.append(scalar)
            }
        }
        return literal + "\""
    }

    private static func textFile(_ path: String, _ text: String) -> ScaffoldFile {
        ScaffoldFile(path: path, data: Data((text + "\n").utf8))
    }
}
