# Audio Widget, Part B: Per-App Volume — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every app that plays audio its own column in the mixer — volume, mute and output (one or several devices) — enforced by an isolated `AudioHost` XPC service with process taps, kept through output switches (crossfade), sleep/wake and restarts.

**Architecture:** `AudioHost.xpc` owns discovery (HAL listeners), per-app pipelines (private process tap + private aggregate + IOProc driving a C render kernel) and recovery, on one serial control queue; it holds no persistent state. Cascade owns the intents (persisted by bundle ID), supervises `AudioHost` like PluginHost (3 s command deadline, 64 MiB, give-up after three faults in five minutes) and feeds the mixer's app columns through `AudioMixerModel`.

**Tech Stack:** Swift 6.2, C (realtime kernel), Core Audio process taps (macOS 14.2+ API, 15.0 floor), NSXPC, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-09-audio-widget-design.md` §3, §4, §5, §6 phases 4–8. Part A's plan: `docs/superpowers/plans/2026-10-09-audio-widget-bar-and-global-mixer.md`. Spike results: `docs/superpowers/verification/2026-10-09-audio-lifecycle-spike.md` (A: a killed process takes its private tap and aggregate with it; B: the tapped app is audible again at once; C: a public aggregate survives).

## Global Constraints

- macOS 15.0 floor; Xcode at `/Applications/Xcode.app`; Swift 6.2; no new dependencies.
- CLAUDE.md and CODE_STYLE.md apply in full (Antirez-style English `///`, column alignment, one modifier per line, `case` indented in `switch`, attributes on their own line, one-line guards on one line, one type per file).
- No HAL call on Cascade's main thread, ever. In `AudioHost` every HAL call (process/device reads, tap/aggregate create/destroy, `AudioDeviceStart`/`Stop`) runs on its single serial control queue.
- The IOProc body is C: no allocation, lock, logging, Objective-C/Swift runtime call or HAL call; it reads one atomic command, writes every output byte.
- Gain in 0…1, no boost, no limiter/EQ/gate; a gain change ramps over 5 ms, advanced once per frame across channels; mute writes exact zeros after its ramp; the first buffer of a new pipeline already uses the requested gain/mute (seeded before `AudioDeviceStart`).
- An app at 100 %, unmuted, following the system output gets no tap at all.
- Tap: `muteBehavior = .mutedWhenTapped`; a stream-specific tap when the app has one output, a stereo mixdown otherwise. Aggregate: private; N outputs → stacked, first output = clock and main sub-device, drift compensation on the others; `TapAutoStart` true.
- Crossfade on an output change: equal-power over 50 ms; old and new pipelines coexist ≤ 100 ms; direct switch when the old output is gone.
- Recovery: retries immediately, then at 100, 300, 1000 ms; at 3 s the app is *not applied*; two failures of the same configuration → native audio for that app, reported. One 1 Hz watchdog, only while controlled IO is expected, comparing atomic render counters (never amplitude).
- Supervision (Cascade side): every XPC command has a 3 s reply deadline, past it Cascade SIGKILLs `AudioHost`; restart past 64 MiB footprint; three crashes, hangs or memory kills in five minutes → give up (per-app audio native), shown in Settings → Plugins with Restart.
- Intents `{ gain, isMuted, outputs: [deviceUID] (empty = follow system) }` by bundle ID, persisted by Cascade (UserDefaults JSON), replayed to `AudioHost` at every (re)start. A missing device never erases a preference.
- Apps appear when any of their processes runs output, leave 3 s after the last stops (one-shot, not a periodic timer). Processes group under their outermost enclosing `.app` bundle (browser helpers under the browser).
- Idle: `AudioHost` not running when no intent differs from neutral and no mixer is visible; 0 timers, 0 render callbacks.
- UI copy keys English with Italian translations: "Follow system" → "Segui sistema", "Not applied" → "Non applicato", "Return to native audio" → "Torna all'audio nativo", "Allow audio capture in System Settings" → "Consenti la registrazione audio nelle Impostazioni di Sistema".
- Every git command prefixed with `timeout 120`; stage files by path only.

## Review Focus

1. A browser plays from a helper process and the user mutes "Google Chrome": every Chrome helper that renders audio is muted, and a helper that starts later inherits the intent. Test in Task 3 (grouping) and Task 7 (late helper joins the app's tap).
2. The user drags an app's volume while its pipeline is still being built or rebuilt: the first audible buffer uses the latest value, and no obsolete build installs an older one. Test in Task 4 (`obsoleteBuildIsDiscarded`) and Task 6 (`seededGainIsTheLatest`).
3. Sleep/wake with the app at 25 %: after wake the app is rebuilt and plays at 25 %, never at 100 % for longer than the measured gap. Test in Task 4 (`wakeRebuildsEvenWithIdenticalIDs`) plus the physical check in Task 11.
4. `AudioHost` crashes or hangs while apps are controlled: those apps become audible natively (spike A/B), the columns show *recovering*, and Cascade replays the intents on restart. Test in Task 9.
5. Audio capture permission denied: controlling an app must never silence it. Task 1 measures what a denied `mutedWhenTapped` tap does; Task 10's tests pin the read-only behaviour that follows from it.

---

### Task 1: Spike — denied capture permission and helper grouping

Throwaway probe; output is a verification note.

**Files:** Create `Prototypes/AudioTapPermissionProbe/main.swift`, `Prototypes/AudioTapPermissionProbe/run-probe.sh`, `docs/superpowers/verification/2026-10-10-audio-tap-permission-spike.md`.

**Interfaces:** Produces answers Tasks 5, 7 and 10 read: (P1) with System Audio Recording denied for the probe's responsible app, does `AudioHardwareCreateProcessTap` fail (which OSStatus), or succeed and deliver silence; (P2) in that case, is the tapped app silenced (`mutedWhenTapped`) or still audible; (P3) is there any readable signal of denial (tap creation status, `kAudioTapPropertyFormat`, IOProc input all-zero for a known-loud source); (P4) for Safari and Chrome playing a YouTube video, the list of audio-rendering process objects with their PID, `kAudioProcessPropertyBundleID` and executable path (`proc_pidpath`), and the outermost enclosing `.app` of each.

- [ ] **Step 1:** Write the probe: `tap <pid>` (stereo-mixdown tap, `mutedWhenTapped`, private aggregate over the default output, IOProc that counts callbacks and records the peak of the tap buffer, prints JSON every second for 5 s), and `processes` (prints every process object with `IsRunningOutput`, bundle ID, PID, `proc_pidpath`, outermost `.app`).
- [ ] **Step 2:** `run-probe.sh` plays a known tone with `afplay`, runs `tap` against it, asks the human (y/n) whether the tone is audible during the tap, and prints a paste block.
- [ ] **Step 3 (human):** run it twice — once with the permission granted, once after turning it off for the terminal in System Settings → Privacy & Security → Screen & System Audio Recording — and once `processes` while Safari and Chrome each play a YouTube video. Record P1–P4 in the note.
- [ ] **Step 4:** Commit `"Measure what a denied capture permission does to a muting tap"`.

### Task 2: AudioHost contracts and the XPC protocol

**Files:**
- Modify: `CascadeKit/Package.swift` (new target `CascadeAudioHost` depending on `CascadeContracts` (and `CascadeAudioRender` once Task 5 adds it), library product `CascadeAudioHost`, test target `CascadeAudioHostTests` depending on both)
- Create the value models in the public contracts, so CascadeKit (the mixer) and AudioHost share them without CascadeKit depending on AudioHost's HAL code — under `CascadeKit/Sources/CascadeContracts/Models/Audio/`: `AudioAppIdentity.swift`, `AudioAppIntent.swift`, `AudioAppEnforcement.swift`, `AudioAppSnapshot.swift`, `AudioHostSnapshot.swift`, `AudioHostCommand.swift`, `AudioHostWire.swift`; the XPC protocols under `CascadeKit/Sources/CascadeAudioHost/Core/Protocols/`: `AudioHostProtocol.swift`, `AudioHostClientProtocol.swift`
- Test: `CascadeKit/Tests/CascadeContractsTests/AudioHostContractTests.swift`

**Interfaces — Produces:**

```swift
public struct AudioAppIdentity: Codable, Hashable, Sendable { public let bundleID: String }   // outermost .app bundle id; never a PID or a name
public struct AudioAppIntent: Codable, Equatable, Sendable {
    public let gain: Double            // 0...1, finite
    public let isMuted: Bool
    public let outputUIDs: [String]    // empty = follow the system output; ≤ 8, unique
    public static let neutral: AudioAppIntent   // 1, false, []
    public var isNeutral: Bool { get }
}
public enum AudioAppEnforcement: String, Codable, Sendable { case native, applied, recovering, notApplied }
public struct AudioAppSnapshot: Codable, Equatable, Sendable {
    public let identity: AudioAppIdentity
    public let displayName: String
    public let intent: AudioAppIntent           // what AudioHost was told
    public let enforcement: AudioAppEnforcement
    public let effectiveOutputUIDs: [String]    // where it actually plays
}
public struct AudioHostSnapshot: Codable, Equatable, Sendable {
    public let generation: UInt64               // AudioHost incarnation-local, increases per change
    public let apps: [AudioAppSnapshot]         // only apps producing audio, ≤ 64
    public let captureAllowed: Bool?            // nil = unknown (see Task 1)
}
public enum AudioHostCommand: Codable, Equatable, Sendable {
    case replaceIntents([AudioAppIdentity: AudioAppIntent])   // full set, sent at (re)start
    case setIntent(AudioAppIdentity, AudioAppIntent)
    case returnToNative(AudioAppIdentity)
}
@objc public protocol AudioHostProtocol {
    func hello(reply: @escaping @Sendable (Int32) -> Void)            // AudioHost's PID
    func send(_ command: Data, reply: @escaping @Sendable (Bool) -> Void)   // JSON AudioHostCommand
}
@objc public protocol AudioHostClientProtocol {
    func publish(_ snapshot: Data)                                   // JSON AudioHostSnapshot
}
public enum AudioHostWire { public static func encode<T: Encodable>(_ value: T) throws -> Data; public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T }   // ≤ 64 KiB, rejects unknown fields like the plugin contracts
```

- [ ] **Step 1: Failing tests**

```swift
@Test func intentRejectsNonFiniteOrOutOfRangeGain()      // NaN, -0.1, 1.1, .infinity throw
@Test func intentRejectsDuplicateOrTooManyOutputs()       // 9 outputs or a duplicate throw
@Test func neutralIntentIsNeutral()                       // AudioAppIntent.neutral.isNeutral; gain 0.5 is not
@Test func wireRejectsOversizedAndUnknownFields()         // 64 KiB + 1 → throws; {"gain":1,"isMuted":false,"outputUIDs":[],"x":1} → throws
@Test func commandsRoundTrip()                            // each case encodes and decodes equal
@Test func snapshotCapsAppsAt64()
```

- [ ] **Step 2:** `swift test --package-path CascadeKit --filter AudioHostContractTests` → FAIL (missing types).
- [ ] **Step 3:** Implement; validation follows `ContractValidation` in CascadeContracts (reuse it).
- [ ] **Step 4:** Same command → PASS.
- [ ] **Step 5:** Commit `"Define the AudioHost contract"`.

### Task 3: Grouping processes into apps

**Files:** Create `CascadeKit/Sources/CascadeAudioHost/Core/Discovery/AudioProcessGrouping.swift`, `.../Models/AudioProcessRecord.swift`; Test `CascadeKit/Tests/CascadeAudioHostTests/AudioProcessGroupingTests.swift`.

**Interfaces — Produces:**

```swift
public struct AudioProcessRecord: Equatable, Sendable {
    public let objectID: UInt32; public let pid: Int32; public let bundleID: String?
    public let executablePath: String?; public let isRunningOutput: Bool
}
public enum AudioProcessGrouping {
    /// outermost .app of a path: "/Applications/Google Chrome.app/Contents/Frameworks/.../Google Chrome Helper (Renderer).app/Contents/MacOS/x" → "/Applications/Google Chrome.app"
    public static func outermostApp(of executablePath: String) -> String?
    /// groups processes under an identity: bundle ID of the outermost .app (resolved through `bundleIDOfApp`), else the process's own bundle ID, else excluded (unidentified processes are never controlled)
    public static func group(_ processes: [AudioProcessRecord], bundleIDOfApp: (String) -> String?) -> [AudioAppIdentity: [AudioProcessRecord]]
}
```

- [ ] **Step 1: Failing tests** — `chromeHelpersGroupUnderChrome` (three helper paths inside Chrome.app → one identity "com.google.Chrome"); `safariWebContentGroupsUnderSafari` (WebKit's `com.apple.WebKit.GPU` process with the bundle path P4 measured in Task 1 → "com.apple.Safari"; if Task 1 shows WebKit GPU lives outside Safari.app, map it through the PID's responsible app as Task 1's note prescribes and test that instead); `processWithoutPathOrBundleIsExcluded`; `twoPIDsOfOneAppShareOneIdentity`; `outermostAppOfAPathWithoutAppIsNil`.
- [ ] **Step 2–4:** FAIL → implement (pure string walk on path components; no disk access inside `group`) → PASS.
- [ ] **Step 5:** Commit `"Group audio processes under their app"`.

### Task 4: The reconciler

**Files:** Create `CascadeKit/Sources/CascadeAudioHost/Core/Reconcile/AudioReconciler.swift`, `.../Models/AudioReconcileAction.swift`, `.../Models/AudioPipelineState.swift`; Test `CascadeKit/Tests/CascadeAudioHostTests/AudioReconcilerTests.swift`.

**Interfaces — Produces:** a value-type reducer, no HAL:

```swift
public struct AudioPipelineConfiguration: Hashable, Sendable { public let processObjectIDs: [UInt32]; public let outputUIDs: [String]; public let streamTap: Bool }
public enum AudioPipelineState: Equatable, Sendable {
    case none, building(token: UInt64, AudioPipelineConfiguration), running(token: UInt64, AudioPipelineConfiguration),
         crossfading(from: UInt64, to: UInt64, AudioPipelineConfiguration), failed(AudioPipelineConfiguration, attempts: Int, since: Duration), native(AudioPipelineConfiguration)
}
public enum AudioReconcileAction: Equatable, Sendable {
    case build(AudioAppIdentity, token: UInt64, AudioPipelineConfiguration, AudioAppIntent)
    case crossfade(AudioAppIdentity, from: UInt64, to: UInt64, AudioPipelineConfiguration, AudioAppIntent)
    case updateCommand(AudioAppIdentity, token: UInt64, AudioAppIntent)     // gain/mute change on a running pipeline
    case teardown(AudioAppIdentity, token: UInt64)
    case scheduleRetry(AudioAppIdentity, after: Duration)                   // 0, 100, 300, 1000 ms
}
public struct AudioReconciler: Sendable {
    public init()
    public mutating func reconcile(intents: [AudioAppIdentity: AudioAppIntent], apps: [AudioAppIdentity: [AudioProcessRecord]], outputs: Set<String>, systemOutputUID: String?, now: Duration) -> [AudioReconcileAction]
    public mutating func built(_ app: AudioAppIdentity, token: UInt64, succeeded: Bool, now: Duration) -> [AudioReconcileAction]
    public mutating func environmentInvalidated(now: Duration) -> [AudioReconcileAction]   // wake, coreaudiod restart, format change: rebuild everything running
    public func state(of app: AudioAppIdentity) -> AudioPipelineState
    public func enforcement(of app: AudioAppIdentity, now: Duration) -> AudioAppEnforcement
}
```

Rules: neutral intent + following system → no pipeline (teardown if any). Effective outputs = intent outputs that exist; if none exists, the system output. A configuration change on a running pipeline → `crossfade` when the old outputs still exist, else teardown + build. Tokens strictly increase; `built` with a token that is not the current one is ignored (obsolete build). Failures: retries at 0/100/300/1000 ms; `enforcement` is `.recovering` until 3 s since the first failure, then `.notApplied`; the second failure *episode* for an identical configuration → `.native` (no more builds until the configuration or intent changes, or `returnToNative` clears it).

- [ ] **Step 1: Failing tests** — `neutralFollowingSystemNeedsNoPipeline`; `quarterGainBuildsOnePipeline`; `gainChangeOnRunningPipelineUpdatesCommandOnly`; `outputChangeCrossfades`; `outputGoneSwitchesDirectly`; `obsoleteBuildIsDiscarded` (Review Focus 2); `missingPreferredOutputFallsBackToSystemAndKeepsPreference`; `wakeRebuildsEvenWithIdenticalIDs` (Review Focus 3); `retriesAtZeroHundredThreeHundredThousand`; `notAppliedAfterThreeSeconds`; `secondFailureEpisodeGoesNative`; `appLeavingTearsDownItsPipeline`; `lateHelperChangesConfigurationAndRebuilds` (Review Focus 1).
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `"Reconcile intents into pipeline actions"`.

### Task 5: The realtime render kernel

**Files:** Create `CascadeKit/Sources/CascadeAudioRender/include/CascadeAudioRender.h`, `CascadeKit/Sources/CascadeAudioRender/CascadeAudioRender.c`, `CascadeKit/Tests/CascadeAudioHostTests/AudioRenderKernelTests.swift`; Modify `CascadeKit/Package.swift` (C target, `-O2`, `-Wall -Wextra -Werror`).

**Interfaces — Produces (C API):**

```c
typedef struct CascadeAudioRender CascadeAudioRender;          // opaque, allocated off the realtime thread
typedef struct { double sampleRate; uint32_t channels; bool interleaved; bool float64; uint32_t maxFrames; } CascadeAudioRenderFormat;
CascadeAudioRender *CascadeAudioRenderCreate(CascadeAudioRenderFormat input, CascadeAudioRenderFormat output, double gain, bool muted);  // NULL on invalid format
void     CascadeAudioRenderSetCommand(CascadeAudioRender *, double gain, bool muted);            // any thread; atomic, lock-free
void     CascadeAudioRenderSetCrossfade(CascadeAudioRender *, double fromWeight, double toWeight, uint32_t frames); // equal-power ramp of this pipeline's share
void     CascadeAudioRenderProcess(CascadeAudioRender *, const AudioBufferList *input, AudioBufferList *output, uint32_t frames); // realtime: tap = LAST input buffer; maps channels (mono↔stereo, N-channel by index, extra outputs zeroed); writes every output byte
uint64_t CascadeAudioRenderCallbackCount(const CascadeAudioRender *);                             // atomic, for the watchdog
void     CascadeAudioRenderDestroy(CascadeAudioRender *);                                        // only after the IOProc is stopped
```

Ramp: linear in gain over `round(sampleRate × 0.005)` frames, advanced once per frame for all channels; a new command starts from the current ramped value. Mute = ramp to 0 then exact zeros. Crossfade weights `cos/sin` of a linear phase over the given frames.

- [ ] **Step 1: Failing tests** (Swift calling the C API with synthetic buffers, compared to a Double oracle): `unityIsBitExactWhenSettled`; `quarterGainMatchesScalarWithinOneULP` (Float32 and Float64, 44.1/48/96/192 kHz); `rampTakesFiveMilliseconds`; `muteWritesExactZerosAfterRamp`; `rightOnlySignalKeepsBothChannels`; `nearSilenceIsNotGated` (1e-7 amplitude survives scaled); `fullScalePeaksAreNotLimited`; `monoToStereoAndStereoToMono`; `planarAndInterleaved`; `tapIsTheLastInputBuffer` (device input buffer first, tap second); `nanInputIsCountedNotPropagated` (output zero for those samples); `crossfadeIsEqualPower` (sum of squares of the two weights == 1 ± 1e-9 across the ramp); `callbackCountIncrements`.
- [ ] **Step 2–4:** FAIL → implement → PASS. The header documents that `CascadeAudioRenderProcess` allocates nothing, takes no lock and makes no system call; the file is one translation unit that calls nothing outside `<math.h>`, `<string.h>` (`memset`) and `<stdatomic.h>`, which the reviewer checks by reading.
- [ ] **Step 5:** Commit `"Add the audio render kernel"`.

### Task 6: HAL seam and the per-app pipeline

**Files:** Create under `CascadeKit/Sources/CascadeAudioHost/Core/HAL/`: `AudioHostHAL.swift` (protocol), `CoreAudioHostHAL.swift`; under `Core/Pipeline/`: `AppAudioPipeline.swift`; Test `CascadeKit/Tests/CascadeAudioHostTests/AppAudioPipelineTests.swift`, `.../Support/FakeAudioHostHAL.swift`.

**Interfaces:**
- Consumes: Task 4's `AudioPipelineConfiguration`, Task 5's C API, Task 2's `AudioAppIntent`.
- Produces:

```swift
public protocol AudioHostHAL: AnyObject, Sendable {   // every call on the control queue
    func processes() -> [AudioProcessRecord]
    func outputUIDs() -> Set<String>
    func systemOutputUID() -> String?
    func streamFormat(ofOutput uid: String) -> CascadeAudioRenderFormat?
    func createTap(processObjectIDs: [UInt32], streamOfOutput uid: String?) -> (tapID: UInt32, uuid: String, format: CascadeAudioRenderFormat)?
    func createAggregate(tapUUID: String, outputUIDs: [String]) -> UInt32?       // private; stacked when > 1 output; clock = first; drift compensation on the others
    func start(aggregate: UInt32, render: OpaquePointer) -> Bool                  // installs the IOProc calling CascadeAudioRenderProcess, then AudioDeviceStart
    func stop(aggregate: UInt32)                                                  // AudioDeviceStop + destroy IOProc; returns after the IOProc is quiescent
    func destroy(aggregate: UInt32); func destroy(tap: UInt32)
    func listen(onProcesses: @escaping @Sendable () -> Void, onDevices: @escaping @Sendable () -> Void, onServiceRestart: @escaping @Sendable () -> Void)
}
final class AppAudioPipeline: @unchecked Sendable {   // control-queue confined
    init?(identity: AudioAppIdentity, token: UInt64, configuration: AudioPipelineConfiguration, intent: AudioAppIntent, hal: any AudioHostHAL)   // nil = build failed; everything created is torn down again
    func update(_ intent: AudioAppIntent)
    func beginCrossfade(fadingIn: Bool, frames: UInt32)
    var callbackCount: UInt64 { get }
    func teardown()   // stop, destroy aggregate, destroy tap, destroy render context — in that order
}
```

- [ ] **Step 1: Failing tests** (fake HAL records calls in order) — `buildCreatesTapAggregateRenderThenStarts`; `seededGainIsTheLatest` (render created with the intent's gain/mute before `start`, Review Focus 2); `singleOutputUsesAStreamTap`; `severalOutputsUseAMixdownTapAndAStackedAggregate`; `failedAggregateTearsDownTheTap`; `teardownOrderIsStopAggregateTapRender`.
- [ ] **Step 2–4:** FAIL → implement (`CoreAudioHostHAL` uses `CATapDescription`, `AudioHardwareCreateProcessTap`, `AudioHardwareCreateAggregateDevice` with `kAudioAggregateDeviceIsPrivateKey: true`, `TapAutoStart: true`, `kAudioSubTapDriftCompensationKey: true`, `AudioDeviceCreateIOProcID` with a C callback trampoline that only calls `CascadeAudioRenderProcess`) → PASS.
- [ ] **Step 5:** Commit `"Build one app's tap, aggregate and render pipeline"`.

### Task 7: The AudioHost service

**Files:** Create `CascadeKit/Sources/CascadeAudioHost/Core/Service/AudioHostService.swift`, `.../Core/Service/AudioHostListener.swift`, `.../Core/Service/AudioHostWatchdog.swift`; Test `CascadeKit/Tests/CascadeAudioHostTests/AudioHostServiceTests.swift`.

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces: `public final class AudioHostService: NSObject, AudioHostProtocol` with `public init(hal: any AudioHostHAL, queue: DispatchQueue, clock: @escaping @Sendable () -> Duration, schedule: @escaping @Sendable (Duration, @escaping @Sendable () -> Void) -> Void, publish: @escaping @Sendable (AudioHostSnapshot) -> Void)`; `public final class AudioHostListener: NSObject, NSXPCListenerDelegate` mirroring `PluginHostListener` (code-signing requirement from `PluginHostSigning`).

Behaviour: listeners → `apps = AudioProcessGrouping.group(hal.processes(), …)` → reconciler → execute actions (build pipelines; crossfade = build the new one fading in, fade the old out over 50 ms, teardown old after ≤ 100 ms via `schedule`); `NSWorkspace.didWakeNotification` and `onServiceRestart` → `environmentInvalidated`; apps leave 3 s after their last running process stops (one-shot `schedule`); watchdog: while any pipeline is running, one 1 Hz `schedule` chain compares each pipeline's `callbackCount`; two stale ticks while its app still runs output → treat as a failed build; the chain stops when no pipeline runs. A snapshot is published after every change (equal snapshots skipped).

- [ ] **Step 1: Failing tests** (fake HAL, manual clock and scheduler) — `setIntentBuildsAndPublishesApplied`; `neutralIntentTearsDownAndPublishesNative`; `appLeavesThreeSecondsAfterSilence`; `lateHelperJoinsTheAppsTap` (Review Focus 1); `wakeRebuilds`; `crossfadeKeepsBothPipelinesAtMostHundredMilliseconds`; `watchdogStartsOnlyWithRunningPipelines`; `staleCallbacksTriggerRecovery`; `replaceIntentsAppliesTheWholeSet`; `returnToNativeClearsANativeFallback`; `noHALCallOffTheControlQueue`.
- [ ] **Step 2–4:** FAIL → implement → PASS.
- [ ] **Step 5:** Commit `"Run per-app pipelines in the AudioHost service"`.

### Task 8: The AudioHost.xpc target

**Files:** Create `AudioHost/main.swift`, `Config/AudioHost-Info.plist` (copy of `Config/PluginHost-Info.plist`); Modify `Cascade.xcodeproj/project.pbxproj` (a new native target `AudioHost`, product `AudioHost.xpc`, bundle id `hylo.Cascade.AudioHost`, linking the `CascadeAudioHost` package product, folder-synchronized group `AudioHost`, embedded in Cascade's "Embed XPC Services" phase, same build settings as the `PluginHost` target: hardened runtime, no sandbox, Swift 6.0, approachable concurrency) — mirror every `PluginHost` entry (`PBXBuildFile`, `PBXFileReference`, `PBXFileSystemSynchronizedRootGroup`, `PBXNativeTarget`, `PBXTargetDependency`, `PBXContainerItemProxy`, configuration list, package product dependency) with fresh IDs; `CascadeKit/Package.swift` (library product `CascadeAudioHost`); `scripts/build-development.sh` unchanged unless the build needs it.

`main.swift`: like `PluginHost/main.swift` — derive the app identifier from `".AudioHost"`, create `AudioHostService(hal: CoreAudioHostHAL(queue:), queue: DispatchQueue(label: "cascade.audiohost.control", qos: .userInitiated), …)`, `NSXPCListener.service()` with `AudioHostListener`, resume.

- [ ] **Step 1:** Add the target and files.
- [ ] **Step 2:** Verify: `xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-audio-dd build` succeeds and `ls /private/tmp/cascade-audio-dd/Build/Products/Debug/Cascade.app/Contents/XPCServices` lists `AudioHost.xpc` and `PluginHost.xpc`; `codesign --verify --deep --strict` on the app passes.
- [ ] **Step 3:** Commit `"Bundle the AudioHost XPC service"`.

### Task 9: Cascade side — client, supervision, intents

**Files:** Create in CascadeKit `CascadeKit/Sources/CascadeKit/Core/Protocols/AudioAppsControlling.swift` (the protocol below, which Task 10's model consumes); in `Cascade/Core/Audio/`: `AudioHostClient.swift`, `AudioHostSupervision.swift`, `AudioIntentStore.swift`, `AppAudioService.swift`; in `Cascade/Core/Protocols/`: `AudioHostConnecting.swift`; Modify `CascadeKit/Sources/CascadePluginEngine/Models/PluginHostIncarnation.swift` (make `kill()` and `footprint()` public — reused for AudioHost); Test `CascadeTests/AppAudioServiceTests.swift`, `CascadeTests/Support/FakeAudioHostConnection.swift`.

**Interfaces:**
- Consumes: Task 2's contract; `PluginHostIncarnation`; `PluginHostSupervisor`'s policy as a model (do not reuse the type — its loss kinds are plugin-specific).
- Produces:

```swift
protocol AudioHostConnecting: AnyObject, Sendable {            // the XPC seam, faked in tests
    func connect(onSnapshot: @escaping @Sendable (AudioHostSnapshot) -> Void, onLoss: @escaping @Sendable () -> Void) -> Bool
    func hello(_ reply: @escaping @Sendable (Int32?) -> Void)
    func send(_ command: AudioHostCommand, reply: @escaping @Sendable (Bool?) -> Void)   // nil = no reply (link broke)
    func footprint() -> UInt64?; func kill(); func disconnect()
}
struct AudioHostSupervision: Sendable {                        // pure policy
    static let commandDeadline = Duration.seconds(3); static let memoryLimit: UInt64 = 64 << 20; static let faultLimit = 3; static let window = Duration.seconds(300)
    mutating func lost(_ loss: Loss, at: Duration) -> Duration?   // nil = given up; backoff 1, 5, 30 s
    mutating func forgive(); private(set) var hasGivenUp: Bool
    enum Loss { case crashed, hung, overMemory }
}
final class AudioIntentStore { init(defaults: UserDefaults, key: String = "audioAppIntents"); func load() -> [AudioAppIdentity: AudioAppIntent]; func save(_ intents: [AudioAppIdentity: AudioAppIntent]) }   // JSON, off main on the service queue
@MainActor final class AppAudioService: AudioAppsControlling {
    init(connection: any AudioHostConnecting, store: AudioIntentStore, queue: DispatchQueue, clock: @escaping @Sendable () -> Duration)
    func setMixerVisible(_ isVisible: Bool)     // starts AudioHost when visible or when any stored intent is non-neutral; stops it when neither
    var onStatus: ((AudioHostStatus) -> Void)?  // .running, .recovering, .givenUp — for Settings
    func restart()                               // forgive + connect
}
```

```swift
@MainActor public protocol AudioAppsControlling: AnyObject {   // CascadeKit; defined here, consumed by Task 10's model
    func setIntent(_ intent: AudioAppIntent, for app: AudioAppIdentity)
    func returnToNative(_ app: AudioAppIdentity)
    func setMixerVisible(_ isVisible: Bool)
}
```

`AppAudioService` also hands each `AudioHostSnapshot` to the model through a `var onSnapshot: ((AudioHostSnapshot) -> Void)?` on the main actor; Task 10 wires it to `AudioMixerModel.receive(_:)`.

Rules: on connect → `hello` (PID recorded) → `replaceIntents(store.load())`; a command without reply in 3 s → `kill()` + loss `.hung`; after each reply check `footprint() > 64 MiB` → `kill()` + `.overMemory`; link loss without our kill → `.crashed`; backoff/give-up per `AudioHostSupervision`; on give-up the model's apps show native and Settings shows Restart. Intents are saved on every change.

- [ ] **Step 1: Failing tests** — `connectReplaysStoredIntents`; `commandWithoutReplyKillsAfterThreeSeconds` (manual clock); `footprintOverLimitKills`; `crashRestartsAfterBackoffAndReplays` (Review Focus 4); `threeFaultsInFiveMinutesGiveUp`; `restartForgivesAndReconnects`; `neutralIntentsAndHiddenMixerStopAudioHost`; `intentsSurviveAMissingDevice`; `noXPCCallOnTheMainThread`.
- [ ] **Step 2–4:** FAIL → implement (real `AudioHostClient` wraps `NSXPCConnection(serviceName: bundleID + ".AudioHost")` with the code-signing requirement from `PluginHostSigning`) → PASS: `xcodebuild … -only-testing:CascadeTests/AppAudioServiceTests test`.
- [ ] **Step 5:** Commit `"Supervise AudioHost and keep the per-app intents"`.

### Task 10: Mixer app columns and per-app picker

**Files:** Create in CascadeKit `Models/Audio/AudioAppState.swift`, `Components/Plugins/Audio/AudioAppColumn.swift`, `Components/Plugins/Audio/AudioAppIconCache.swift`; Modify `Core/Audio/AudioMixerModel.swift`, `Components/Plugins/Audio/AudioMixerComponent.swift`, `Components/Plugins/Audio/AudioOutputPicker.swift`, `Components/Plugins/Audio/AudioOutputPickerRow.swift`, `Resources/Localizable.xcstrings`, `CascadeKit/Sources/CascadePlugins/Resources/com.cascade.audio.json` (services `["audio.system", "audio.apps"]`, permissions `["audio.capture"]`), `Cascade/App/CascadeServices.swift` and `Cascade/Core/Plugins/PluginSystem.swift` (provide `audio.apps`, wire `AppAudioService`, Settings row for AudioHost in `Cascade/Views/Settings/PluginStatusSection.swift` with Restart); Test `CascadeKit/Tests/CascadeKitTests/AudioAppColumnTests.swift`, `AudioMixerModelTests.swift`.

**Interfaces:**
- Consumes: `AudioAppsControlling` and `AppAudioService.onSnapshot` (Task 9); the Task 2 models from CascadeContracts.
- Produces:

```swift
public struct AudioAppState: Equatable, Sendable { public let identity: AudioAppIdentity; public let displayName: String; public let intent: AudioAppIntent; public let enforcement: AudioAppEnforcement; public let effectiveOutputUIDs: [String] }
// AudioMixerModel gains:
public init(controller: any SystemAudioControlling, apps: (any AudioAppsControlling)? = nil)
public private(set) var apps: [AudioAppState]          // ordered by displayName
public private(set) var captureAllowed: Bool?
public func receive(_ snapshot: AudioHostSnapshot)
public func adjust(app: AudioAppIdentity, to gain: Double); public func endAdjusting(app: AudioAppIdentity)   // coalesced like the global level
public func toggleMute(app: AudioAppIdentity)
public func choose(outputUID: String?, for app: AudioAppIdentity)   // nil = Follow system; several mode toggles, never empties (empty → follow system)
```

Layout (the mixer's apps area, layout A, ~260 × 92 pt): a horizontal `ScrollView` of `AudioAppColumn`s, each 30 pt wide: app icon 18 pt at the top, then the capsule (`AudioVolumeCapsule`, `widthRatio: 1`, 18 pt wide, filling the height left), then a row with mute (16 pt) and output (16 pt, the device icon of its first effective output, `+N` when several) buttons. Enforcement: `.recovering` → a small `arrow.triangle.2.circlepath` badge on the icon; `.notApplied`/`.native` with a non-neutral intent → the capsule drawn with a dashed 1 pt stroke and a "Return to native audio" item in the column's context menu. The per-app picker opens over the apps area like the global one, with "Follow system" as its first row (checked when `outputUIDs` is empty). `captureAllowed == false` (from Task 1's answer) → columns read-only at their native 100 % and a one-line banner "Allow audio capture in System Settings" replacing the empty-state text, with a button opening `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`. Icons from `NSWorkspace.shared.icon(forFile:)` of the app URL resolved by bundle ID, loaded once per bundle ID on a background queue into `AudioAppIconCache`.

- [ ] **Step 1: Failing tests** — `appsArriveSortedAndLeave`; `appGainCoalescesToOneCommandPerFrame`; `followSystemIsTheFirstPickerRowAndClearsOutputs`; `severalModeNeverEmptiesItFallsBackToFollowSystem`; `captureDeniedMakesColumnsReadOnly` (Review Focus 5); `notAppliedShowsTheReturnToNativeAction`; `manifestDeclaresAudioAppsAndCapture` (in CascadePluginsTests).
- [ ] **Step 2–4:** FAIL → implement → PASS; full CascadeKit suite (known Battery failure only); app build.
- [ ] **Step 5:** Commit `"Show each playing app in the mixer"`.

### Task 11: Verification, documentation, spec amendments

**Files:** Create `docs/superpowers/verification/2026-10-10-audio-widget-part-b.md`; Modify `docs/superpowers/specs/2026-10-09-audio-widget-design.md` (§2: the detail keeps the notch's normal size, layout A, SF Symbols with device vs pill icons, percentage only in the mixer, icon ink white / #00C6EA, thin pill on the grid only; §3: Task 1's permission answer), `docs/plugins/services.md` and `docs/plugins/content.md` (`audio.apps`), `CLAUDE.md` (per-app audio no longer pending).

- [ ] **Step 1:** Update the docs so every statement matches the code.
- [ ] **Step 2:** Verification note: automated results (full CascadeKit, CascadeTests, `AudioRenderKernelTests`), and a manual checklist each marked "pending: run with the user": YouTube in Safari and in Chrome appears as one column per browser; 25 % and mute audibly applied; output to AirPods only, then AirPods + speakers (both play), crossfade without a click; 50 sleep/wake cycles at 25 % (no 100 % burst beyond the measured gap); AirPods disconnect while playing; `kill -9` AudioHost while controlling (audible at once, columns recover, intents replayed); three kills in five minutes → given up, Settings Restart works; permission denied behaviour; idle cost (AudioHost not running with neutral intents and the notch closed); CPU and memory against the spec's gates for one and ten apps.
- [ ] **Step 3:** Run the suites, commit `"Document per-app audio"`.
