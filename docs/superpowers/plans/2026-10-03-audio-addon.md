# Audio Addon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver a broker-authorized Audio addon with persistent per-app gain/mute/routing, transparent native processing and an internal notch mixer.

**Architecture:** A public `AddonProvider` publishes bounded controls and calls a typed service through `AddonContext.services`. The shared native system service owns HAL discovery, persistent intent and serialized recovery; a C++ kernel owns sample processing. Common SDK options/control primitives render in Cascade without loading provider code.

**Tech Stack:** Swift 6.2, CascadeAddonSDK/Contracts/Runtime/Presentation, Core Audio taps, AudioToolbox, AppKit/SwiftUI, C++20; no new third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-03-audio-mixer-design.md` (approved).

## Global Constraints

- Branch `cava/audio`; macOS 15.0 floor; runtime-check every newer/private capability. The local beta probe is not macOS 15 qualification.
- Use the same SDK, manifest, REQUIRES, permissions, broker, revision checks, process isolation and resource policy as external addons. No legacy PluginProvider or Audio-specific host registration.
- No main-thread HAL/disk work; no ARC, allocation, locks/spins, logging, HAL reads or dispatch in the sample callback. Immutable snapshots cross the service boundary.
- Gain in [0, 1]; finite 5 ms ramp once per frame across channels; Float32/Float64; no limiter, EQ, noise gate, boost or simultaneous multiple outputs.
- Recovery: immediate, then 100/300/1000 ms one-shot retries; failed state by 3 seconds. At most two live-plus-retiring contexts per app; no replacement-thread growth after a hung call.
- One shared 1 Hz watchdog only for expected controlled rendering; two stale checks trigger bounded recovery. Zero periodic mixer work without eligible sessions.
- Thresholds: <1% incremental CPU for one stereo 48 kHz app, <3% for ten over 60 s; ≤16/48 MiB incremental private resident memory; callback p99.9 <10% buffer interval, no missed deadlines.
- Added latency: wired ≤one measured device buffer +2 ms; Bluetooth ≤20 ms against the same bypass profile. First controlled buffer uses restored gain/mute.
- English code/comments/docs, native Cascade visual language and accessibility. Preserve the underlying open page; options use a shared display-bound lease.
- Existing native launch hold stays intact. Production activation is conditional on its separately reviewed qualification; offline tests and standalone probes do not qualify it.
- Public/private backend claims require measured output, isolation and wake evidence. Symbol presence/readback alone proves neither audio quality nor per-app control.

## Review Focus

1. Wake retains the same process/device IDs but invalidates rendering: rebuild and seed persisted state anyway (Tasks 3–4).
2. Full-scale right-only or near-silent audio: preserve both channels with no limiter or amplitude-triggered gating (Task 2).
3. A blocking stop outlives disable and a late callback: retain context safely, bound replacements and keep UI responsive (Tasks 3–5).
4. A PID is reused, helpers change or two apps share a display name: do not apply another app's intent (Tasks 1, 4).
5. A mixer action races revision/grant revocation or display removal: reject it, restore the original page and release only presentation resources (Tasks 5–7).

## Verified starting point and file responsibilities

The real SDK entry point is `CascadeAddonSDK/Core/Protocols/AddonProvider.swift`,
with `AddonContext.services` and `AddonServiceClient.invoke/subscribe/unsubscribe`.
`Examples/ServiceConsumer` demonstrates canonical grant selection and bounded
responses. `ServiceBroker.beginInvocation` reserves work before dispatch and
validates operation/scope. `AddonRuntime` is currently an **internal** pure actor;
do not pretend the app already has a production public runtime assembly.

`ContentNode`/`ContentRenderer` currently support actions, rows, columns and
progress but no value-input slider, picker or horizontal scroll primitive.
`OperationRequest` has no options operation. Implement those shared capabilities
before Audio consumes them. The native startup hold is independently verified
as exit 78; host assembly/launcher qualification is a production prerequisite.

New code is grouped by responsibility: contracts under `Models/Audio`, typed
client under SDK `Core/Audio`, native implementation in private
`CascadeAudioSystem`, kernel in `CascadeAudioRealtime`, broker bridge under
runtime `Core/Audio`, and provider package under `Addons/Audio`. The provider
imports only public SDK products. It does not import the native service/kernel.

Use `/private/tmp/cascade-audio-swift-build` as the SwiftPM scratch directory.
The test command below means:
`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /usr/bin/xcrun swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-audio-swift-build --no-parallel --filter <suite>`.
Run each new test red before implementation, then green; capture exact failures.
Only rerun wider suites when changed interfaces require them.

---

### Task 1: Bounded audio service contract and public SDK client

**Files:** Create `CascadeKit/Sources/CascadeContracts/Models/Audio/AudioMixerModels.swift`, `AudioMixerCommand.swift`, `AudioMixerContract.swift`; `CascadeKit/Sources/CascadeAddonSDK/Core/Audio/AudioMixerClient.swift`. Test `CascadeKit/Tests/CascadeContractsTests/AudioMixerContractTests.swift`, `CascadeKit/Tests/CascadeRuntimeTests/AudioMixerClientTests.swift`.

**Interfaces:** Produce immutable Codable/Sendable `AudioApplicationIdentity`, `AudioIntent`, `AudioBindingToken`, `AudioApplicationSnapshot`, `AudioDeviceSnapshot`, `AudioMixerSnapshot` and `AudioMixerCommand`. `AudioIntent` has `gain: Double`, `isMuted: Bool`, `preferredOutputUID: String?` (nil follows system). Identity uses verified bundle/signing evidence, or an explicit unidentified identity; never a display name or persisted PID. `AudioBindingToken` is an opaque UUID for an ephemeral app/device binding; each row exposes its current token. Snapshot carries `generation: UInt64` (service incarnation), requested/applied/recovering/failed state and hardware capabilities. Commands cover app intent/retry/native return, master volume/mute, output/system-sound/input selection and supported input gain/mute; each carries service generation and target binding token when acting on a live binding. Tokens for unaffected apps stay valid when another row changes. `AudioMixerContract.serviceID = "cascade.system.audio"`, operations `"control"`/`"state"`; permission `"audio.control"`. `AudioMixerClient.send(_ command: AudioMixerCommand) async throws -> AudioMixerSnapshot`, plus `decodeUpdate(_ event: ServiceEvent) throws -> AudioMixerSnapshot`.

- [ ] Write `rejectsNonfiniteOutOfRangeAndOversizedPayload`: NaN/∞/negative/>1 gain rejected; command >4096 bytes, response >65536 bytes and >64 app/device records rejected before retention; unknown fields rejected. Write `pidAndDisplayNameCannotSelectAnotherIdentity` and `requestedQuarterGainSurvivesAppliedUnitySnapshot` (desired gain remains 0.25).
- [ ] Write `clientRejectsForeignExpiredAndAmbiguousGrants`: foreign owner/generation, duplicate usable grants, wrong response contract/operation and late response all fail without accepting a snapshot.
- [ ] Run `AudioMixerContractTests` and `AudioMixerClientTests`; expect missing contract/client or assertions failing.
- [ ] Implement the values/strict decoding and client using `ServiceInvocation`, `Grant` and existing response validation. Cap deadline at min(now+3 seconds, grant expiry); avoid a universal selector/PID command.
- [ ] Run both suites; expect all cases pass. Commit only the contract/client/tests: `feat: define bounded addon audio service contract`.

### Task 2: Audited native gain kernel

**Files:** Create `CascadeKit/Sources/CascadeAudioRealtime/include/AudioRenderKernel.h`, `CascadeKit/Sources/CascadeAudioRealtime/AudioRenderKernel.cpp`; `Prototypes/AudioSignalCheck/AudioSignalCheck.cpp`, `Prototypes/AudioSignalCheck/run-check.py`. Modify `CascadeKit/Package.swift` for the private C++ target. The standalone check is its test harness.

**Interfaces:** C API: opaque `AudioRenderContext`; `AudioRenderCreate(AudioRenderFormat format, double gain, bool muted) -> AudioRenderContext *` (nullable on invalid format/allocation), `AudioRenderSetCommand(AudioRenderContext *, double gain, bool muted) -> bool`, `AudioRenderProcess(AudioRenderContext *, const AudioBufferList *, AudioBufferList *, uint32_t frames) -> AudioRenderResult`, `AudioRenderCallbackSequence(const AudioRenderContext *) -> uint64_t`, `AudioRenderDestroy(AudioRenderContext *)`. `AudioRenderFormat` fixes PCM precision, rate, planar/interleaved channels and maximum buffer bytes; generation/lifetime belongs to the caller. Destruction requires proven quiescence, never a timeout.

- [ ] Write `firstBufferUsesSeededQuarterGain`, `rightOnlyFullScaleIsLinear`, `nearSilenceNeverTriggersFade`, `planarChannelsAdvanceOneRampPerFrame`, `invalidDimensionsNeverReadPastBounds` and `zeroGainWritesZeroWithoutReadingSignal`. Assert native scalar multiplication against a long-double oracle ≤1 ULP at 44.1/48/96/192 kHz, Float32/64, mono/stereo, planar/interleaved; impulse, ±1 peaks, zero and near-zero. A 5 ms transition completes after ceil(rate*0.005) frames equally on every channel; untouched unity bypass preserves samples.
- [ ] Run the standalone harness; expect compilation/link failure for the missing kernel.
- [ ] Implement preallocated validated context and coherent lock-free commands. A UInt64 stores gain bits with the unused sign bit encoding mute; generation/revision is serialized outside the callback. Verify lock-free atomics at construction; reject unsupported representation. No fast-math/nonlinear processing; document buffer ownership/aliasing and initialization.
- [ ] Run `python3 Prototypes/AudioSignalCheck/run-check.py` in optimized and ASan/UBSan modes; expect all signal/bounds checks pass. Instrument allocator/lock calls separately; do not use sanitizer timing for performance claims. Commit `feat: add transparent native audio gain kernel`.

### Task 3: Persistent intent and deterministic recovery policy

**Files:** Create `CascadeKit/Sources/CascadeAudioSystem/AudioIntentStore.swift`, `AudioLifecyclePolicy.swift`; `CascadeKit/Tests/CascadeAudioSystemTests/AudioLifecyclePolicyTests.swift`, `AudioIntentStoreTests.swift`. Modify `CascadeKit/Package.swift` for private native target/tests depending on Contracts/Realtime.

**Interfaces:** `AudioIntentStoring.load() async throws -> [AudioApplicationIdentity: AudioIntent]`, `save(_ intents: [AudioApplicationIdentity: AudioIntent], revision: UInt64) async throws`; injected storage uses the existing authorized addon storage coordinator, not main-thread files. Pure `AudioLifecyclePolicy.reduce(_ state: AudioLifecycleState, event: AudioLifecycleEvent, now: Duration) -> AudioLifecycleReduction` returns state plus typed effects: prepare/start/stop/retry/fail; clocks and backend are injected. State includes generation, desired revision, retry episode, first-callback readiness, expected render progress and retiring-context count.

- [ ] Write `wakeRebuildsWithIdenticalIDs`, `staleCompletionCannotReplaceLatestIntent`, `identicalEventsCannotRefillRetryBudget`, `silentProgressIsHealthy`, `idleOwnsNoWatchdog`, `twoStaleActiveChecksRecover`, `stopTimeoutRetainsContextAndCapsAtTwo`, `blockedHALCannotBlockSupervisorFailure`. Assert retries at 0/100/300/1000 ms; failed state at 3 s; paused/dormant/starting states do not trigger steady-stall recovery.
- [ ] Write `failedOrReorderedPersistenceNeverSavesSyntheticUnity`: intent 0.25 survives restart and corrupt/unavailable storage exposes failure without overwriting it; obsolete saves cannot replace a newer committed revision.
- [ ] Run both new suites; expect missing types/assertion failures.
- [ ] Implement reducer, bounded durable storage journal and latest-revision checks. Persistence and lifecycle work run off MainActor; final applied state is distinct from persisted intent. A new wake/topology/explicit retry/healthy progress opens a fresh episode; duplicate notification does not.
- [ ] Run suites; expect all cases pass. Commit `feat: preserve audio intent through bounded recovery`.

### Task 4: Native tap backend, event discovery and cleanup

**Files:** Create `CascadeKit/Sources/CascadeAudioSystem/AudioHardwareAccess.swift`, `CoreAudioProcessInventory.swift`, `CoreAudioTapSession.swift`, `AudioMixerEngine.swift`; tests `CascadeKit/Tests/CascadeAudioSystemTests/AudioMixerEngineTests.swift`, `CoreAudioTapSessionTests.swift`. Reuse/extract operations from `Cascade/Core/Volume/CoreAudioSystemVolume.swift` and `Cascade/Core/Audio/OutputDeviceAccess.swift` only after graph-tracing their callers; do not create two master-device controllers.

**Interfaces:** Inject `AudioHardwareAccess` for bounded snapshot/listener/prepare/start/stop operations and real second fake implementation. `AudioMixerEngine.send(_ command: AudioMixerCommand) async throws -> AudioMixerSnapshot`, `accept(_ event: AudioHardwareEvent) async`, `revoke(owner: AddonID) async`; snapshots are emitted only on actual change. Prepared sessions own kernel, tap, private aggregate and IOProc by immutable generation; output UID/actual format is qualified before start. Single supervisor queue is independent of HAL execution.

- [ ] Write `seedIsInstalledBeforeStart`, `wakeSameIDsRecreatesBinding`, `reusedPIDDoesNotInheritForeignGain`, `helperReplacementUsesVerifiedIdentity`, `preferredUIDReturnsWithoutLosingIntent`, `duplicateStopNeverFreesLiveCallback`, `permissionAndUnsupportedFormatAreVisible`, `closingPresentationKeepsControl`, `disableEndsControlWithoutDeletingIntent`. Fake a blocked stop and a late callback: no premature reclamation or unbounded threads/contexts.
- [ ] Run new suites; expect missing implementation.
- [ ] Implement listener-before-baseline discovery, workspace sleep/wake/process events and HAL process/device/running/format/service-restart notifications. Cache identity/icons outside realtime. Match tap stream format; never force shared rate/buffer. Seed context before AudioDeviceStart and prove first-render progress before applied state. Bound retry/supervisor resources; add only the approved shared eligible-session watchdog.
- [ ] Run suites and standalone API probe. Add a controlled tap qualification mode comparing `muted`/`mutedWhenTapped`, actual PCM layouts, native bypass handoff, route disconnect and stalled reader; obtain the real system capture grant when first needed. Record uncontrolled native gaps rather than claiming absolute silence after invalidation.
- [ ] Commit `feat: add event-driven Core Audio mixer backend` after automated checks; physical effect qualification remains Task 8.

### Task 5: Shared audio service authority, leases and resource admission

**Files:** Create `CascadeKit/Sources/CascadeRuntime/Core/Audio/AudioServiceHost.swift`, `AudioControlLease.swift`; tests `CascadeKit/Tests/CascadeRuntimeTests/AudioServiceHostTests.swift`. Modify `Core/Services/ServiceBroker.swift`, `Core/Runtime/AddonRuntime.swift` and `Core/Resources/ServiceCPUAttributionLedger.swift` only where shared system-adapter execution/accounting needs support. Add the private AudioSystem dependency to Runtime; SDK has none.

**Interfaces:** Internal `AudioServiceHost.perform(_ work: ServiceWork, authority: AudioServiceAuthority) async throws -> ServiceResponse`; `revoke(_ authority: AudioServiceAuthority) async`. Authority is built by canonical runtime admission from verified owner, connection/source generation, granted operation and monotonic expiry; it is never provider-supplied. `AudioControlLease` retains effective non-unity/muted/rerouted sessions independently of presentation subscriptions.

- [ ] Write `foreignOrRevokedWorkNeverTouchesHAL`, `revokeDuringPrepareDiscardsResult`, `twoConsumersShareCanonicalDiscovery`, `notchClosureKeepsExplicitControlLease`, `disableReleasesExactOwnersSessions`, `quotaDenialStartsNoSession`, `delegatedCPUIsCharged`, `workerHangDoesNotBlockActionAdmission`. Reuse existing ServiceBroker/runtime fixtures and subscription receipt tests; no duplicate broker instance.
- [ ] Run `AudioServiceHostTests`; expect missing host/accounting behavior.
- [ ] Implement shared system-adapter binding through existing source/grant/work admission and correlated settlement. Keep the generic service transport; Audio exposes no symbol/selector proxy. Use owner-bound ongoing-control reservations, measured native memory and delegated CPU attribution. The ordinary provider 5 ms/s profile remains intact; continuous sample work requires its own admitted service profile with the approved audio gates, never an uncharged exception.
- [ ] Run new suite plus existing `ServiceBroker`, runtime service invocation/subscription and delegated-CPU suites using their actual discovered test names. Expect no grant/revocation/accounting regressions. Commit `feat: broker audio control with explicit service leases`.

### Task 6: Common addon controls and display-bound options

**Files:** Create `CascadeKit/Sources/CascadeContracts/Models/Content/ValueControl.swift`, `ContentSelection.swift`, `Models/Pages/AddonOptionsRequest.swift`; `CascadeKit/Sources/CascadeRuntime/Core/Publications/AddonOptionsCoordinator.swift`; `CascadeKit/Sources/CascadePresentation/Components/Content/CascadeValueControl.swift`, `CascadeSelection.swift`. Modify `ContentNode.swift`, `OperationRequest.swift`, `ContentRenderer.swift`, `ProtocolNegotiator.swift`, `AddonRuntime.swift` and the generic display presentation bridge. Tests `CascadeContractsTests/AddonControlTests.swift`, `CascadeRuntimeTests/AddonOptionsTests.swift`, `CascadePresentationTests/AddonControlPresentationTests.swift`.

**Interfaces:** Generic `.valueControl`, `.selection`, `.horizontalScroll` content kinds, finite value [0,1], vertical/horizontal orientation, bounded choices, action ID and opaque base payload. `ControlActionInput` combines base payload with typed selected value/choice within the existing 4096-byte action limit. `OperationRequest.presentOptions(AddonOptionsRequest)`/`.dismissOptions(UUID)`; request binds publication ID/revision, originating action request ID and bounded document. Host binds display from the accepted user action, never an arbitrary provider display ID. Negotiate cumulative protocol 1.5 and capabilities `content.controls.v1`/`notch.options.v1` only when implemented; retain 1.4 compatibility.

- [ ] Write `unknownCapabilityRejectsBeforePublication`, `invalidValueOrChoiceCannotDispatch`, `actionFromExpiredRevisionCannotOpenOptions`, `refreshCannotReplaceOpenPage`, `escapeBackWithdrawalDisableAndDisplayRemovalRestoreArrangement`, `competingLeaseRevokesPrevious`, `optionsDoNotExtendAudioPresentationSubscription`. Assert one page lease, bounded document/choices and original display/page restoration.
- [ ] Run the three suites; expect absent capabilities/kinds/coordinator.
- [ ] Implement common factories/renderers, current-revision action authorization and generic page bridge. Vertical controls use cached layout/layer transforms during dragging; coalesce to at most one in-flight service command plus latest pending value, always flush final value. Keyboard/VoiceOver expose label, percentage, mute and route; no periodic UI timer. No Audio-specific model in NotchEngine; mark only the first three shared TODO items complete after tests, leave Caffeinate wiring unchecked.
- [ ] Run suites plus existing content decoding, action authorization and display presentation checks. Compare real app interaction CPU/main-thread behavior before/after when the generic bridge can be driven. Commit `feat: add shared addon controls and notch options`.

### Task 7: Audio provider and mixer presentation

**Files:** Create `Addons/Audio/Package.swift`, `Manifests/audio.json`, `Sources/AudioAddon/AudioAddonProvider.swift`, `AudioMixerPresentation.swift`, `Tests/AudioAddonTests/AudioAddonTests.swift`, `README.md`. Use a public SDK export path in `CASCADE_SDK_PATH`, like `Examples/ServiceConsumer`; no full-host import.

**Interfaces:** `AudioAddonProvider: AddonProvider`, `handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput`; initializer binds owner/publication assignment and clock. `AudioMixerPresentation.make(_ snapshot: AudioMixerSnapshot, page: AudioMixerPage) throws -> ContentDocument`; pages `.mixer`/`.options`. Manifest declares widget/options/control capabilities, audio/storage permissions, REQUIRES service version 1 and external execution; capabilities must resolve before publication.

- [ ] Write `providerUsesOnlyDeclaredGrants`, `closeLeavesServiceControlEffective`, `stopCancelsLatePublication`, `staleRouteActionRejected`, `emptyRecoveringPermissionAndUnavailableStatesDiffer`, `optionsUseCommonRoute`, `masterAndAppControlsHaveAccessibleNames`, `largeAppListFitsBoundedScrollablePage`. Persist desired state through the service; presentation never writes synthetic unity.
- [ ] Build/test against a public-only SDK export; expect the provider/manifest absent initially. Check dependency/import boundary so host implementation cannot leak into the addon.
- [ ] Implement compact Audio tile, master-left vertical mixer, horizontal app columns with icon/gain/mute/one-route selection; options expose output/system sounds/input capabilities. Subscribe for visible state changes; sustained control leases stay in the service. Icon resource leases end when hidden. Never open mic streams just to list inputs.
- [ ] Run addon tests and public SDK boundary/manifest validation commands. Native preview demonstrates mixer/empty/options/errors and Reduce Motion/Transparency; label synthetic previews separately from real audio. Commit `feat: add audio mixer addon presentation`.

### Task 8: Real playback, performance and conditional activation

**Files:** Create `Prototypes/AudioQualification/run-qualification.py`, `README.md`, `docs/wayfinder/research/2026-10-03-audio-qualification.md`; modify `scripts/build-development.sh` and native addon host composition only after its separately qualified launcher/adapter exists. Do not expose internal AddonRuntime as a public catch-all API.

**Interfaces:** Qualification consumes the actual service/provider/kernel and writes compact measurements (no recorded audio): source/route/OS/architecture, before/after gain error, latency, CPU, RSS, wakeups, callback deadline distribution, generation and recovery state. Activation consumes only the qualified generic managed addon host, never legacy registration.

- [ ] Add failing qualification assertions for every Global Constraint threshold; scenarios are native bypass versus one/ten controlled apps on the same hardware, 60 s notch closed, silence/mute/idle and dragging. Require 0 periodic timers/render callbacks when no eligible controlled sessions and separately count active watchdog wakes.
- [ ] Run controlled-source/loopback or physical measurement at 44.1/48/96/192 kHz; check gain/mute, stereo isolation, unity handoff gaps/duplication, route isolation, wired and same-profile Bluetooth latency. Measure host/service/coreaudiod separately and do not count a saved percentage as gain evidence.
- [ ] Drive at least 50 real sleep/wake cycles, helper replacement/app restart, route loss/return, sample-rate changes, Bluetooth playback/call profile, concurrent commands and disable. Assert seeded first buffer, bounded recovery or visible error and no stale pointer/authority; daemon reset belongs only to an explicit fault session because it interrupts other audio.
- [ ] Run `scripts/test-addon-managed-death.sh`; current expected result is 78/HOLD. Activation remains pending until the separately reviewed mechanism proves pre-main selection and host-death exit; no script flag, in-process fallback or removal of the gate is part of Audio.
- [ ] When the generic host is qualified, run canonical `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer /bin/zsh scripts/build-development.sh`; expect success and `/Applications/Cascade.app` pointing to this build. Drive the real addon mixer across displays, options/Back/Escape/withdrawal and permissions. Quit/relaunch Cascade and verify exact executable/PID.
- [ ] Commit qualification evidence with precise hardware scope and pending cases; release only after required gates pass. A docs/probe milestone is not an implemented widget.

## Self-review and execution boundary

Coverage: contracts/identity Task 1; signal fidelity Task 2; persistence/recovery
Task 3; native bindings/cleanup Task 4; authorization/background control/resource
leases Task 5; shared controls/options/display restoration Task 6; provider/UI
Task 7; physical/performance/launcher verification Task 8. The five Review Focus
cases each have named tests above. Interfaces use the same types throughout.

The existing capability probe passed own-process mute/readback and symbol
inventory; it does not replace Tasks 2–8. Private Fig/MX ABI/effect remains
unverified and is an optional research track, not a dependency on invented
signatures. Select a replacement backend only when it passes the same measured
contract and improves the public baseline. Production activation and physical
qualification remain explicit prerequisites, not silent exceptions.

Recommended execution: subagent-driven implementation with a fresh independent
review per task, because ownership, realtime lifetime and canonical authority
cross three modules and an incorrect handoff can produce full-volume playback
or a hang. Human review of this executable plan precedes production code.
