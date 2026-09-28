# Addon Contracts and SwiftUI SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make manifests, content, dependencies and Swift APIs independent of the provider's execution, with verifiable limits.

**Architecture:** Serializable values in Contracts, declarative composition in Presentation and a shared SwiftUI renderer. The resolver and content retention are host logic separate from the UI.

**Tech Stack:** Swift tools 6.2, Foundation, SwiftUI, Swift Testing; no external library.

**Spec:** [specification](../specs/2026-09-09-addon-runtime-design.md), [main plan](2026-09-09-addon-runtime.md).

## Execution status

The four P1 blocks are implemented; automated tests and reviews completed for the implemented code; 230 package tests pass with --no-parallel, as recorded in the [P1 report](../verification/2026-09-09-addon-runtime-P1.md). VoiceOver, the system accessibility settings, energy behavior on the desktop and the link to the P2/P3 scheduler remain to be qualified. The unit tests and the preview are not a proof of the remote SwiftUI scene. No commit of the earlier work is included.

## Global Constraints

- macOS 14 as the app's minimum. The deployment target is not raised implicitly.
- Same SDK and controls for all future team widgets and for external addons.
- No automatic serialization of AnyView or closures; no dependency on the names of concrete widgets in the renderer.
- No provider code on the MainActor or in the host's animation callback.
- All new wire types are Codable and Sendable with explicit schema/versions; the domain types do not inherit the global MainActor isolation.

## Task 01.1: Package, identity, schema and messages

**Files:** modify CascadeKit/Package.swift; create Sources/CascadeContracts/AddonIdentity.swift, AddonManifest.swift, AddonRequirement.swift, AddonPermission.swift, AddonResourceRequest.swift, Publication.swift, ProviderMessage.swift, AddonFailure.swift under CascadeKit; create Tests/CascadeContractsTests/ManifestTests.swift, MessageTests.swift, FixtureData.swift, Fixtures/focus.json, Fixtures/requires-cycle-a.json, Fixtures/requires-cycle-b.json, Fixtures/incompatible.json.

**Interfaces:** define all the values of the "Common interface vocabulary" table of the main plan, keeping the JSON shapes of the specification. Pure APIs:

```swift
public struct AddonID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init?(rawValue: String)
}
public struct AddonManifest: Codable, Sendable {
    public static func decode(_ data: Data) throws -> AddonManifest
    public func validate() throws
}
public struct ProviderOutput: Codable, Sendable {
    public let publications: [Publication]
    public let operations: [OperationRequest]
    public let completion: InvocationCompletion?
    public let checkpoint: Data?
}
```

OperationRequest is an enum with the cases requestService(requirementID, scope), schedule(deadline, eventID), releaseLease(leaseID), endPublication(PublicationID); identifiers as validated strings, scope as a closed object of allowed fields, no dictionary of arbitrary Foundation objects. Publication includes content or timeline, never both; finite dates and UInt64 revisions not recycled within the same session. InvocationCompletion associates requestID with an action result or a service response: publishing a snapshot does not prove the command's completion. AddonFailure contains the explicit cases of the specification and readable reasons.

- [x] Add the Contracts target and its tests to the package with processed fixture resources, keeping the current CascadeKit product. Limit the target's dependencies to Foundation; add concurrency checks on the new targets without migrating the language mode globally.
- [x] Copy focus.json from the specification's example and add a fixture loader in the test target:

```swift
func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

@Test func rejectsOversizedManifestBeforeDecode() {
    #expect(throws: (any Error).self) {
        try AddonManifest.decode(Data(repeating: 32, count: 65_537))
    }
}
```

- [x] Implement the 64 KiB manifest limit before the JSONDecoder, rejection of an unknown major, invalid IDs, malformed SemVer ranges, negative/NaN resources and unknown required capabilities. Unknown optional fields may be ignored only if they do not change security semantics; unknown discriminants are rejected.
- [x] Define distinct limits for content and envelope: 64 KiB per document, 256 KiB per timeline, 512 KiB total per envelope; at most 16 publications and 16 operations per response, action input 4 KiB, checkpoint 64 KiB. Both the per-field maximums and the total one apply. Assets use a separate bounded transfer and do not raise these maximums. Test an action result with a wrong requestID, a service response to the wrong request and a list that exceeds the limit while staying under the maximum bytes.
- [x] Define PresentationSet as a map of only the widget, compactLeading, compactTrailing, minimal, expanded representations. Publication.content contains a set; each ScheduledEntry contains one. All representations share PublicationID and revision; no duplicated activity per side or expansion. The complete current set respects 64 KiB overall, and a timeline 256 KiB overall. Validate the required representations for widget/activity/notice and the absence of expanded in notices.
- [x] Add round-trip tests of the messages, duplicates of feature/service/action, `sourceApp.required == false`, requirements per feature and the impossibility of using bundleID as an authenticated identity. Define the conflict fixtures by changing ID/REQUIRES and PROVIDES when necessary to represent a real cycle with respect to focus; do not use fixtures resolved over the network.
- [x] Run ManifestTests and MessageTests; review name compatibility between documents and code, update the public schema in docs/addons/manifest.schema.json and the error registry in docs/addons/protocol.md. The delivery of the files is recorded in the P1 report; no commit of the earlier work.

## Task 01.2: Swift builder and renderer of the same descriptions

**Files:** create Sources/CascadeContracts/ContentDocument.swift, ContentNode.swift, ActionDescriptor.swift; Sources/CascadePresentation/CascadeContent.swift, CascadeContentBuilder.swift, CascadeComponents.swift, ContentRenderer.swift, ContentPreview.swift; Sources/CascadeAddonSDK/AddonProvider.swift, AddonContext.swift; Tests/CascadePresentationTests/ContentArchiveTests.swift, ContentValidationTests.swift under CascadeKit. Update Package.swift with the public products Contracts, Presentation and AddonSDK.

**Interfaces:** ContentDocument has schemaVersion Int, root ContentNode, privacy enum, accessibilityLabel String and assetIDs [String]. `encode() throws -> Data`, `static decode(_:) throws -> ContentDocument`, `validate() throws`. ContentNode is a validated struct with a Kind discriminant and throwing factories for text(String), symbol(String), image(assetID), row([ContentNode]), column([ContentNode]), progress(value: Double), countdown(until: Date), clock(format: ClockFormat), action(ActionDescriptor). ClockFormat is a closed enum for hours/minutes/seconds, respecting locale and accessibility.

```swift
public protocol CascadeContent {
    var contentNode: ContentNode { get }
}

public protocol AddonProvider: Sendable {
    func handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput
}
```

AddonEvent enum: refresh(PublicationID), scheduled(eventID: String), action(ActionRequest), serviceChanged(ServiceEvent), serviceRequest(ServiceInvocation), stop(StopReason). ServiceEvent contains subscriptionID, the new connection's valid token and a validated service payload. ServiceInvocation contains requestID, service/operation, input and deadline; the broker authenticates the caller before sending. AddonContext exposes only service/storage clients, the current generation and grants; no NotchEngine, NSApp, host factory or link to the catalog.

- [x] Write the archiving test of a document built only from values:

```swift
@Test func keepsCountdownWithoutProviderObjects() throws {
    let document = try ContentDocument(
        schemaVersion: 1,
        root: try .countdown(until: Date(timeIntervalSince1970: 2_000_000_000)),
        privacy: .publicContent,
        accessibilityLabel: "Time remaining",
        assetIDs: []
    )
    let decoded = try ContentDocument.decode(document.encode())
    #expect(decoded == document)
}
```

- [x] Implement the types as Equatable values in addition to Codable/Sendable where relevant; the wire privacy uses publicContent/sensitive and is adapted to the existing privacy only at the engine boundary.
- [x] Implement CascadeRow, CascadeColumn, CascadeText, CascadeSymbol, CascadeImage, CascadeProgress, CascadeCountdown, CascadeClock and CascadeButton as CascadeContent components. The result builder converts components into nodes. CascadeButton accepts an ActionDescriptor (ID and payload), not a closure executable by the host. Document that these are not transparent substitutes for every SwiftUI.View.
- [x] Implement ContentRenderer as a SwiftUI.View with a ContentDocument input and a host callback for ActionDescriptor. The preview uses exactly that renderer, with an explicit preview dispatcher. No JSON built by hand by the developer and no introspection of an arbitrary view.
- [x] Verify 64 KiB wire, depth 8, 128 nodes, 4 KiB strings, finite/clamped progress values, allowed symbols/URLs, asset count and unique actions. Try images and buttons without an accessible label, an unknown schema and depth 9; they must be rejected before the views are built.
- [ ] Run ContentArchiveTests and ContentValidationTests; render the components with reduced motion/transparency and VoiceOver. Add docs/addons/content.md with the allowed components and the difference between a durable description and a remote scene; commit.

## Task 01.3: Deterministic resolver for addons and features

**Files:** create Sources/CascadeRuntime/Resolution/ResolutionPlanner.swift, ResolutionModels.swift, SemanticVersionRange.swift; Tests/CascadeRuntimeTests/ResolutionPlannerTests.swift, ResolutionFixtures.swift under CascadeKit; update Package.swift with Runtime and tests. The Runtime target depends on Contracts and, from P2, Transport; not on CascadeKit or on the Features.

**Interfaces:** `ResolutionPlanner.resolve(catalog: [InstalledAddon], environment: HostEnvironment, prior: [ServiceBinding]) throws -> Resolution`. InstalledAddon contains manifest, verified signer identity, digest and enabled state. HostEnvironment contains OS version, host capabilities, installed/running apps and grants, all values. Resolution contains admitted addons, blocked features with a reason, launch order, bindings and reverse dependents. ServiceBinding identifies requirementID, consumer, provider, verified providerIdentity, contractVersion, digest and optional featureID. The nil value indicates the root scope; two features can have different bindings, while all the conjoined conditions in the same scope must satisfy a single binding.

- [x] Prepare JSON fixtures with three addons in the test target: Focus provides sessions 1.0; Consumer requires >=1 <2; OptionalConsumer requires the source app only for openInSourceApp. The fixture parser produces the InstalledAddon values with a signature marked test-only; no fake is imported into production.
- [x] Verify the app's absence: localTimer admitted and openInSourceApp blocked. Add cycle A→B→A, major conflict, two equivalent providers, disabling, old valid binding and missing permission. Each case must have deterministic output for the same input, even after permutation of the catalog.
- [x] Implement the algorithm, off the MainActor:

```text
validate bounded catalog
evaluate root requirements and feature requirements separately
filter providers by enabled state, identity restriction, grants and version
choose explicit binding, then valid prior binding, then host, then stable candidate order
reject cycles and closures over 32 addons / 128 edges / depth 8
topologically order accepted dependencies and build reverse edges
return a plan with blocked reasons; perform no install, launch or permission request
```

- [x] Apply a monotonic budget of 256 steps to the anyOf alternatives and to the provider attempts, without giving steps back during rollback; abort with resolutionTooComplex if the number of explorations exceeds the policy's maximum. Add that error to the 01.1 registry. No unbounded combinatorial search and no provider chosen because it answered first.
- [x] Run ResolutionPlannerTests and generative tests with a recorded seed for order/cycles. Save docs/addons/requires.md with installed versus open, service versions versus package, and limits. External reproductions and rollback, already admitted graphs and conjoined constraints per scope were also reviewed.

## Task 01.4: Host-owned content and notch adaptation

**Files:** create Sources/CascadeRuntime/Publications/PublicationStore.swift, PublicationTimeline.swift; Sources/CascadeKit/Core/AddonPresentation/AddonPresentationBridge.swift, SnapshotWidget.swift, SnapshotActivity.swift, SnapshotNotice.swift; Tests/CascadeRuntimeTests/PublicationStoreTests.swift and Tests/CascadeKitTests/AddonPresentationTests.swift under CascadeKit. Modify Core/Widgets/WidgetContext.swift, WidgetHost.swift and Core/Activities/LiveActivityHost.swift only for revocation/identity and the necessary bridges.

**Interfaces:** `actor PublicationStore` exposes `accept(_ publication: Publication, owner: AddonID) throws`, `snapshot(at: Date) -> [Publication]`, `remove(owner: AddonID)`, `expire(at: Date)`. None of these methods retains AddonProvider. `@MainActor AddonPresentationBridge.apply(_ publications: [Publication])` receives only values and uses the engine; it does not import Runtime. The app will connect the two in P3.

- [x] Write PublicationStoreTests to accept a publication, destroy the test producer, read the same publication; lower revision rejected, other owner rejected, finite expiry, removal of all future entries on disable.
- [x] Implement snapshots/timelines with ordered dates, 32 entries and 256 KiB per instance; initial budget for retained host state 8 MiB global, separate from 32 MiB of assets and from the on-disk storage. Do not preallocate 8 MiB for each addon. Countdown/clock are time rules, not lists of ticks.
- [x] Adapt documents to NotchWidget/NotchLiveActivity/NotchTransientNotice only inside the bridge. Runtime namespacing before the engine. Preserve anchored 8-hour sessions, notices 10 s/backlog 8, privacy before rendering, priorities and the behavior of the two activities. Do not replace the existing arbitration with the provider's priorities.
- [x] Make WidgetContext revocable and verify that a retained copy does not invalidate after suspend. Invalidate only the affected instance/revision in the bridge, without recreating the whole page for an identical value. Add tests to AddonPresentationTests for the release of the hidden clock view from the caches (the energy measurement remains to be qualified), a visible snapshot without a provider and sensitive content redacted in accessibility too.
- [x] Handle assets through references: the bridge accepts only assets already validated by the P2 service, with a placeholder when one is missing. No path reading or synchronous decoding in the factories; decoder and quota will be introduced in 02.5.
- [x] Run PublicationStoreTests, AddonPresentationTests, LiveActivityHostTests and NotchActivityLifetimeTests; run the prescribed build and relaunch if the integrated app/engine code was modified. Record the P1 outcomes and reintegrate only the relevant files with a conflict check. The commit is deferred because the checkout contains earlier uncommitted work.
