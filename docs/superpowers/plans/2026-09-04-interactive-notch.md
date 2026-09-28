# Interactive Notch Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for the independent integration and review tasks. Shared engine integration stays with the coordinating worker.

**Goal:** Add hover haptics, interactive activity surfaces, Bluetooth connection notices and music provider foundations.

**Architecture:** Keep CascadeKit responsible for presentation and rendering. App integrations publish typed events and own system permissions; providers depend only on public activity contracts. Retain layer-driven morphing and event-driven idle behavior.

**Tech Stack:** Swift, macOS 14+, AppKit, SwiftUI, Core Animation, IOBluetooth, ApplicationServices, Swift Testing.

**Spec:** ../specs/2026-09-04-interactive-notch-design.md

## Global Constraints

- Aptica all'inizio dell'hover, prima del morph; nessun impulso per aggiornamenti automatici.
- No new third-party dependencies, polling loops, blocking main-thread work or fabricated device data.
- Preserve pre-existing project signing changes. Work on `codex/interactive-notch` in the shared checkout so the user can inspect the app immediately.
- Only claim native-notice suppression when the implementation can verify it; disclose AX dismissal limits.
- Code follows CODE_STYLE.md. Baseline: 21 passing package tests.

### Task 1: Presentation, input and haptics

Files: engine/controller, NotchHostView, NotchPanel, configuration, geometry, new Core/Activities and Core/Interaction types; package tests.

Interfaces: `NotchLiveActivity` exposes `id: String`, compact leading/trailing and expanded view factories; `LiveActivityContext.invalidate()` requests a content refresh. `NotchEngine.present(_:duration:)` publishes a persistent activity when duration is nil or a temporary one otherwise; `dismissActivity(id:)` removes it.

- [x] Add failing tests for immediate hover haptic, no duplicate while open, precise shape hit testing, compact geometry and persistent/transient restoration.
- [x] Implement an injected haptic performer and an activity host with one cancellable expiration task, coalescing by ID and a bounded transient queue.
- [x] Interpolate compact extents separately from expansion. Preserve spring continuity across updates and stop display links at rest.
- [x] Deliver clicks through to child views inside the path and toggle window mouse interception with the actual pointer position.
- [x] Suspend hidden content, preserve provider state and handle stop, lock/unlock, screen changes and Reduce Motion.

Example acceptance sequence:
```swift
host.present(music, duration: nil)
host.present(headphones, duration: 4)
host.dismiss(id: headphones.id)
#expect(host.currentActivity?.id == music.id)
```

### Task 2: Bluetooth event source

Files: new `Cascade/Integrations/Bluetooth/` Swift files only; self-contained tests in that directory or a testable pure model in CascadeKit if coordinated first.

Interfaces: `@MainActor protocol BluetoothMonitoring: AnyObject { func start() -> AsyncStream<BluetoothConnectionEvent>; func stop() }`. `BluetoothConnectionEvent` is a Sendable immutable struct containing `deviceID: String`, `name: String`, `symbolName: String`, `isConnected: Bool`. Concrete implementation: `IOBluetoothConnectionMonitor`.

- [x] Verify duplicate connection, disconnect/reconnect and startup baseline behavior through a pure reducer test.
- [x] Retain and unregister IOBluetooth connection/disconnection tokens. Seed existing connections silently, deduplicate per device and expose real connection/disconnection events.
- [x] Handle stop/restart and wake without recurring timers, device discovery scans or battery subprocesses.
- [x] Type-check with the local Xcode SDK and report hardware coverage limitations.

### Task 3: Native Bluetooth notice replacement

Files: new `Cascade/Integrations/Bluetooth/NativeBluetoothNoticeSuppressor.swift` and supporting narrowly scoped types if needed. No modifications to the other workers' files.

Interfaces: `@MainActor protocol BluetoothNoticeSuppressing: AnyObject { var status: BluetoothNoticeSuppressionStatus { get }; func start(); func stop(); func expectConnection(deviceName: String) }`. Provide concrete `AccessibilityBluetoothNoticeSuppressor` if AX is viable. Status differentiates permissionRequired, observing, unsupported and failure; never label post-presentation dismissal as guaranteed prevention.

- [x] Verify public reference and local system behavior before choosing exact identifiers. Read-only system inspection is allowed; do not change notification preferences or kill system processes.
- [x] Implement a selective event-driven AX observer only if supported, restrict dismissal to a matching recent device event, preserve pairing/security prompts, and enforce bounded traversal/work off the main actor.
- [x] Stop observers and expire matching hints; no periodic scraping.
- [x] Report limitations and a concrete manual verification procedure, including potential native-banner flash.

### Task 4: App wiring and music foundation

Files: CascadeApp, new Features/BluetoothConnectionActivity, Features/MediaActivity, Integrations/Media protocol/models, and a native menu with preferences/demo controls. Info usage description in project configuration.

- [x] Wire a single monitor to the engine, show device events for four seconds, and forward connect hints to the native suppressor.
- [x] Add immutable Now Playing snapshots, command capabilities and provider contract with AsyncStream and async commands.
- [x] Provide compact/expanded music content and clearly labeled opt-in demo controls; do not show pretend playback at startup.
- [x] Provide user controls for aptics, Bluetooth monitoring and native replacement, with actual permission/status text and normal termination cleanup.

### Task 5: Verification and review

- [x] Run package tests after each feature cycle using the command below.
- [x] Build the app with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-notch-derived CODE_SIGNING_ALLOWED=NO build`.
- [x] Review final changes for lifecycle leaks, stolen input, content outside the hardware notch, hidden ticking views and false suppression claims.
- [x] Write a concise test/limitations record, including what needs a real Bluetooth accessory and physical haptic feedback verification.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-notch-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-notch-module-cache /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-notch-build --disable-sandbox
```

## Execution record

Pre-flight: Tasks 2 and 3 have disjoint source files and communicate only through typed events in Task 4. After the user's explicit request to develop with subagents, engine integration was also delegated with agreed API boundaries; the coordinator implemented activity arbitration and app/media integration. A separate agent reviewed the final changes. The user's hover-start correction supersedes the initial completion-trigger proposal. Main-branch work is avoided through the new feature branch; no existing user changes are committed or overwritten.

Implemented contracts also include `NotchLiveActivity.sourceID`, grouped dismissal,
and explicit `BluetoothMonitoringStatus`. Grouped dismissal avoids retaining a
growing history of device identifiers in the app. Native observer refresh is
idempotent so opening the menu preserves its recent connection hints.

Review identified and corrected service restart and overly strong native-status
wording. The final engine review also covers hidden widget activation, display
link startup while locked, compact wing hover, stale pointer state after restart,
and control dragging. Behavioral regression tests accompany these fixes.

The native override requirement remains **pending hardware/AX verification**.
The implementation is selective post-display dismissal, not guaranteed prevention.
App launch for interactive verification was rejected by automatic approval review
and needs explicit user approval. No workaround was attempted.

Full commands, evidence and remaining runtime checks:
`../verification/2026-09-04-interactive-notch.md`.
