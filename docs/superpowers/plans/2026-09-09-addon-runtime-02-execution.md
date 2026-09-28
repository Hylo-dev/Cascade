# Addon Execution and Resource Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run native addons on demand while keeping durable content, shared services and verifiable resource control.

**Architecture:** Runtime actor separate from the UI, authenticated asynchronous channels and processes controlled by the launcher proven in P0. Scheduler and broker own requests, leases, timelines and quotas; the provider does not own the notch's lifecycle.

**Tech Stack:** Foundation/XPC, ExtensionFoundation behind an availability adapter, Swift Concurrency/Dispatch, sandbox and Apple process tools.

**Spec:** [specification](../specs/2026-09-09-addon-runtime-design.md), [main plan](2026-09-09-addon-runtime.md); P0 prerequisites for the launcher and P1 for the values.

## Global Constraints

- macOS 14 as the app's minimum. The deployment target is not raised implicitly.
- Same SDK, isolation, grants and budgets for team and external addons.
- Cascade must be open; no orphaned child process accepted as success.
- The publication is owned by the host and does not coincide with the connection or a work lease.
- No synchronous proxy, process wait or unbounded decoding on the MainActor.
- Binding application quotas; native CPU/RAM monitored with an explicit detection interval.

## Task 02.1: Authenticated channel and on-demand launch

**Files:** create Sources/CascadeTransport/AddonConnection.swift, WireEnvelope.swift, PeerVerifier.swift, XPCAddonConnection.swift; Sources/CascadeRuntime/Processes/AddonProcessLaunching.swift, NativeAddonLauncher.swift, ProcessIdentity.swift, AddonProcessPool.swift; Sources/CascadeAddonSDK/AddonProviderEntrypoint.swift; Tests/CascadeRuntimeIntegrationTests/ProcessConnectionTests.swift, Fixtures/ProbeAddon/ under CascadeKit. Update Package.swift and the Xcode project only where signed executable bundles are needed.

**Interfaces:** use AddonManifest, AddonEvent, ProviderOutput and ConnectionGeneration from P1. Add ProcessIdentity (PID, verified birth instant/identifier, publisher, bundle ID, digest) and RunningAddon (identity, generation, connection). API:

```swift
protocol AddonProcessLaunching: Sendable {
    func start(_ addon: InstalledAddon) async throws -> RunningAddon
    func stop(_ running: RunningAddon, reason: StopReason) async throws
}
protocol AddonConnection: Sendable {
    func send(_ event: AddonEvent) async throws -> ProviderOutput
    func close() async
}
```

The pool keeps at most one native provider per active addon; it does not create a process per UI instance. "Pool" means controlled reuse of processes, not loading addons from different publishers into the same process. The identity is revalidated before operations on the process; a PID alone is not a sufficient handle.

- [ ] Write ProcessConnectionTests that launch a real fixture and verify compatible major, authorized peer, a new generation at every launch and rejection of a message from the previous generation. Also reproduce a provider that sends an envelope with a different owner.
- [ ] Implement the handshake: verified peer → matching manifest/digest → negotiated version → assigned grants → admitted messages. Verify the case of a valid signature but an unauthorized publisher, and that of a binary modified after the initial verification.
- [ ] Use the launcher chosen in P0 without introducing a second unproven mechanism. The addon process has a verified sandbox configuration, no unauthenticated network listener and no declared ability to create unmanaged subprocesses; this restriction must correspond to a real verification of the profile.
- [ ] Apply the P1 limits before deep application parsing: total envelope 512 KiB, documents 64 KiB and timelines 256 KiB, in addition to the per-field/count maximums. State queue: one pending element per instance; acks and credits for further sends. Command messages use a distinct queue, without silent dropping. A peer that ignores the credits is disconnected and stopped, also measuring the preliminary transport allocations.
- [ ] Implement stop and detection of the actual exit. Prove host exit, host crash, provider spin and identity mismatch with the P0 harness adapted to the production bundles. Do not accept "connection invalidated" as proof of the process's absence.
- [ ] Run ProcessConnectionTests and create scripts/test-addon-runtime.sh for the signed fixtures; record results and commit. A script must refuse to hit processes that do not belong to its own fixtures.

## Task 02.2: Scheduler, actions and publications independent of the process

**Files:** create Sources/CascadeRuntime/AddonRuntime.swift, Scheduling/AddonScheduler.swift, Scheduling/DeadlineQueue.swift, Actions/ActionDispatcher.swift, Actions/ActionJournal.swift; Tests/CascadeRuntimeTests/AddonSchedulerTests.swift, ActionDispatcherTests.swift, PublicationLifecycleTests.swift; Tests/CascadeRuntimeIntegrationTests/ProviderExitTests.swift under CascadeKit.

**Interfaces:** `AddonRuntime.dispatch(_ request: ActionRequest) async -> ActionOutcome`; `refresh(_ id: PublicationID) async throws`; `disable(_ id: AddonID) async`; `stop() async`. Dependencies in init: PublicationStore, AddonProcessLaunching, ResolutionPlanner through a Resolution snapshot, ServiceBroker from 02.3 and an injectable clock. The tests use a FakeClock defined in the file TestClock.swift, with `now: Date` and `advance(by: TimeInterval)`; production distinguishes persistent Date and ContinuousClock for durations.

- [ ] Write the central test with a fake provider only in the test target:

```text
given a timer publication expiring in 60 seconds
when its provider completes and exits normally
then the publication remains and no process is required
when an authorized pause action arrives
then exactly one provider starts, a new generation is used, and the result revises the same publication
when a reply from the old generation arrives
then it changes nothing
```

Repeat the sequence with a real process fixture in ProviderExitTests. The unit test alone does not prove the absent-process requirement.

- [ ] Implement separate states for process, job and publication. The work ends with bounded output; the publication does not retain provider instances. An expected exit preserves valid state/actions; a crash marks the information stale according to the policy; disable revokes actions and removes content/timelines, future ones included.
- [ ] Implement a single deadline queue, rearmed on the changed minimum; no per-addon timers and no renewal heartbeat. On reactivation/sleep-wake re-evaluate expired events, drop outdated notices and do not restart finished sessions. Persistent civil time and the monotonic clock must have separate clock-jump tests.
- [ ] Admit one heavy job per addon and two global ones initially; user actions precede discretionary refreshes, with a bounded queue and maximum wait to avoid starvation. Schedule the short reuse window with the same central queue and the policy measured in P0; zero resident processes without demand outside the window. Do not freeze processes to simulate CPU turns.
- [ ] Separate ack, completed and outcomeUnknown. ActionJournal keeps at least request ID and state within explicit limits (initially 128 requests/10 minutes per addon), counting the memory. Non-idempotent command with the connection lost after sending: outcomeUnknown, no automatic retry. Repeatable command: retry only within the declared window and with the same ID. The timeout case must revoke the late result, without pretending that the external effect was cancelled.
- [ ] Prove full queues, 100 coalesced revisions, four pending commands, a deadline expired before launch, two concurrent actions on the same revision, stop during checkpoint and no reactivation on disable. For endActivity the removal stays immediate even with the view open.
- [ ] Run AddonSchedulerTests, ActionDispatcherTests, PublicationLifecycleTests and ProviderExitTests; update docs/addons/lifecycle.md with delivery and persistence guarantees; commit.

## Task 02.3: Leases, broker and live dependencies

**Files:** create Sources/CascadeRuntime/Services/ServiceBroker.swift, ServiceRegistry.swift, ServiceBindingStore.swift, LeaseStore.swift, PermissionStore.swift; Sources/CascadeAddonSDK/Services/AddonServiceClient.swift, Storage/AddonStorageClient.swift; Tests/CascadeRuntimeTests/ServiceBrokerTests.swift, PermissionRevocationTests.swift under CascadeKit.

**Interfaces:** `ServiceBroker.acquire(requirementID: String, consumer: AddonID, scope: ServiceScope) async throws -> Lease`; `release(_ leaseID: UUID, consumer: AddonID) async`; `call(_ request: ServiceRequest) async throws -> ServiceResponse`. ServiceScope enum for ownStorage, selectedFiles, networkHosts and namedService; ServiceRequest contains leaseID, consumer authenticated from the envelope, operationID and bounded input. Do not accept the consumer's identity directly from the payload.

- [ ] Write ServiceBrokerTests with a CountingSource service defined in the test target: it counts start/stop and delivers events through AsyncStream with bufferingNewest(1). Two compatible acquisitions must call start once; the first release does not stop the source, the second does.
- [ ] Implement a sharing key comprising version, account, scope and confidentiality constraints. Two accounts or incompatible grants do not share cache/data. The service's cost counts only once in the total, while the requested work stays attributable to the consumers.
- [ ] Separate the interest subscription retained by the host from the connection's access token. The interest has owner, feature/session, grant, expiry and quota; it can survive the provider's normal exit and wake it on an admitted event. On the new connection a new token is created, without reusing leases from previous generations. Disable, expiry and revocation remove both. Prove an event with the provider absent, and no source after revocation of the last interest.
- [ ] Route a call to a third-party service as a ServiceInvocation and correlate InvocationCompletion.service to the client's ServiceResponse. Events keep only the last useful state per subscription; commands keep explicit outcomes and deadlines. When A waits for B, the broker must not hold execution permits that prevent B from starting: transfer the work admission during the wait, keeping memory/processes accounted for, or reject early with resourceDenied. Prove A→B→C and a chain beyond the process capacity: no deadlock or unbounded growth.
- [ ] Apply the P1 resolution to real changes of installation, enablement, running app and permissions. Re-evaluate the reverse closure of the dependents, without polling. A lost service blocks only the dependent features; no selection of another provider mid-session without a new authorized binding.
- [ ] Implement leases revocable by owner, scope, generation and deadline. A disabled provider or consumer loses its handles; another feature without that dependency continues. Reject permission lending, a handle used by another addon and access to data after revocation even if the action was already queued.
- [ ] Run ServiceBrokerTests and PermissionRevocationTests; add integration with two signed addon fixtures when available. The broker must not offer a shell, a generic NSWorkspace proxy or private engine APIs. Document public services and scopes in docs/addons/services.md; commit.

## Task 02.4: Quotas, supervision and quarantine

**Files:** create Sources/CascadeRuntime/Resources/ResourcePolicy.swift, ResourceGovernor.swift, ProcessMetricsReader.swift, AddonHealthStore.swift; Tests/CascadeRuntimeTests/ResourceGovernorTests.swift, QuarantineTests.swift; Tests/CascadeRuntimeIntegrationTests/ResourceAbuseTests.swift under CascadeKit; create scripts/test-addon-resources.sh.

**Interfaces:** ResourcePolicy is versioned host configuration; `ResourceGovernor.admit(_ request: ResourceRequest, owner: AddonID) throws -> Reservation`, `release(_ reservationID: UUID)`, `observe(_ metrics: ProcessMetrics, identity: ProcessIdentity) -> GovernorDecision`. ResourceRequest enum publication, asset, job, command, storage; Reservation contains ID, owner and amount. ProcessMetrics contains CPU user+system delta, footprint, timestamp and identity; GovernorDecision enum keep, reduce, stop, quarantine.

- [ ] Write ResourceGovernorTests with the same request and an identical budget for bundled and external origin: same result. Verify 4 activities/addon and 16 global, notices 8, 16 instances/addon, message limits, state 8 MiB global, images 8 MiB/addon and 32 global, three providers at most and global memory admission 256 MiB. The quotas are simultaneous maximums, not sums reserved per installation.
- [ ] Implement reservation before host-controlled allocation/work, and release on error, timeout and cancellation. CPU and footprint of native code are instead observed with the adapter verified in P0; no promise of an instantaneous RAM limit or a simulated metric if the OS denies the read.
- [ ] A single supervisor samples the active processes, initially at most 1 Hz, and disarms itself when there are no processes. Count its cost. Apply the specification's candidates: event-driven shared credit addon100ms with refill5ms CPU/s, kept across jobs and provider restarts; provider footprint target 64 MiB/observed threshold 96; remote scene total per addon target 128/threshold 192. The continuous audio/UI profile does not inherit these numbers: it must pass 04.3 before public enablement.
- [ ] For three moderate violations in five minutes, quarantine the version. For the stop/flooding threshold, stop the process immediately through the launcher; record detection and exit time. Retry after a crash at 1/5/30 s only with demand still valid, then quarantine; use DeadlineQueue, not additional per-addon timers.
- [ ] Prove CPU loop, memory expansion bounded by the harness, IPC flooding, quotas circumvented with many sessions, a shared service used to offload cost, and an absent metric. The harness interrupts only the test processes and has a global deadline; no test must be able to deliberately exhaust the machine.
- [ ] Run ResourceGovernorTests, QuarantineTests and `/bin/zsh scripts/test-addon-resources.sh`. Save stop latency/overshoot and supervisor costs, in addition to the simple pass/fail; commit.

## Task 02.5: Assets, checkpoints and bounded persistence

**Files:** create Sources/CascadeRuntime/Storage/AddonStateStore.swift, StateMigration.swift, AssetStore.swift, AssetDecoder.swift; Tests/CascadeRuntimeTests/AddonStateStoreTests.swift, AssetStoreTests.swift, StateMigrationTests.swift under CascadeKit. Modify AddonStorageClient and the 01.4 bridge to consume authorized handles.

**Interfaces:** `AddonStateStore.read(owner: AddonID) async throws -> Data?`; `write(_ data: Data, schemaVersion: Int, owner: AddonID) async throws`; `AssetStore.importAsset(_ data: Data, owner: AddonID) async throws -> AssetHandle`; AssetHandle contains ID, owner, dimensions and revision of the asset, never an arbitrary path. The asset's revision is not ConnectionGeneration: the host's references survive the provider's expected exit; only the tokens with which the provider uses them are tied to the connection. Migration receives a copy of the previous state and produces a new validated file before the atomic replacement.

- [ ] Write tests that interrupt a write between staging and commit: the old state must remain readable. Verify disk quotas of 10 MiB state and 20 MiB cache/addon, 100 MiB global initially; cache deletion separate from removal of the user's data.
- [ ] Implement separate directories per verified owner, rejection of incoming path traversal/symlinks and no access to the source app's data by convention. Write on significant events, not per frame or every second. Time-bounded checkpoint; stop does not wait forever for a provider.
- [ ] Decode images off the MainActor with bounded concurrency, at most 1 MiB compressed and 1 megapixel; reject malformed metadata/images and account for the decoded buffer before publishing it. If P0/decoder analysis requires isolating the decoder, use a controlled native worker, not a new unsupervised pipeline.
- [ ] Keep the assets referenced by valid publications after the provider's normal exit; release them when the last reference disappears. Owner revocation prevents use of the remaining handles. The cache of the same asset is not shared across incompatible private scopes.
- [ ] Prove restart with a still valid publication, an expired one, a corrupted file and a future schema. Do not replay commands or notices from persistence; do not automatically renew the maximum duration of an activity.
- [ ] Run AddonStateStoreTests, AssetStoreTests and StateMigrationTests; run all the P2 suites and record the P2 report with build/relaunch if the app was touched; commit.
