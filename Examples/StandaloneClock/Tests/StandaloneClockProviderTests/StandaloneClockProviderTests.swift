import CascadeAddonSDK
import CascadeContracts
import Foundation
import StandaloneClockProvider
import Testing

private enum UnexpectedCapability: Error { case call }

private struct FailingServices: AddonServiceClient {
    func invoke(_ invocation: ServiceInvocation, grant: Grant) async throws -> ServiceResponse {
        throw UnexpectedCapability.call
    }
    func subscribe(requirementID: String, grant: Grant) async throws -> UUID { throw UnexpectedCapability.call }
    func unsubscribe(subscriptionID: UUID) async throws { throw UnexpectedCapability.call }
}

private struct FailingStorage: AddonStorageClient {
    func read(key: String) async throws -> Data? { throw UnexpectedCapability.call }
    func write(_ data: Data, key: String) async throws { throw UnexpectedCapability.call }
    func remove(key: String) async throws { throw UnexpectedCapability.call }
}

private struct FailingAssets: AddonAssetClient {
    func importAsset(_ data: Data, publicationID: PublicationID) async throws -> AssetHandle {
        throw UnexpectedCapability.call
    }
    func shareAsset(_ asset: AssetHandle, to publicationID: PublicationID) async throws -> AssetHandle {
        throw UnexpectedCapability.call
    }
    func releaseAsset(_ asset: AssetHandle) async throws { throw UnexpectedCapability.call }
}

private struct Fixture {
    let owner = AddonID(rawValue: "org.cascade.examples.clock")!
    let assignment: PublicationID
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    init() {
        assignment = PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID())
    }

    func context() throws -> AddonContext {
        try AddonContext(
            services: FailingServices(),
            storage: FailingStorage(),
            assets: FailingAssets(),
            generation: ConnectionGeneration(),
            grants: []
        )
    }
}

private func failureCode(_ operation: () async throws -> ProviderOutput) async -> AddonFailure.Code? {
    do {
        _ = try await operation()
        return nil
    } catch {
        return (error as? AddonFailure)?.code
    }
}

@Test func manifestAndRefreshUseOnlyHostAssignedDeclarativeClockState() async throws {
    let manifestURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Manifest.json")
    let manifest = try AddonManifest.decode(Data(contentsOf: manifestURL))
    #expect(manifest.id.rawValue == "org.cascade.examples.clock")
    #expect(manifest.execution.owner == .cascade)
    #expect(manifest.execution.entryPoint == "StandaloneClockProvider")
    #expect(manifest.bundledLibraries.isEmpty && manifest.requires.isEmpty && manifest.provides.isEmpty)
    #expect(manifest.permissions.isEmpty && manifest.features.count == 1)
    #expect(manifest.features[0].id == "clock" && manifest.features[0].actions == [])
    #expect(manifest.resources.background == .none)

    let fixture = Fixture()
    let provider = try StandaloneClockProvider(
        expectedOwner: fixture.owner,
        publicationID: fixture.assignment,
        clock: { fixture.now }
    )
    let first = try await provider.handle(.refresh(fixture.assignment), context: fixture.context())
    let publication = try #require(first.publications.first)
    #expect(first.publications.count == 1 && first.operations.isEmpty)
    #expect(first.completion == nil && first.checkpoint == nil)
    #expect(publication.id == fixture.assignment && publication.revision == 1)
    #expect(publication.kind == .widget && publication.timeline == nil)
    #expect(publication.expiresAt.timeIntervalSince1970.isFinite && publication.expiresAt > fixture.now)
    #expect(publication.content?.widget?.root.kind == .clock)
    #expect(publication.content?.widget?.root.clockFormat == .hourMinute)
    #expect(publication.content?.widget?.assets.isEmpty == true)
    try first.validateContext(
        authenticatedAddonID: fixture.owner,
        expectedCompletion: nil,
        previousRevisions: [:]
    )

    let second = try await provider.handle(.refresh(fixture.assignment), context: fixture.context())
    #expect(second.publications.first?.revision == 2)
    try second.validateContext(
        authenticatedAddonID: fixture.owner,
        expectedCompletion: nil,
        previousRevisions: [fixture.assignment: 1]
    )

    let recreated = try StandaloneClockProvider(
        expectedOwner: fixture.owner,
        publicationID: fixture.assignment,
        previousRevision: 2,
        clock: { fixture.now }
    )
    let resumed = try await recreated.handle(.refresh(fixture.assignment), context: fixture.context())
    #expect(resumed.publications.first?.revision == 3)
    try resumed.validateContext(
        authenticatedAddonID: fixture.owner,
        expectedCompletion: nil,
        previousRevisions: [fixture.assignment: 2]
    )
}

@Test func unsupportedAndInvalidEventsFailWithoutUsingCapabilities() async throws {
    let fixture = Fixture()
    let foreignOwner = AddonID(rawValue: "org.cascade.examples.other")!
    #expect(throws: (any Error).self) {
        _ = try StandaloneClockProvider(expectedOwner: foreignOwner, publicationID: fixture.assignment)
    }

    let provider = try StandaloneClockProvider(
        expectedOwner: fixture.owner,
        publicationID: fixture.assignment,
        clock: { fixture.now }
    )
    let other = PublicationID(
        addonID: fixture.owner,
        instanceID: UUID(),
        sessionID: fixture.assignment.sessionID
    )
    #expect(await failureCode { try await provider.handle(.refresh(other), context: fixture.context()) } == .invalidPayload)

    let request = try ActionRequest(
        schemaVersion: 1,
        requestID: UUID(),
        publicationID: fixture.assignment,
        actionID: "unknown",
        input: Data(),
        deadline: fixture.now.addingTimeInterval(30),
        observedRevision: 0
    )
    let rejected = try await provider.handle(.action(request), context: fixture.context())
    #expect(rejected.publications.isEmpty && rejected.operations.isEmpty && rejected.checkpoint == nil)
    guard case .action(request.requestID, .rejected(let reason)) = rejected.completion else {
        Issue.record("Unsupported action must return its correlated rejection")
        return
    }
    #expect(reason.code == .invalidPayload)
    try rejected.validateContext(
        authenticatedAddonID: fixture.owner,
        expectedCompletion: .action(requestID: request.requestID),
        previousRevisions: [:]
    )

    let scheduled = try await provider.handle(.scheduled(eventID: "clock.refresh"), context: fixture.context())
    #expect(scheduled.publications.isEmpty && scheduled.operations.isEmpty && scheduled.completion == nil)
    let service = try ServiceInvocation(
        schemaVersion: 1,
        requestID: UUID(),
        contractID: "unsupported.service",
        operation: "read",
        payload: Data(),
        deadline: fixture.now.addingTimeInterval(30)
    )
    #expect(await failureCode { try await provider.handle(.serviceRequest(service), context: fixture.context()) } == .missingRequirement)
    let stopped = try await provider.handle(.stop(.idle), context: fixture.context())
    #expect(stopped.publications.isEmpty && stopped.operations.isEmpty)
    #expect(await failureCode {
        try await provider.handle(.refresh(fixture.assignment), context: fixture.context())
    } == .sessionRevoked)
}

@Test func invalidCivilTimeAndExhaustedRevisionFailClosed() async throws {
    let fixture = Fixture()
    let nonfinite = try StandaloneClockProvider(
        expectedOwner: fixture.owner,
        publicationID: fixture.assignment,
        clock: { Date(timeIntervalSince1970: .infinity) }
    )
    #expect(await failureCode {
        try await nonfinite.handle(.refresh(fixture.assignment), context: fixture.context())
    } == .invalidPayload)

    let exhausted = try StandaloneClockProvider(
        expectedOwner: fixture.owner,
        publicationID: fixture.assignment,
        previousRevision: .max,
        clock: { fixture.now }
    )
    #expect(await failureCode {
        try await exhausted.handle(.refresh(fixture.assignment), context: fixture.context())
    } == .resourceDenied)
}
