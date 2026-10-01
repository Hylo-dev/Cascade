//
//  CrashServiceFixture.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

struct CrashServiceFixture {
    let runtime: AddonRuntime
    let governor: ResourceGovernor
    let clock: MutableRuntimeClock
    let adapter: RecordingRuntimeAdapter
    let provider: RuntimeConnection
    let providerID: AddonID
    let installedProvider: InstalledAddon

    init() async throws {
        let consumerAddon = try installedFixture("consumer", publisher: "TEST-ONLY.shared")
        let providerAddon = try installedFixture("focus", publisher: "TEST-ONLY.shared")
        installedProvider = providerAddon
        providerID = providerAddon.manifest.id
        clock = MutableRuntimeClock(instant: RuntimeInstant(
            wall     : Date(timeIntervalSince1970: 2_000_000_000),
            monotonic: .zero
        ))
        adapter = RecordingRuntimeAdapter()
        governor = ResourceGovernor()
        runtime = try await AddonRuntime.make(
            catalog    : [consumerAddon, providerAddon],
            environment: HostEnvironment(
                osVersion       : SemanticVersion(14, 0, 0),
                hostCapabilities: [:],
                applications    : [:],
                grants          : [consumerAddon.manifest.id: [], providerAddon.manifest.id: []],
                explicitBindings: []
            ),
            governor: governor,
            adapter : adapter,
            clock   : clock
        )
        let offer = try ProtocolOffer(major: 1, minimumMinor: 0, maximumMinor: 0, contentSchemas: [1])
        let launch = try await runtime.requestLaunch(owner: consumerAddon.manifest.id)
        let consumer = try await runtime.attach(launchID: launch, offer: offer)
        let permission = try await runtime.authorizeService(
            connection           : consumer,
            requirementID        : "com.example.focus.sessions",
            scope                : ServiceScope(featureID: "summary", operation: "read"),
            partition            : "TEST-ONLY.account",
            crossPublisherConsent: true
        )
        do {
            _ = try await runtime.acquireService(
                connection  : consumer,
                permissionID: permission,
                lifetime    : .seconds(3_600)
            )
            Issue.record("Expected the provider cold-start path.")
        } catch let error as AddonFailure {
            #expect(error.code == .dependencyUnavailable)
        }
        let providerStart = try #require(adapter.lastStart(owner: providerID))
        provider = try await runtime.attach(launchID: providerStart.launchID, offer: offer)
        let acquisition = try await runtime.acquireService(
            connection  : consumer,
            permissionID: permission,
            lifetime    : .seconds(3_600)
        )
        #expect(try await runtime.receiveSourceStartupCompletion(acquisition.sourceID, connection: provider))
    }

    func version() throws -> AddonVersionIdentity {
        try AddonVersionIdentity(
            verifiedIdentity: installedProvider.verifiedIdentity,
            version         : SemanticVersion(1, 0, 0)
        )
    }

    func advance(_ seconds: Int) {
        let current = clock.now()
        clock.set(RuntimeInstant(
            wall     : current.wall.addingTimeInterval(Double(seconds)),
            monotonic: current.monotonic + .seconds(seconds)
        ))
    }
}
