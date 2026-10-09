# Audio Widget, Part A: Bar and Global Mixer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `1x2` volume bar widget and its full-page mixer with the global capsule and output selector (single and multi-output), on the plugin engine.

**Architecture:** A thin `com.cascade.audio` plugin publishes one `Component` per surface (widget and a new `detail` surface). The kernel draws the components natively from a main-actor `AudioMixerModel` fed by `SystemAudioService` in the app, which owns global volume, mute, the system output and Cascade's multi-output aggregate. The notch engine gains a detail page that a widget click opens.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit, Core Audio HAL, Swift Testing, `CascadeContracts` / `CascadePluginSDK` / `CascadePluginEngine` / `CascadeKit`.

**Spec:** `docs/superpowers/specs/2026-10-09-audio-widget-design.md` (§1, §2, §4 permissions none needed here, §6 phases 0–3).

**Part B** (spec §3 and phases 4–8: `AudioHost`, per-app pipeline, crossfade, recovery, qualification) gets its own plan, written after Task 1's spike results, which the spec says may change it.

## Global Constraints

- macOS 15.0 deployment floor; check every API exists on macOS 15.
- No new dependencies. English code, comments and docs; Antirez-style `///` narrative comments; column alignment; one modifier per line; see `CODE_STYLE.md`.
- No HAL call, disk IO or blocking on the main thread. HAL work runs on one serial utility queue owned by its service.
- No polling and no timers in this part. Listeners only. Nothing runs while no audio component is visible except the HAL listeners `SystemAudioService` keeps for the bar's state, and those only while the `audio` feature is enabled.
- Drag and scroll update the model immediately and send at most one hardware command per display frame (coalesce to the latest value).
- Volume 0 is not mute. Mute is set only from the mixer.
- Click versus drag on any capsule uses `WidgetPress.slop` (4 pt) and `WidgetPress.holdDuration` (500 ms): a press released within the slop and before the hold duration is a click; a held still press belongs to the grid's editing and does nothing in the component.
- Wheel scroll steps by 1/16; precise (trackpad) scroll is continuous, `deltaY / 200` per event (the capsule's full travel is 200 pt of finger movement). Momentum phases are ignored.
- UI copy keys in English with Italian translations in the target's `.xcstrings`: "Several outputs" → "Più uscite", "Follow system" → "Segui sistema", "Global volume" → "Volume globale", "Apps appear here when they play audio" → "Le app compaiono qui quando riproducono audio", "Back" → "Indietro".
- The global multi-output aggregate is public (not private), named "Cascade Multi-Output", UID prefix `cascade.multi-output.`, stacked, clock and main sub-device = first selected device, drift compensation on every other sub-device.
- Test commands: CascadeKit `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path CascadeKit --filter <Suite>`; app `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-audio-dd -only-testing:CascadeTests/<Suite> test`.

## Review Focus

1. The default output disappears (AirPods disconnect) while the mixer is open: the global capsule must follow the new default and the bar's icon must change, never show the stale device. Test owned by Task 7.
2. The user turns "Several outputs" off while Cascade's multi-output aggregate is the system output, or quits Cascade with it active: the system must be left on a real device and the aggregate destroyed; a leftover from a crash is destroyed at the next launch. Tests owned by Task 10.
3. A drag continues while the default output switches: commands carry the device ID they were made for, and a command for a device that is no longer the default is dropped. Test owned by Task 7.
4. A long press on the bar must still start grid editing and must not open the detail or change the volume. Test owned by Task 4.
5. The detail page is open on one display and that display is removed, or the notch collapses: the detail closes and the engine is told it is no longer visible. Tests owned by Tasks 3 and 5.

---

### Task 1: Spike — tap and aggregate lifecycle on process death

Throwaway probe whose output is a verification note; nothing here is product code.

**Files:**
- Create: `Prototypes/AudioLifecycleProbe/main.swift`, `Prototypes/AudioLifecycleProbe/run-probe.sh`, `Prototypes/AudioLifecycleProbe/README.md`
- Create: `docs/superpowers/verification/2026-10-09-audio-lifecycle-spike.md`

**Interfaces:**
- Produces: the note's answers to three questions, which Part B's plan reads: (A) does a private aggregate holding a process tap disappear when its creating process is killed with SIGKILL; (B) does the tapped app stay muted (`mutedWhenTapped`) after that kill; (C) does a public aggregate survive its creator's SIGKILL.

- [ ] **Step 1: Write the probe.** One executable with three modes: `create-private <pid>` (creates a `CATapDescription(stereoMixdownOfProcesses:)` tap with `muteBehavior = .mutedWhenTapped` on the process objects of `<pid>`, a private aggregate `Cascade-probe-<uuid>` holding it plus the default output, starts an IOProc that copies input to output, prints the aggregate and tap UIDs as JSON, then sleeps forever); `create-public` (creates a public stacked aggregate `cascade.multi-output.probe-<uuid>` over the default output, prints its UID, sleeps); `inspect <uid>...` (prints, as JSON, whether each UID is still present in `kAudioHardwarePropertyDevices` / `kAudioHardwarePropertyTapList`).
- [ ] **Step 2: Write `run-probe.sh`.** Starts `afplay` on a long system sound in a loop, runs each create mode in the background, waits 2 s, `kill -9`s it, waits 2 s, runs `inspect`, asks whether `afplay` is still audible (y/n) and records the answer, and destroys any public leftover through a final `inspect --destroy`. Build with `swiftc -O`.
- [ ] **Step 3: Run it on this Mac — the human partner runs this step, since it needs someone listening** — and write the note: macOS build, hardware, output device, the JSON, and the three answers. Each answer states what was observed, not inferred.
- [ ] **Step 4: Commit**

```bash
git add Prototypes/AudioLifecycleProbe docs/superpowers/verification/2026-10-09-audio-lifecycle-spike.md
git commit -m "Measure what a killed process leaves behind of taps and aggregates"
```

### Task 2: Contracts — the `detail` surface, audio components, Bluetooth address

**Files:**
- Modify: `CascadeKit/Sources/CascadeContracts/Models/PluginMessages/Enums/PluginSurfaceKind.swift`, `CascadeKit/Sources/CascadeContracts/Models/Plugin/PluginSurfaces.swift`, `CascadeKit/Sources/CascadeContracts/Core/Extensions/PluginSurfaces+Kind.swift`, `CascadeKit/Sources/CascadeContracts/Models/Plugin/PluginCatalog.swift`
- Create: `CascadeKit/Sources/CascadeContracts/Models/Bluetooth/PluginBluetoothAddress.swift`
- Modify: `CascadeKit/Sources/CascadePluginHost/Models/Bluetooth/BluetoothAudioRouteSnapshot.swift` (delegate to the new helper, delete its copy)
- Modify: `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginSurfaceRouter.swift` (`case .detail: break` placeholder so the switch compiles; Task 4 fills it)
- Test: `CascadeKit/Tests/CascadeContractsTests/PluginManifestTests.swift`, `CascadeKit/Tests/CascadeContractsTests/PluginMessageTests.swift`, `CascadeKit/Tests/CascadeContractsTests/PluginBluetoothStateTests.swift`

**Interfaces:**
- Produces: `PluginSurfaceKind.detail` (raw value `"detail"`); `PluginSurfaces.detail: PluginPlainSurface?` (JSON key `detail`, init parameter `detail:` last, default nil); `PluginCatalog.components` gains `"audio.volumeBar": 1` and `"audio.mixer": 1`; `public enum PluginBluetoothAddress { public static func outputAddress(fromUID uid: String) -> String? }`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func detailNeedsAWidgetInTheSameFeature() throws {
    #expect(throws: (any Error).self) { try PluginSurfaces(detail: PluginPlainSurface()) }
    let surfaces = try PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 2)]), detail: PluginPlainSurface())
    #expect(surfaces.declares(.detail))
}

@Test func detailDecodesFromTheManifest() throws {
    let json = #"{"widget":{"sizes":["1x2"]},"detail":{}}"#
    let surfaces = try JSONDecoder().decode(PluginSurfaces.self, from: Data(json.utf8))
    #expect(surfaces.detail != nil)
}

@Test func catalogOffersTheAudioComponents() {
    #expect(PluginCatalog.components["audio.volumeBar"] == 1)
    #expect(PluginCatalog.components["audio.mixer"] == 1)
    #expect(PluginCatalog.components["audio.outputPicker"] == 1)
}

@Test func detailPublicationRejectsRegions() // a .detail publication whose root is Regions throws, as a widget's does

@Test func outputAddressAcceptsOnlyTheOutputUIDShape() {
    #expect(PluginBluetoothAddress.outputAddress(fromUID: "a0-b1-c2-d3-e4-f5:output") == "A0-B1-C2-D3-E4-F5")
    #expect(PluginBluetoothAddress.outputAddress(fromUID: "A0-B1-C2-D3-E4-F5:input") == nil)
    #expect(PluginBluetoothAddress.outputAddress(fromUID: "BuiltInSpeakerDevice") == nil)
    #expect(PluginBluetoothAddress.outputAddress(fromUID: "A0-B1-C2-D3-E4:output") == nil)
}
```

- [ ] **Step 2: Run** `... swift test --package-path CascadeKit --filter "PluginManifestTests|PluginMessageTests|PluginBluetoothStateTests"` — Expected: FAIL, `detail` and `PluginBluetoothAddress` undefined.
- [ ] **Step 3: Implement.** `PluginSurfaces.validate()` adds `detail == nil || widget != nil` with message "A detail opens from its feature's widget". `PluginBluetoothAddress.outputAddress` is `BluetoothAudioRouteSnapshot.bluetoothAddress(for:)` moved verbatim. Add `case .detail: break` to every exhaustive `PluginSurfaceKind` switch the compiler reports (router, kernel).
- [ ] **Step 4: Run** the same command plus `--filter "BluetoothAudioRouteTests|PluginKernelTests"` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Add the detail surface and the audio components to the plugin contract"`

### Task 3: Notch engine — the detail page

**Files:**
- Modify: `CascadeKit/Sources/CascadeKit/Core/Engine/NotchEngine.swift`, `CascadeKit/Sources/CascadeKit/Core/Engine/NotchDisplayCoordinator.swift`, `CascadeKit/Sources/CascadeKit/Core/Engine/NotchController.swift`, `CascadeKit/Sources/CascadeKit/Models/Engine/DisplayPresentation.swift`, `CascadeKit/Sources/CascadeKit/Core/Protocols/PluginSurfaceHosting.swift`
- Test: `CascadeKit/Tests/CascadeKitTests/NotchDisplayCoordinatorTests.swift`, `CascadeKit/Tests/CascadeKitTests/NotchControllerTests.swift`, `CascadeKit/Tests/CascadeKitTests/Support/RecordingSurfaceHost.swift`

**Interfaces:**
- Consumes: `NotchContextualPage` (existing) as the detail's content contract.
- Produces, on `NotchEngine` and on `PluginSurfaceHosting`:
  - `func showDetail(_ page: any NotchContextualPage, on displayID: CGDirectDisplayID?, onDismiss: @escaping @MainActor () -> Void)`
  - `func dismissDetail(id: String)`
  - `DisplayPresentation.detailPage: (any NotchContextualPage)?`

Behaviour (spec §2): the detail is drawn through the same path as a selected contextual page (`displayedContextualPage` returns the detail first) and takes precedence over the widget grid and the file shelf page while open, without changing their selection. One detail at a time: showing another calls the previous one's `onDismiss` and replaces it. The detail closes, calling `onDismiss` exactly once, on: `dismissDetail(id:)` with its id, Escape while it is shown, the notch collapsing on its display, its display being removed, and a new detail replacing it. Closing restores whatever was selected before. A page whose `contentHeight` is 196 renders at the controller's 240 pt maximum expanded height; Step 1 pins it so the constant is right.

- [ ] **Step 1: Write the failing tests** (in the suites' existing fixture styles)

```swift
@Test func detailReplacesTheGridAndRestoresItOnDismiss()
@Test func secondDetailDismissesTheFirstOnce()           // first onDismiss count == 1, second shown
@Test func collapsingTheNotchDismissesTheDetail()
@Test func removingTheDisplayDismissesTheDetail()
@Test func escapeDismissesTheDetail()
@Test func detailDoesNotDeselectTheFileShelfPage()     // contextual page stays selected after the detail closes
@Test func detailPageExpandsToTheMaximumHeight()       // controller's expanded height == configuration.maximumActivityExpandedHeight for contentHeight 196
```

- [ ] **Step 2: Run** `--filter "NotchDisplayCoordinatorTests|NotchControllerTests"` — Expected: FAIL, `showDetail` undefined.
- [ ] **Step 3: Implement.** The coordinator keeps `detail: (page, displayID, onDismiss)?` beside `contextualPage`; it never touches `expandedPageSelection`. Escape reuses the controller's existing key handling for the expanded surface. `RecordingSurfaceHost` records `shownDetails` and `dismissedDetailIDs`.
- [ ] **Step 4: Run** the same filter plus the whole `CascadeKitTests` target — Expected: PASS, no regression.
- [ ] **Step 5: Commit** `git commit -m "Let the notch show one detail page over its expanded surface"`

### Task 4: Audio state, model and gestures in CascadeKit

**Files:**
- Create: `CascadeKit/Sources/CascadeKit/Models/Audio/AudioOutputDevice.swift`, `.../Models/Audio/AudioOutputIcon.swift`, `.../Models/Audio/SystemAudioState.swift`, `.../Models/Audio/VolumeGesture.swift`, `.../Core/Audio/AudioMixerModel.swift`, `.../Core/Protocols/SystemAudioControlling.swift`
- Test: `CascadeKit/Tests/CascadeKitTests/AudioMixerModelTests.swift`, `CascadeKit/Tests/CascadeKitTests/VolumeGestureTests.swift`

**Interfaces:**
- Produces:

```swift
public struct AudioOutputDevice: Equatable, Hashable, Sendable {
    public let uid          : String
    public let name         : String
    public let transportType: UInt32          // kAudioDeviceTransportType*
    public let bluetooth    : AudioBluetoothIdentity?   // model/productID/colorID from the bluetooth source
}
public struct AudioBluetoothIdentity: Equatable, Hashable, Sendable {
    public let model: PluginBluetoothDeviceModel; public let productID: UInt16?; public let colorID: UInt8?
}
public enum AudioOutputIcon: Equatable, Sendable {
    case speaker(level: Int)                       // speaker.wave.1/2/3 for 1–33/34–66/67–100, speaker.fill at 0
    case muted                                     // speaker.slash.fill
    case bluetooth(AudioBluetoothIdentity)          // drawn by the bluetooth.device drawing
    case symbol(String)                            // laptopcomputer, display, tv, airplayaudio, headphones
    public static func resolve(output: AudioOutputDevice?, level: Double, isMuted: Bool) -> AudioOutputIcon
}
public struct SystemAudioState: Equatable, Sendable {
    public let level           : Double            // 0...1
    public let isMuted         : Bool
    public let supportsVolume  : Bool
    public let outputs         : [AudioOutputDevice]   // every output device, Cascade's aggregate excluded
    public let selectedUIDs    : [String]          // system output; several when the multi-output is active, clock first
    public let defaultDeviceID : UInt32            // HAL id the level belongs to
}
@MainActor public protocol SystemAudioControlling: AnyObject {
    func setLevel(_ level: Double, forDevice deviceID: UInt32)
    func setMuted(_ isMuted: Bool, forDevice deviceID: UInt32)
    func selectOutputs(_ uids: [String])            // one uid: plain default; several: multi-output, clock first
}
@MainActor @Observable public final class AudioMixerModel {
    public init(controller: any SystemAudioControlling)
    public private(set) var system: SystemAudioState?
    public private(set) var isAdjusting: Bool       // true during a drag or a scroll burst
    public var allowsSeveralOutputs: Bool           // the picker's toggle
    public func receive(_ state: SystemAudioState)  // from the service; ignored for `level` while adjusting the same device
    public func adjust(to level: Double)            // optimistic, clamps 0...1, coalesces: one controller call per frame
    public func endAdjusting()
    public func toggleMute()
    public func choose(outputUID: String)           // single mode: [uid]; several mode: toggles uid in selection, never empties it
}
public struct VolumeGesture: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable { case none, click, level(Double) }
    public init(startLevel: Double, travel: Double)          // travel = capsule height in points
    public mutating func move(to translation: CGSize, elapsed: Duration) -> Outcome
    public mutating func end(translation: CGSize, elapsed: Duration) -> Outcome
    public static func scrolled(_ level: Double, deltaY: Double, isPrecise: Bool) -> Double
}
```

Frame coalescing in `adjust`: keep the latest requested level and schedule one `DispatchQueue.main.async` flush when none is pending; the flush sends the latest value. That is one hop per burst, no timer.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func iconFollowsLevelBluetoothAndTransport() {
    #expect(AudioOutputIcon.resolve(output: builtIn, level: 0.5, isMuted: false) == .symbol("laptopcomputer"))
    #expect(AudioOutputIcon.resolve(output: airPods, level: 0.5, isMuted: false) == .bluetooth(airPodsIdentity))
    #expect(AudioOutputIcon.resolve(output: unknownUSB, level: 0.2, isMuted: false) == .speaker(level: 20))
    #expect(AudioOutputIcon.resolve(output: airPods, level: 0.5, isMuted: true) == .muted)
}
@Test func adjustingCoalescesToOneCommandWithTheLatestLevel() async  // 3 adjusts then a main-queue turn → controller.levels == [0.3]
@Test func serviceStateDoesNotFightAnOngoingDrag()                    // adjust(0.8); receive(level 0.2, same device) → system.level == 0.8
@Test func commandsCarryTheDeviceTheyWereMadeFor()                    // adjust on device 7; receive default 9; flush → nothing sent for 7 to 9 (Review Focus 3)
@Test func severalModeTogglesButNeverEmpties()                        // choose a, choose b → [a, b]; choose a → [b]; choose b → [b]
@Test func pressReleasedWithinSlopBeforeHoldIsAClick()               // end(.init(width: 1, height: 2), .milliseconds(200)) == .click
@Test func heldStillPressIsNeitherClickNorDrag()                     // end(.zero, .milliseconds(600)) == .none (Review Focus 4)
@Test func dragPastSlopMapsTravelToLevel()                           // start 0.5, travel 100: move(height -25) == .level(0.75); move(height +100) == .level(0.0), clamped
@Test func wheelStepsBySixteenthsAndTrackpadIsContinuous()           // scrolled(0.5, deltaY: 1, isPrecise: false) == 0.5625; scrolled(0.5, deltaY: 20, isPrecise: true) == 0.6
```

- [ ] **Step 2: Run** `--filter "AudioMixerModelTests|VolumeGestureTests"` — Expected: FAIL.
- [ ] **Step 3: Implement** the types above; drag is vertical and upward raises the level (`level = start - translation.height / travel`).
- [ ] **Step 4: Run** the same filter — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Model the audio widget's state, icon and gestures"`

### Task 5: Plugin detail routing and component services

**Files:**
- Create: `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginDetail.swift`, `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginComponentServices.swift`, `CascadeKit/Sources/CascadeKit/Components/Plugins/PluginDetailView.swift`
- Modify: `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginSurfaceRouter.swift`, `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginWidget.swift`, `CascadeKit/Sources/CascadeKit/Components/Plugins/PluginComponentView.swift`, `CascadeKit/Sources/CascadeKit/Resources/Localizable.xcstrings` ("Back")
- Test: `CascadeKit/Tests/CascadeKitTests/PluginSurfaceRouterTests.swift`

**Interfaces:**
- Consumes: `PluginSurfaceHosting.showDetail/dismissDetail` (Task 3), `PluginSurfaceKind.detail` (Task 2), `AudioMixerModel` (Task 4).
- Produces:
  - `@MainActor public final class PluginComponentServices { public init(audio: AudioMixerModel? = nil) ; public let audio: AudioMixerModel? }` — `AudioMixerModel` comes from Task 4.
  - `PluginSurfaceRouter.init(host:manifests:services:submit:visibility:)` with `services: PluginComponentServices = PluginComponentServices()`, so `PluginSystem`'s call site keeps compiling until Task 8.
  - SwiftUI environment values `\.pluginComponentServices: PluginComponentServices?` and `\.pluginOpenDetail: (@MainActor () -> Void)?`, set by `PluginWidget` / `PluginDetail` content views.
  - `final class PluginDetail: NotchContextualPage` with `id = "plugin-detail:" + plugin + "/" + feature`, `contentHeight = 196`, content `PluginDetailView`: a back button (`chevron.left`, label "Back") top-leading, then `PluginDocumentView(store:)`.

Behaviour: the router keeps a store per `.detail` publication but shows nothing until asked. A widget whose feature declares `detail` gets `openDetail`, which shows that feature's `PluginDetail` on the widget's display and calls `visibility(true, detailKey)`; its `onDismiss` calls `visibility(false, detailKey)`. A withdrawn detail publication while open dismisses it. Back calls `host.dismissDetail(id:)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func detailPublicationIsKeptButNotShown()                 // host.shownDetails is empty after routing a .detail change
@Test func openingTheWidgetsDetailShowsItAndReportsVisibility()  // shownDetails.count == 1; visibility log == [(true, detailKey)]
@Test func dismissingTheDetailReportsItHidden()                  // visibility log ends with (false, detailKey)
@Test func withdrawingAnOpenDetailDismissesIt()                  // dismissedDetailIDs == ["plugin-detail:com.example/feature"]
@Test func widgetWithoutDetailHasNoOpenAction()
```

- [ ] **Step 2: Run** `--filter PluginSurfaceRouterTests` — Expected: FAIL.
- [ ] **Step 3: Implement** as described; `PluginComponentView` reads `@Environment(\.pluginComponentServices)` and passes it to the audio components (Tasks 6 and 9).
- [ ] **Step 4: Run** `--filter "PluginSurfaceRouterTests|PluginNodeViewTests"` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Route plugin detail publications to the notch's detail page"`

### Task 6: The `audio.volumeBar` component

**Files:**
- Create: `CascadeKit/Sources/CascadeKit/Components/Plugins/Audio/AudioVolumeCapsule.swift`, `.../Audio/AudioVolumeBarComponent.swift`, `.../Audio/AudioOutputIconView.swift`, `.../Audio/ScrollWheelReader.swift`
- Modify: `CascadeKit/Sources/CascadeKit/Components/Plugins/PluginComponentView.swift` (identifiers gain `audio.volumeBar`, `audio.mixer`, `audio.outputPicker`; `case ("audio.volumeBar", 1)`)
- Test: `CascadeKit/Tests/CascadeKitTests/PluginNodeViewTests.swift`

**Interfaces:**
- Consumes: `AudioMixerModel`, `VolumeGesture`, `AudioOutputIcon` (Task 4); `\.pluginComponentServices`, `\.pluginOpenDetail` (Task 5); `PluginBluetoothDeviceComponent` (existing) for `.bluetooth`.
- Produces: `struct AudioVolumeCapsule: View` — `init(level: Double, isMuted: Bool, icon: AudioOutputIcon?, showsPercentage: Bool, onLevel: (Double) -> Void, onEnd: () -> Void, onClick: (() -> Void)?)`, reused by the mixer (Task 9); `struct ScrollWheelReader: NSViewRepresentable` — calls `onScroll(deltaY: Double, isPrecise: Bool, phase: NSEvent.Phase, momentum: NSEvent.Phase)` for scroll events over its frame only while it is in a window, installed as a local `.scrollWheel` monitor in `viewDidMoveToWindow` and removed when the window goes nil; its `hitTest` returns nil so clicks pass through.

Look (spec §2 table): capsule `RoundedRectangle(cornerRadius: width / 2)`, top fill `Color(white: 0.33)` with a 1 pt `white.opacity(0.12)` stroke, bottom fill white (grey `Color(white: 0.56)` when muted) whose height is `level`; icon 22 pt, 14 pt above the bottom, inside the fill; while `isAdjusting`, percentage `.monospacedDigit()` 10 pt from the top and the capsule scaled 1.05 with `.snappy`. With no model or no state, the unavailable look: empty capsule and the `speaker.slash` icon at half opacity. Accessibility: `.accessibilityElement()`, label "Global volume", value "\(percent)%", `.accessibilityAdjustableAction` ±1/16.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func volumeBarIsOfferedByTheKernel()   // PluginComponentView.identifiers ⊇ ["audio.volumeBar","audio.mixer","audio.outputPicker"]
@Test func volumeBarWithoutServicesDrawsTheUnavailableState() // rendering with services nil does not crash and exposes accessibility value "—"
@Test func volumeBarExposesAnAdjustableElement()               // hosting the bar with a model at 0.5 exposes label "Global volume", value "50%"
```

- [ ] **Step 2: Run** `--filter PluginNodeViewTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** The drag is a `DragGesture(minimumDistance: 0)` fed into `VolumeGesture`; it must be a `.simultaneousGesture` so the tile's own press still sees the hold. `.click` calls `pluginOpenDetail`; `.level` calls `model.adjust`; the end calls `model.endAdjusting()`. Scroll ignores events whose momentum phase is not empty.
- [ ] **Step 4: Run** the filter — Expected: PASS. Then run the app (`scripts/build-development.sh`) only after Task 8; this task has no visible entry point yet.
- [ ] **Step 5: Commit** `git commit -m "Draw the audio volume bar component"`

### Task 7: `SystemAudioService` in the app

**Files:**
- Create: `Cascade/Core/Audio/SystemAudioHardware.swift` (protocol), `Cascade/Core/Audio/CoreAudioSystemHardware.swift`, `Cascade/Core/Audio/SystemAudioService.swift`
- Modify: `Cascade/Core/Volume/CoreAudioSystemVolume.swift` (scalar set and mute set, aggregate sub-device controls)
- Test: `CascadeTests/SystemAudioServiceTests.swift`, `CascadeTests/Support/FakeSystemAudioHardware.swift`

**Interfaces:**
- Consumes: `SystemAudioState`, `AudioOutputDevice`, `SystemAudioControlling`, `AudioMixerModel` (Task 4); `PluginBluetoothAddress` (Task 2); `PluginBluetoothState` (existing).
- Produces:

```swift
protocol SystemAudioHardware: AnyObject, Sendable {          // every call on the service's serial queue
    func outputDevices() -> [AudioOutputDevice]               // bluetooth identity nil; the service fills it
    func defaultOutput() -> (deviceID: UInt32, uid: String)?
    func volume(of deviceID: UInt32) -> (level: Double, isMuted: Bool, supportsVolume: Bool)?
    func setVolume(_ level: Double, of deviceID: UInt32) -> Bool
    func setMuted(_ isMuted: Bool, of deviceID: UInt32) -> Bool
    func setDefaultOutput(uid: String) -> Bool
    func subDeviceUIDs(ofAggregate uid: String) -> [String]?  // nil when uid is not an aggregate
    func listen(_ onChange: @escaping @Sendable () -> Void)   // devices, default output, volume, mute of the default
    func stopListening()
}
@MainActor final class SystemAudioService: SystemAudioControlling {
    init(hardware: any SystemAudioHardware, queue: DispatchQueue)
    let model: AudioMixerModel
    func start()                     // listen + first snapshot; idempotent
    func stop()
    func receive(_ bluetooth: PluginBluetoothState)  // keeps the latest identity per deviceID, republishes
}
```

`CoreAudioSystemVolume` gains `setScalar(_ value: Double) -> Bool` and `setMuted(_ isMuted: Bool) -> Bool`, transactional like `perform`; when the default output is an aggregate whose UID starts with `cascade.multi-output.`, its controls are the sub-devices' controls, so `perform` (the key tap), `snapshot`, `setScalar` and `setMuted` act on every sub-device. `CoreAudioSystemHardware` uses `CoreAudioSystemVolume` for volume and mute and `OutputDeviceAccess`'s HAL code (moved, not duplicated) for devices and default output.

Snapshots are read on the queue and delivered to `model.receive` with one main-queue hop. A command whose `deviceID` differs from the current default is dropped on the queue.

- [ ] **Step 1: Write the failing tests** (fake hardware records calls and can fire `onChange`)

```swift
@Test func startPublishesTheDefaultOutputsLevelAndDevices()
@Test func defaultOutputSwitchUpdatesTheModelAndIcon()          // Review Focus 1: AirPods removed → model.system.selectedUIDs == ["BuiltInSpeakerDevice"]
@Test func staleDeviceCommandIsDropped()                         // Review Focus 3: setLevel(…, forDevice: 7) after default became 9 → fake.setVolumeCalls is empty
@Test func bluetoothIdentityIsAttachedByAddress()                // state deviceID "A0-…-F5" + output uid "a0-…-f5:output" → device.bluetooth.model == .airPodsPro
@Test func multiOutputAggregateIsHiddenFromOutputsAndExpandedToItsSubDevices() // default uid "cascade.multi-output.x" with subs [a,b] → outputs exclude it, selectedUIDs == [a,b]
@Test func noHardwareCallOnTheMainThread()                       // fake asserts !Thread.isMainThread on every call
```

- [ ] **Step 2: Run** `xcodebuild … -only-testing:CascadeTests/SystemAudioServiceTests test` — Expected: FAIL.
- [ ] **Step 3: Implement.** No `AudioObjectGetPropertyData` outside the queue. Listener blocks registered on the queue, removed in `stopListening`.
- [ ] **Step 4: Run** the suite plus `-only-testing:CascadeTests/VolumeChangeReducerTests` and any existing volume suites — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "Add the system audio service behind the volume bar"`

### Task 8: The `com.cascade.audio` plugin and its wiring

**Files:**
- Create: `CascadeKit/Sources/CascadePlugins/Core/Audio/AudioPlugin.swift`, `CascadeKit/Sources/CascadePlugins/Resources/com.cascade.audio.json`
- Modify: `CascadeKit/Sources/CascadePlugins/Core/FirstPartyPlugins.swift`, `CascadeKit/Sources/CascadePlugins/Resources/Plugins.xcstrings` (settings name "Volume widget" → "Widget volume", returned by `FirstPartyPlugins.name` for `com.cascade.audio`), `Cascade/Core/Plugins/PluginSystem.swift`, `Cascade/App/CascadeServices.swift`
- Test: `CascadeKit/Tests/CascadePluginsTests/AudioPluginTests.swift`, `CascadeKit/Tests/CascadePluginsTests/FirstPartyPluginsTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 5, 7.
- Produces: manifest

```json
{
  "manifestVersion": 2,
  "id": "com.cascade.audio",
  "version": "1.0.0",
  "compatibility": { "macOS": "15.0", "cascadeProtocol": { "major": 2, "minimumMinor": 0 } },
  "execution": { "entryPoint": "AudioPlugin" },
  "features": [
    {
      "id": "audio",
      "surfaces": { "widget": { "sizes": ["1x2"] }, "detail": {} },
      "services": ["audio.system"],
      "components": [
        { "id": "audio.volumeBar", "version": 1 },
        { "id": "audio.mixer", "version": 1 },
        { "id": "audio.outputPicker", "version": 1 }
      ]
    }
  ],
  "resources": { "profile": "eventDriven" }
}
```

`AudioPlugin.handle`: on `.refresh` it returns two publications — `.widget` with `Component(id: "audio.volumeBar", version: 1, parameters: [:])` filling its frame, `.detail` with `Component(id: "audio.mixer", version: 1, parameters: [:])` filling its frame; every other event returns an empty output. `audio.apps` and `audio.capture` are added to the manifest by Part B, when `AudioHost` exists. `PluginSystem.init` gains `services: Set<String>` passed to `PluginEngine(services:)` and `componentServices: PluginComponentServices` passed to the router; `CascadeServices` builds `SystemAudioService(hardware: CoreAudioSystemHardware(), queue: DispatchQueue(label: "cascade.system-audio", qos: .utility))`, passes `["audio.system"]` and `PluginComponentServices(audio: service.model)`, forwards the existing Bluetooth observation to `service.receive`, and starts/stops the service with `plugins.setEnabled` for `AudioPlugin.id` (enabled by default, same preference pattern as `volumeEnabled`, key `audioEnabled`).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func refreshPublishesTheBarAndTheMixer()       // output.publications.map(\.surface) == [.widget, .detail]
@Test func otherEventsPublishNothing()
@Test func bundledManifestsIncludeAudio()           // FirstPartyPlugins.manifests() contains "com.cascade.audio"; providers["AudioPlugin"] != nil
```

- [ ] **Step 2: Run** `--filter "AudioPluginTests|FirstPartyPluginsTests"` — Expected: FAIL.
- [ ] **Step 3: Implement** as above; `scripts/check-plugin-host-imports.sh` must still pass for `CascadePlugins`.
- [ ] **Step 4: Verify**
  - `--filter "AudioPluginTests|FirstPartyPluginsTests"` — PASS.
  - `swift run --package-path CascadeKit cascade-plugin validate CascadeKit/Sources/CascadePlugins/Resources/*.json` — every manifest valid.
  - `scripts/build-development.sh`, launch, add the Volume widget from the gallery: the bar shows the current level and the output icon; scroll and drag change the system volume (check with the menu bar volume); a click opens the detail with a back button (the mixer is empty until Task 9); a long press starts grid editing.
- [ ] **Step 5: Commit** `git commit -m "Ship the audio plugin's volume bar"`

### Task 9: The mixer and the output selector (global)

**Files:**
- Create: `CascadeKit/Sources/CascadeKit/Components/Plugins/Audio/AudioMixerComponent.swift`, `.../Audio/AudioOutputPicker.swift`
- Modify: `CascadeKit/Sources/CascadeKit/Components/Plugins/PluginComponentView.swift`, `CascadeKit/Sources/CascadeKit/Resources/Localizable.xcstrings` (keys from Global Constraints)
- Test: `CascadeKit/Tests/CascadeKitTests/AudioMixerComponentTests.swift`

**Interfaces:**
- Consumes: `AudioVolumeCapsule` (Task 6), `AudioMixerModel` (Task 4).
- Produces: `struct AudioMixerComponent: View` (`case ("audio.mixer", 1)`), `struct AudioOutputPicker: View` — `init(model: AudioMixerModel, onClose: () -> Void)`; the standalone `("audio.outputPicker", 1)` case draws the picker for the global output.

Layout (spec §2): leading column — percentage text, the global `AudioVolumeCapsule` 46 pt wide filling the height, a 20 pt round output button below whose icon is `AudioOutputIcon` (with a `+N` badge when `selectedUIDs.count > 1`) and a mute button; a 1 pt divider `Color(white: 0.2)`; then the apps area, which in this part shows the centred secondary text "Apps appear here when they play audio". The output button opens the picker in the apps area beside the global column: a header row "Several outputs" with a `Toggle` bound to `model.allowsSeveralOutputs`, then one row per `system.outputs` entry (icon, name, a checkmark in single mode or a checkbox in several mode), the current ones highlighted. Choosing in single mode closes the picker; in several mode it stays open. Escape or a click outside the picker closes it.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func mixerShowsTheEmptyAppsStateInThisPart()
@Test func pickerListsEveryOutputAndMarksTheSelection()    // 3 outputs, selected [b] → rows 3, checked [b]
@Test func singleModeChoiceSelectsAndCloses()              // tap row c → controller.selections == [["c"]], onClose called
@Test func severalModeChoiceTogglesAndStaysOpen()          // toggle on, tap c → [["b","c"]], onClose not called
```

- [ ] **Step 2: Run** `--filter AudioMixerComponentTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; test through the model and a recording `SystemAudioControlling`, not view introspection.
- [ ] **Step 4: Run** the filter — PASS. Build and run: the detail shows the global capsule and the picker; choosing a single output switches the system output.
- [ ] **Step 5: Commit** `git commit -m "Draw the mixer's global column and output selector"`

### Task 10: Global multi-output

**Files:**
- Modify: `Cascade/Core/Audio/SystemAudioHardware.swift`, `Cascade/Core/Audio/CoreAudioSystemHardware.swift`, `Cascade/Core/Audio/SystemAudioService.swift`, `Cascade/App/CascadeServices.swift` (quit path), `Cascade/App/AppDelegate.swift` (`applicationWillTerminate`)
- Test: `CascadeTests/SystemAudioServiceTests.swift`

**Interfaces:**
- Consumes: Task 1's answer (C) — whether a public aggregate outlives a killed creator; the launch cleanup below runs regardless.
- Produces, on `SystemAudioHardware`:
  - `func createMultiOutput(subDeviceUIDs: [String]) -> String?` (returns the new aggregate UID, `cascade.multi-output.<uuid>`)
  - `func destroyAggregate(uid: String) -> Bool`
  - `func aggregateUIDs(withPrefix prefix: String) -> [String]`
- On `SystemAudioService`: `func cleanUpLeftovers()` (called once in `start()`), `func restoreBeforeQuit()` (synchronous on the queue, bounded to 2 s, called from `applicationWillTerminate`).

Behaviour: `selectOutputs([a])` sets `a` as default; if a Cascade aggregate was default, it is destroyed after the switch. `selectOutputs([a, b, …])` creates the aggregate (clock = `a`), sets it as default, then destroys any previous Cascade aggregate. Removing all but one selection behaves as `selectOutputs([remaining])` (spec §2). A sub-device that disappears leaves the aggregate running on the rest; if only one remains, the service switches to it and destroys the aggregate. `restoreBeforeQuit` moves the default to the clock device and destroys the aggregate.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func severalOutputsCreateOneAggregateAndMakeItDefault()   // fake.created == [["a","b"]]; default == created uid
@Test func turningSeveralOffLeavesARealDeviceAndDestroysTheAggregate() // Review Focus 2
@Test func changingTheSetReplacesTheAggregate()                 // [a,b] → [a,b,c]: one created, previous destroyed after the switch
@Test func launchDestroysLeftoverCascadeAggregates()            // fake has "cascade.multi-output.old" → destroyed in start()
@Test func quitRestoresTheClockDevice()                         // Review Focus 2
@Test func losingAllButOneSubDeviceFallsBackToIt()
```

- [ ] **Step 2: Run** `-only-testing:CascadeTests/SystemAudioServiceTests` — Expected: FAIL.
- [ ] **Step 3: Implement** with `AudioHardwareCreateAggregateDevice` (keys from Global Constraints: `IsPrivate` false, `IsStacked` true, `MainSubDevice` and `ClockDevice` = first, `kAudioSubDeviceDriftCompensationKey` true on the others) and `AudioHardwareDestroyAggregateDevice`, both on the service queue.
- [ ] **Step 4: Verify**
  - The suite — PASS.
  - Manual, recorded in Task 11's note: select built-in speakers plus AirPods; both play; the bar shows the AirPods icon with `+1`; the volume keys change both; turning "Several outputs" off returns to one device; quit Cascade → Audio MIDI Setup shows no "Cascade Multi-Output"; `kill -9` Cascade while active, relaunch → the leftover is gone.
- [ ] **Step 5: Commit** `git commit -m "Play the system output on several devices at once"`

### Task 11: Documentation and Part A verification

**Files:**
- Modify: `docs/plugins/manifest.md` (the `detail` surface row and the "Today the host provides" sentence), `docs/plugins/content.md` (the catalog line and which components Cascade draws), `docs/plugins/services.md` (`audio.system` now exists as a kernel service; per-app stays planned), `CLAUDE.md` (plugin layer: the Audio plugin and the detail surface; pending list)
- Create: `docs/superpowers/verification/2026-10-09-audio-widget-part-a.md`

- [ ] **Step 1: Update the docs** so every statement about surfaces, components and services matches the code after Tasks 2–10.
- [ ] **Step 2: Write the verification note**: the manual checks of Tasks 8–10 with their observed results, and idle cost with the notch closed and the bar placed (Activity Monitor: Cascade CPU at rest unchanged within 0.1 % and no new idle wakeups compared with `main` on the same machine).
- [ ] **Step 3: Run** the full CascadeKit suite and the app test target — Expected: PASS.
- [ ] **Step 4: Commit** `git commit -m "Document the audio widget and the detail surface"`
