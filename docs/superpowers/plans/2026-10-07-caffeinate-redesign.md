# Caffeinate Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Caffeinate with a stepper-driven, hot-key-able keep-awake feature whose running session shows as the first plugin live activity, with kernel-drawn rolling countdowns.

**Architecture:** A `nonisolated` `CaffeinateService` in the app owns the IOKit assertions on one serial queue and publishes one `PluginCaffeinateState` snapshot per transition on the `caffeinate` source. `CaffeinatePlugin` turns each snapshot into a widget document (with options page) and an activity document (four regions). CascadeKit gains activity routing (`PluginActivity` adapter onto `LiveActivityHost`), a `countdown` node, and rolling digits shared with Music.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Core Animation, IOKit.pwr_mgt, Carbon hot keys, Synchronization (`Mutex`), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-07-caffeinate-redesign-design.md`

## Global Constraints

- Deployment floor macOS 15; no API newer than macOS 15 without an `@available` gate.
- No actors and no `Task` in `CascadePluginEngine`, `CascadePlugins`, `CascadePluginSDK`, nor in `CaffeinateService`. One `Mutex` per state owner; never call out (IOKit, emit, callbacks) while holding it.
- Code that the engine or the service calls off main in the app or CascadeKit is explicitly `nonisolated` (both default to MainActor).
- Never block or do IO on main. No per-frame allocation. No polling, no timer armed while nothing is due.
- `CascadePlugins` imports only `CascadePluginSDK`, `CascadeContracts`, Foundation, Synchronization (checked by `scripts/check-plugin-host-imports.sh`).
- Style per `CODE_STYLE.md`: Antirez-style `///` narrative comments on the why, explicit names, column alignment, multi-argument calls broken with the opening paren on its own line, one SwiftUI modifier per line, no `/* */`, no commented-out code.
- Key tint amber `PluginColor(red: 1, green: 0.77, blue: 0.33)` (`#FFC454`) on black; ink on amber `PluginColor(red: 0.15, green: 0.13, blue: 0.10)`.
- Duration scale: ∞, then 15…1440 minutes in steps of 15. IOKit timeout maximum 86 400 s.
- Glyphs: `cup.and.heat.waves.fill` (default), `mug.fill`, `pill.fill`; outline (off) variants `cup.and.heat.waves`, `mug`, `pill`.
- Compact countdown: `≥ 3600 s` → whole hours floored (`2h`); `300…3599 s` → whole minutes floored (`24m`); `0 < r < 300` → `m:ss` (`4:59`); `≤ 0` → `0:00`; formatted with `Duration` styles (`.units(allowed:[.hours]/[.minutes], width: .narrow)`, `.time(pattern: .minuteSecond)`).
- Activity relevance for Caffeinate: `0.3`. Live activity lifetime cap: `NotchActivityLifetime.maximumDuration` (8 h), enforced by `LiveActivityHost`.
- Copy in English and Italian in `CaffeinateWidget.xcstrings` (plugin) and `Localizable.xcstrings` (app, Settings).

**Commands.** The active developer dir is CommandLineTools, and SwiftPM bundles inside iCloud Drive fail codesign, so always:

- CascadeKit: `cd CascadeKit && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --scratch-path "$HOME/Library/Developer/CascadeKitBuild" --filter <SuiteName>`
- App tests: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Cascade.xcodeproj -scheme Cascade -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/CascadeDevelopment" -only-testing:CascadeTests/<SuiteName>`
- Full build: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer zsh scripts/build-development.sh`

Baseline before Task 1: every CascadeKit test passes except `BatteryPluginTests.theFaceShowsThePercentageAndTheStatus` (pre-existing, unrelated; leave it).

## Review Focus

1. **Lock discipline in `CaffeinateService`** — a command arriving while another is between "decide" and "record" must not double-acquire or leak an assertion. Test `concurrentCommandsNeverLeakAnAssertion` (Task 6).
2. **Expiry racing a user gesture** — the deadline timer firing just as the user taps ＋15m must leave either an extended session or a stopped one, never a published "on" with no assertion. Test `extendAfterExpiryDoesNothing` (Task 6).
3. **Countdown at the edges** — exactly 3600 s, 300 s, 0 s, negative, and an end in the past when the view appears. Test `compactTextAtBoundaries` and `scheduleIsEmptyForAPastEnd` (Task 3).
4. **Activity republished after the cap** — a new `startedAt` must present again after `LiveActivityHost` ended the old lifetime; an unchanged one must not re-present. Test `aRenewedStartPresentsAgain` (Task 5).
5. **Stepper while active near the floor** — 10 minutes left shows `15m`; − makes the session indefinite; + from ∞ ends 15 minutes from now. Test `stepWhileActiveUsesTimeLeftRoundedUp` (Task 6).

---

### Task 1: Caffeinate contract values

**Files:**
- Create: `CascadeKit/Sources/CascadeContracts/Models/PluginMessages/Enums/CaffeinateDuration.swift`, `.../Enums/CaffeinateGlyph.swift`, `.../Enums/CaffeinateFailure.swift`
- Rewrite: `CascadeKit/Sources/CascadeContracts/Models/PluginMessages/PluginCaffeinateState.swift`
- Retire the old feature so everything keeps compiling: replace `CascadePlugins/Core/Caffeinate/CaffeinatePlugin.swift` with a stub `CaffeinatePlugin` (same `id`, `feature = "awake"`, `handle` returns `try PluginOutput()`), delete `CaffeinateFace.swift` and `CascadeKit/Tests/CascadePluginsTests/CaffeinatePluginTests.swift`; delete the app's `CaffeinateController.swift`, `CaffeinateSession.swift`, `CaffeinateSessionSnapshot.swift`, `CaffeinateAssertionManaging.swift`, `CaffeinateFailure.swift`, `IOKitCaffeinateAssertions.swift`, `CaffeinatePluginSource.swift` and `CascadeTests/CaffeinateControllerTests.swift`; remove Caffeinate's wiring from `CascadeServices.swift` and `AppDelegate.swift` (source, action handler, shutdown wait). Leave the manifest as it is until Task 8.
- Test: `CascadeKit/Tests/CascadeContractsTests/CaffeinateStateTests.swift`

**Interfaces:**
- Produces:
  - `public enum CaffeinateDuration: Hashable, Sendable { case indefinite; case minutes(Int) }` with `static let step = 15`, `static let maximumMinutes = 1440`, `init?(wireMinutes: Int)` (0 → `.indefinite`, else a multiple of 15 in 15…1440), `var wireMinutes: Int`, `var seconds: TimeInterval?` (nil for ∞), `func steppedUp() -> CaffeinateDuration?` (nil at 1440; ∞ → 15), `func steppedDown() -> CaffeinateDuration?` (nil at ∞; 15 → ∞), `static func timeLeft(_ remaining: TimeInterval) -> CaffeinateDuration` (ceil to a multiple of 15, clamped 15…1440).
  - `public enum CaffeinateGlyph: String, CaseIterable, Sendable { case cupHeatWaves = "cup.and.heat.waves.fill", mug = "mug.fill", pill = "pill.fill" }` with `var filledSymbol: String` (raw value) and `var outlineSymbol: String`.
  - `public enum CaffeinateFailure: Equatable, Sendable { case assertionRefused(Int32); case extensionRefused(Int32) }`.
  - `public struct PluginCaffeinateState: Equatable, Sendable` with `static let source = "caffeinate"`, stored `startedAt: Date?`, `endsAt: Date?`, `activityStartedAt: Date?`, `nextDuration: CaffeinateDuration`, `keepsDisplayAwake: Bool`, `glyph: CaffeinateGlyph`, `failure: CaffeinateFailure?`; memberwise `public init` with defaults (`nil`, `nil`, `nil`, `.minutes(60)`, `true`, `.cupHeatWaves`, `nil`); `var isActive: Bool { startedAt != nil }`; `public init?(_ event: PluginSourceEvent)`; `public func event() throws -> PluginSourceEvent`.
  - Wire fields: `startedAt`, `endsAt`, `activityStartedAt` (`.number` epoch seconds, omitted when nil), `nextDuration` (`.number` wire minutes), `keepsDisplayAwake` (`.bool`), `glyph` (`.string` raw), `failure` (`.string` `"assertionRefused"`/`"extensionRefused"`) with `failureCode` (`.number`).

- [ ] **Step 1: Write the failing tests** — `CaffeinateStateTests`:
  - `durationScale`: `CaffeinateDuration.indefinite.steppedUp() == .minutes(15)`, `.minutes(15).steppedDown() == .indefinite`, `.indefinite.steppedDown() == nil`, `.minutes(1440).steppedUp() == nil`, `.minutes(45).steppedUp() == .minutes(60)`.
  - `wireMinutesRejectsOffScale`: `init(wireMinutes:)` nil for `-15, 10, 1455, 7`; `.indefinite` for 0.
  - `timeLeftRoundsUp`: `timeLeft(600) == .minutes(15)`, `timeLeft(901) == .minutes(30)`, `timeLeft(5400) == .minutes(90)`, `timeLeft(200_000) == .minutes(1440)`, `timeLeft(0) == .minutes(15)`.
  - `eventRoundTrip`: a state with every field set, and the default state, survive `event()` → `init?(_:)` unchanged (dates compared at second precision).
  - `eventRejectsInvalidFields`: unknown glyph string, `nextDuration` 7, `failure` without `failureCode`, non-finite `endsAt` → `nil`.
- [ ] **Step 2:** Run `--filter CaffeinateStateTests`; expect compile failure (types missing).
- [ ] **Step 3:** Implement the three enums and the new state (no `isBusy`, `minutes`, `error`), then retire the old feature as listed under Files.
- [ ] **Step 4:** Run `--filter CaffeinateStateTests`; expect PASS. Run the whole CascadeKit suite and `xcodebuild build` of the app; both must succeed (baseline Battery failure aside).
- [ ] **Step 5:** Commit `Model Caffeinate's state as absolute dates, a duration scale and a glyph`.

### Task 2: Activity publications

**Files:**
- Create: `CascadeKit/Sources/CascadeContracts/Models/PluginMessages/PluginActivityAttributes.swift`
- Modify: `PluginPublication.swift` (new `activity` field and rules), `CascadeContracts/Core/Extensions/PluginDocument+Validation.swift` (regions take 3 or 4 children), `CascadePluginSDK/Core/Builders/PluginViews.swift` (`Regions` doc comment: four for an activity)
- Test: `CascadeKit/Tests/CascadeContractsTests/PluginActivityPublicationTests.swift`

**Interfaces:**
- Produces: `public struct PluginActivityAttributes: Codable, Hashable, Sendable { startedAt: Date; relevance: Double; accessibilityLabel: String }`, throwing `init(startedAt:relevance:accessibilityLabel:)`, `relevance` in `0...1`, label non-empty ≤ 512 UTF-8 bytes, unknown keys rejected like `PluginNoticeAttributes`. `PluginPublication.init(feature:surface:document:staleAfter:notice:activity:)` with `activity: PluginActivityAttributes? = nil`.
- Rules in `PluginPublication.validate()`: with a document, `(surface == .activity) == (activity != nil)`; an activity's root is `.regions` with exactly 4 children; a notice's root is `.regions` with exactly 3; any other surface's root is not `.regions`. A withdrawal carries neither attributes.

- [ ] **Step 1: Failing tests:** `anActivityNeedsFourRegionsAndAttributes` (valid case passes; 3 regions throws; missing attributes throws), `attributesOnlyOnActivities` (widget with attributes throws), `noticesStillTakeThreeRegions`, `attributesValidateRange` (relevance 1.5 and empty label throw), `activityRoundTripsThroughJSON`.
- [ ] **Step 2:** Run `--filter PluginActivityPublicationTests`; expect FAIL.
- [ ] **Step 3:** Implement. Document-level validation only allows `regions` at depth 1 with 3 or 4 children; the surface-specific count lives in `PluginPublication`.
- [ ] **Step 4:** Run `--filter PluginActivityPublicationTests` and `--filter PluginDocumentTests`; expect PASS.
- [ ] **Step 5:** Commit `Let a plugin publish an activity as four regions with attributes`.

### Task 3: Countdown node and its formatting

**Files:**
- Create: `CascadeKit/Sources/CascadeContracts/Models/Nodes/Enums/PluginCountdownStyle.swift`, `CascadeKit/Sources/CascadeKit/Core/Time/CompactCountdown.swift`, `CascadeKit/Sources/CascadeKit/Core/Time/CompactCountdownSchedule.swift`
- Modify: `PluginNodeKind.swift` (`case countdown(end: Date, style: PluginCountdownStyle)`, name `"countdown"`, leaf), `PluginViews.swift` (SDK builder)
- Test: `CascadeKit/Tests/CascadeKitTests/CompactCountdownTests.swift`, a case in `CascadeKit/Tests/CascadeContractsTests/PluginDocumentTests.swift`

**Interfaces:**
- Produces: `public enum PluginCountdownStyle: String, Codable, Hashable, Sendable { case compact }`; SDK `public func Text(countdownTo end: Date, style: PluginCountdownStyle = .compact) -> PluginNode`; `nonisolated enum CompactCountdown { static func text(remaining: TimeInterval, locale: Locale = .current) -> String; static func nextChange(after now: Date, end: Date) -> Date? }`; `nonisolated struct CompactCountdownSchedule: TimelineSchedule { let end: Date }` whose entries start at the `from` date and then yield only `nextChange` instants, finishing after the one at `end`.

- [ ] **Step 1: Failing tests:**
  - `compactTextAtBoundaries` (locale `en_US`): `7200→"2h"`, `3600→"1h"`, `3599→"59m"`, `300→"5m"`, `299→"4:59"`, `61→"1:01"`, `0→"0:00"`, `-5→"0:00"`.
  - `nextChangeFollowsTheUnit`: end = now+7230 → next change at end−7200; end = now+400 → end−300; end = now+120.4 → end−120; end = now → nil.
  - `scheduleIsEmptyForAPastEnd`: entries after the first date are empty when `end < from`.
  - Contract: a document containing `Text(countdownTo: Date(timeIntervalSince1970: 1_800_000_000))` round-trips through JSON.
- [ ] **Step 2:** Run `--filter CompactCountdownTests`; expect FAIL.
- [ ] **Step 3:** Implement. `nextChange` uses whole-unit floors of `end − now`: hours above 3600, minutes from 300, seconds below. `text` uses `Duration.seconds(...).formatted(...)` per the Global Constraints.
- [ ] **Step 4:** Run `--filter CompactCountdownTests` and `--filter PluginDocumentTests`; expect PASS.
- [ ] **Step 5:** Commit `Add a kernel-drawn compact countdown node`.

### Task 4: Rolling digits for every kernel-drawn time

**Files:**
- Move and generalize: `Cascade/Components/Music/MusicTimeLabelView.swift` → `CascadeKit/Sources/CascadeKit/Components/Time/RollingDigitsLabelView.swift`; create `CascadeKit/Sources/CascadeKit/Components/Time/RollingDigitsLabel.swift`
- Modify: `Cascade/Components/Music/MusicTimeLabel.swift` (wrap `RollingDigitsLabel`), `CascadeKit/Sources/CascadeKit/Components/Plugins/PluginNodeContent.swift` (`.timer` and `.countdown`)
- Delete: `Cascade/Checks/Music/MusicTimeLabelChecks.swift`, `scripts/test-music-time-label.sh` (their checks move into the new unit tests)
- Test: `CascadeKit/Tests/CascadeKitTests/RollingDigitsLabelTests.swift`

**Interfaces:**
- Consumes: `CompactCountdown`, `CompactCountdownSchedule` (Task 3).
- Produces: `public final class RollingDigitsLabelView: NSView` with `init(font: NSFont, color: NSColor)` and `func show(_ text: String, countsDown: Bool, animates: Bool)`; `public struct RollingDigitsLabel: NSViewRepresentable { let text: String; let font: NSFont; let color: NSColor; let countsDown: Bool }` that animates unless `accessibilityReduceMotion`.
- Rendering: `.countdown(end, .compact)` → `TimelineView(CompactCountdownSchedule(end: end))` → `RollingDigitsLabel(text: CompactCountdown.text(remaining: end − context.date), countsDown: true)`. `.timer(start, end, countsDown)` → `TimelineView(.periodic(from: start, by: 1))` → `RollingDigitsLabel` with the system `h:mm:ss`/`m:ss` text it shows today. Font and colour come from the node's own `.font` and `.foregroundStyle(.color)` modifiers (convert with the existing `PluginFont`/`PluginColor` SwiftUI extensions, adding `NSFont`/`NSColor` conversions beside them), falling back to `NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)` and white.

- [ ] **Step 1: Failing tests** (port the assertions of `MusicTimeLabelChecks` and add): `onlyChangedDigitsRoll` (showing `"1:23"` then `"1:24"` adds a transition to the last glyph only), `aNewLengthRelaysWithoutAnimation`, `reduceMotionSetsTextInPlace` (`animates: false` adds no transition), `colorAndFontAreApplied`.
- [ ] **Step 2:** Run `--filter RollingDigitsLabelTests`; expect FAIL.
- [ ] **Step 3:** Move and generalize the view (font and colour parameters, `public`, comment updated), add the representable, switch Music's label to it, render the two node kinds as above.
- [ ] **Step 4:** Run `--filter RollingDigitsLabelTests` and `--filter PluginNodeStoreTests`; expect PASS. Build the app (`xcodebuild build ...`) to confirm Music still compiles.
- [ ] **Step 5:** Commit `Roll every kernel-drawn time's digits the way Music does`.

### Task 5: Accepted actions carry their event; plugin activities are routed

**Files:**
- Modify: `CascadeKit/Sources/CascadePluginEngine/Core/Engine/PluginEngine.swift` (`submit`), `.../Core/Kernel/PluginKernel.swift` (`submit` returns the resolved event to the engine), `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginSurfaceRouter.swift`, `CascadeKit/Sources/CascadeKit/Core/Protocols/PluginSurfaceHosting.swift`, `CascadeKit/Sources/CascadeKit/Core/Engine/NotchEngine.swift` and `NotchDisplayCoordinator.swift` (conformance), `Cascade/Core/Plugins/PluginSystem.swift`
- Create: `CascadeKit/Sources/CascadeKit/Core/Plugins/PluginActivity.swift`
- Test: `CascadeKit/Tests/CascadePluginEngineTests/PluginEngineTests.swift` (new case), `CascadeKit/Tests/CascadeKitTests/PluginActivityRoutingTests.swift`; update the recording hosts in `CascadeKit/Tests/CascadeKitTests/Support/` and `CascadeTests` to the new protocol requirement.

**Interfaces:**
- Consumes: `PluginActivityAttributes` (Task 2).
- Produces:
  - `PluginEngine.submit(_ request: PluginActionRequest, onAccepted: (@Sendable (PluginActionRequest, PluginActionEvent) -> Void)? = nil)`.
  - `PluginAcceptedAction` unchanged; the router's `submit`/`submitAccepted` closures forward the event: `submitAccepted: ((PluginActionRequest, @escaping (PluginActionEvent, @escaping @MainActor () -> Void) -> Void) -> Void)?` — implementer may restructure so long as the native effect receives the `PluginActionEvent`.
  - `PluginSystem.actionHandler: (PluginPublicationKey, PluginActionEvent) -> Void`, invoked on main for widget, options-page and activity controls alike.
  - `PluginSurfaceHosting.present(_ activity: any NotchLiveActivity)` (new requirement) and `endActivity(id: String)` (new requirement; `NotchEngine` already has both).
  - `final class PluginActivity: NotchLiveActivity` (`@MainActor`, internal) with `init(id: String, sourceID: String, store: PluginNodeStore, attributes: PluginActivityAttributes, visibility: @escaping (Bool) -> Void)`, `func update(_ attributes: PluginActivityAttributes)`, `lifetime = NotchActivityLifetime(startedAt: attributes.startedAt)`, `relevanceScore = attributes.relevance`, regions 0–2 via `PluginRegionView` like `PluginNotice`, `makeExpandedView` = region 3. Activation/suspension report visibility.
  - Router `route(activity:)`: first content → store + `PluginActivity` + `host.present`; later content → `store.apply`, `update(attributes)`, and `host.present` again **only if** `startedAt` changed; withdrawal → `host.endActivity(id:)` and drop store. Activity controls submit through the plain `submit` path (no options origin).

- [ ] **Step 1: Failing tests:** engine `acceptedActionCarriesItsEvent` (a button with action `"x.y"` yields an event with `action == "x.y"`); routing `anActivityIsPresentedWithItsFirstContent`, `anUpdateDoesNotPresentAgain`, `aRenewedStartPresentsAgain`, `aWithdrawalEndsTheActivity`, `theExpandedRegionIsTheFourth`, `activityControlsSubmitThroughTheBroker`.
- [ ] **Step 2:** Run `--filter PluginActivityRoutingTests` and `--filter PluginEngineTests`; expect FAIL.
- [ ] **Step 3:** Implement. Update the router's type doc (activities are now routed here, not by the Music sub-project). Fix `PluginSystem` to the new handler shape (its body may temporarily ignore the event until Task 8).
- [ ] **Step 4:** Run both filters plus `--filter PluginSurfaceRouter` and the whole `CascadePluginEngineTests`; expect PASS.
- [ ] **Step 5:** Commit `Route plugin activities and hand native owners the accepted action`.

### Task 6: `CaffeinateService`

**Files:**
- Create: `Cascade/Core/Caffeinate/CaffeinateService.swift`, `Cascade/Core/Caffeinate/CaffeinateAssertions.swift` (protocol + `IOKitCaffeinateAssertions`), `Cascade/Core/Caffeinate/CaffeinatePreferences.swift` (protocol + `UserDefaultsCaffeinatePreferences`), `Cascade/Core/Caffeinate/CaffeinateCommand.swift`, `Cascade/Core/Caffeinate/CaffeinatePluginSource.swift` (`nonisolated final class CaffeinatePluginSource: PluginEventSource`, `init(service:)`; `start` sets the service's emitter and emits the current state, `stop` sets it to nil)
- Test: `CascadeTests/CaffeinateServiceTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `nonisolated enum CaffeinateCommand: Equatable, Sendable { case start, stop, toggle, extend, stepUp, stepDown, setKeepsDisplayAwake(Bool), setGlyph(CaffeinateGlyph) }` , `static let plugin = PluginID(rawValue: "com.cascade.caffeinate")!`, and `init?(_ event: PluginActionEvent)` mapping by action name: `caffeinate.start` → `.start`, `caffeinate.stop` → `.stop` (the power `Toggle` carries whichever of the two matches the state it shows, so the value is not needed), `caffeinate.extend`, `caffeinate.duration.up`/`.down`, `caffeinate.display` → `.setKeepsDisplayAwake(value)` (bool value required). `.toggle` comes only from the shortcut.
  - `nonisolated protocol CaffeinateAssertions: Sendable { func acquire(_ kind: CaffeinateAssertionKind, timeout: TimeInterval?) throws(CaffeinateAssertionError) -> UInt32; func setTimeout(_ timeout: TimeInterval?, of identifier: UInt32) throws(CaffeinateAssertionError); func release(_ identifier: UInt32) throws(CaffeinateAssertionError) }` with `enum CaffeinateAssertionKind { case system, display }` and `struct CaffeinateAssertionError: Error { let code: Int32 }`. IOKit: `PreventUserIdleSystemSleep` / `PreventUserIdleDisplaySleep`, `kIOPMAssertionTimeoutActionTurnOff`, `IOPMAssertionSetProperty(id, kIOPMAssertionTimeoutKey, seconds)` with 0 for none.
  - `nonisolated protocol CaffeinatePreferences: Sendable` with get/set `nextDuration`, `keepsDisplayAwake`, `glyph`, `shortcut: CaffeinateShortcut?` (type from Task 7; declare it there and add the member in Task 7).
  - `nonisolated final class CaffeinateService: Sendable` with `init(assertions: any CaffeinateAssertions, preferences: any CaffeinatePreferences, now: @escaping @Sendable () -> Date = Date.init, queue: DispatchQueue = DispatchQueue(label: "Cascade.Caffeinate", qos: .utility))`, `func perform(_ command: CaffeinateCommand)` (async on the queue), `func setEmitter(_ emit: (@Sendable (PluginCaffeinateState) -> Void)?)` (nil = lease ended → stop the session), `var state: PluginCaffeinateState { get }` (under the lock), `func expire()` and `func systemDidWake()` (internal, for the timer and the wake observer), and for tests `func drain()` (`queue.sync {}`).
- Behaviour (each a test): start acquires system (+ display if preferred) with timeout = `nextDuration.seconds`, sets `startedAt`, `endsAt`, `activityStartedAt` = now; stop releases both and clears; extend sets both timeouts to `endsAt+900−now` and moves `endsAt` (no-op for ∞ or off); stepUp/stepDown off → change `nextDuration`; active → value `CaffeinateDuration.timeLeft(endsAt−now)` (or ∞), neighbour sets `endsAt = now + seconds` (∞ → nil, timeout none), and `nextDuration` follows; display toggle during a session acquires/releases only the display assertion; every user command renews `activityStartedAt`; a refused acquire keeps the previous state and sets `failure`; the next command clears `failure`; a failed release keeps the identifier and retries on the next stop or expiry; expiry publishes off; `systemDidWake` past `endsAt` publishes off; emitter set to nil stops the session; one emit per transition and none for a no-op. The deadline is one `DispatchSourceTimer` on `.wallDeadline`, cancelled whenever no timed session exists. The wake observer is `NSWorkspace.shared.notificationCenter` `didWakeNotification`, registered once in `init`.

- [ ] **Step 1: Failing tests** in `CaffeinateServiceTests` with a `FakeAssertions` (records acquire/setTimeout/release, can be told to fail, asserts no call happens while the service's lock is held by trying `state` from inside the call on another thread with a timeout) and in-memory preferences, one test per behaviour above, plus Review Focus tests `concurrentCommandsNeverLeakAnAssertion` (200 interleaved start/stop/extend from 4 threads end with acquires == releases + live) , `extendAfterExpiryDoesNothing`, `stepWhileActiveUsesTimeLeftRoundedUp` (10 min left → stepDown makes ∞; stepUp from ∞ → `endsAt == now+900`).
- [ ] **Step 2:** Run app tests `-only-testing:CascadeTests/CaffeinateServiceTests`; expect FAIL.
- [ ] **Step 3:** Implement: decide-under-lock → copy → unlock → IOKit → record-under-lock → emit. No `Task`, no actor, no MainActor.
- [ ] **Step 4:** Run the suite; expect PASS.
- [ ] **Step 5:** Commit `Own Caffeinate's assertions in one queue-bound service`.

### Task 7: Global shortcut

**Files:**
- Create: `Cascade/Core/Caffeinate/CaffeinateShortcut.swift` (value: `keyCode: UInt32`, `modifiers: UInt32` Carbon flags, `Codable`, `static let default` = ⌃⌥⌘C i.e. `kVK_ANSI_C` with `controlKey | optionKey | cmdKey`, `var displayString: String`), `Cascade/Core/Caffeinate/CaffeinateHotKey.swift`
- Modify: `CaffeinatePreferences` (+ `shortcut`, default `.default`; `nil` = off)
- Test: `CascadeTests/CaffeinateShortcutTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CaffeinateHotKey` with `init(onPress: @escaping @MainActor () -> Void)`, `@discardableResult func register(_ shortcut: CaffeinateShortcut?) -> Bool` (unregisters the previous one; `false` when `RegisterEventHotKey` fails, e.g. taken), `deinit` unregisters and removes the handler. One `InstallEventHandler` on the application event target for `kEventHotKeyPressed`.

- [ ] **Step 1: Failing tests:** `defaultIsControlOptionCommandC`, `displayStringUsesSymbols` (`"⌃⌥⌘C"`), `shortcutRoundTripsThroughCodable`, `registeringNilUnregisters` (returns `true`, no handler call).
- [ ] **Step 2:** Run `-only-testing:CascadeTests/CaffeinateShortcutTests`; expect FAIL.
- [ ] **Step 3:** Implement with Carbon (`import Carbon.HIToolbox`); the handler only calls `onPress`.
- [ ] **Step 4:** Run; expect PASS.
- [ ] **Step 5:** Commit `Add Caffeinate's global shortcut`.

### Task 8: Plugin documents, manifest, wiring and Settings

**Files:**
- Rewrite: `CascadeKit/Sources/CascadePlugins/Core/Caffeinate/CaffeinatePlugin.swift`, `.../CaffeinateFace.swift`; split the activity into `.../CaffeinateActivityFace.swift` and the options page into `.../CaffeinateOptionsFace.swift` if the face file passes ~300 lines
- Rewrite: `CascadeKit/Sources/CascadePlugins/Resources/com.cascade.caffeinate.json`, `CaffeinateWidget.xcstrings`
- Modify: `Cascade/App/CascadeServices.swift`, `Cascade/App/AppDelegate.swift` (remove the old shutdown wait), `Cascade/Views/Settings/CascadeSettingsView.swift` and the `CascadeSetting` enum (new section "Caffeinate": glyph picker, shortcut recorder, keep display awake), `Cascade/Resources/Localizable.xcstrings` (or the app's string catalog)
- Create: `Cascade/Views/Settings/CaffeinateShortcutRecorder.swift`
- Test: rewrite `CascadeKit/Tests/CascadePluginsTests/CaffeinatePluginTests.swift`; update `FirstPartyPluginsTests` expectations

**Interfaces:**
- Consumes: Tasks 1–7.
- Manifest feature `awake`: `"surfaces": { "widget": { "sizes": ["2x1", "1x1"] }, "activity": {} }`, `"sources": ["caffeinate"]`, `"permissions": ["power.keepAwake"]`, `"actions": ["caffeinate.start", "caffeinate.stop", "caffeinate.extend", "caffeinate.duration.up", "caffeinate.duration.down", "caffeinate.display", "caffeinate.options"]`, `"supportsFullscreen": true`.
- Plugin: on a `.source` event, publish the widget document (always) and the activity (document while `isActive`, withdrawal when not, only when that changes or its content changes); `refresh` republishes the last; `.action` events return an empty output; never a `wake`. Activity attributes: `startedAt = activityStartedAt`, `relevance = 0.3`, label "Caffeinate, 24 minutes left" / "Caffeinate, active until you stop it".
- Faces (spec §5): power control is one `Toggle(isOn: isActive, action: isActive ? "caffeinate.stop" : "caffeinate.start")` per placement with stable explicit ids `power.large`, `power.small`, `power.options`, `power.activity`; extend `Button` id `extend`; stepper `Button`s `duration.down`/`duration.up` with `.opacity(0.35)` and no action effect at the limits (a disabled look: they stay buttons; the service ignores off-scale); display `Toggle` id `display`; opener `Button` id `options`. Glyph from `state.glyph` (filled when active, outline when off) with `.contentTransition(.symbolEffect)`. Compact trailing `Text(countdownTo:)` with `.font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())` and amber; empty `Spacer` for ∞. Expanded large time `.font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())`: `Text(timerInterval: now...endsAt)` counting down with "until" + `Text(endsAt, style: .time)`, or for ∞ `Text(timerInterval: startedAt...startedAt+86_400, countsDown: false)` with "active for".
- Wiring (re-adding what Task 1 removed): `CascadeServices` builds `CaffeinateService(assertions: IOKitCaffeinateAssertions(), preferences: UserDefaultsCaffeinatePreferences())`, passes `CaffeinatePluginSource(service:)` under `PluginCaffeinateState.source`, sets `plugins.actionHandler = { key, event in guard key.plugin == CaffeinateCommand.plugin, let command = CaffeinateCommand(event) else { return }; service.perform(command) }`, owns `CaffeinateHotKey(onPress: { service.perform(.toggle) })`, and exposes `@Observable` properties `caffeinateGlyph`, `caffeinateKeepsDisplayAwake`, `caffeinateShortcut` (+ `caffeinateShortcutUnavailable: Bool`) that forward to the service/hot key. Remove `needsResourceShutdown`/`shutdown` plumbing for Caffeinate.
- Settings recorder: a button showing `displayString` or "None"; while recording, `.onKeyPress` captures the next key with at least one of ⌘⌃⌥; Esc cancels; a "Clear" button sets `nil`. Shows "Shortcut unavailable" under it when registration failed.

- [ ] **Step 1: Failing tests** (`CaffeinatePluginTests`): `offPublishesTheWidgetAndNoActivity`, `onPublishesBothAndTheActivityHasFourRegions`, `stoppingWithdrawsTheActivity`, `noPublicationForAnUnchangedState`, `indefiniteHasNoExtendAndCountsUp`, `timedCompactUsesTheCountdownNode`, `controlsKeepStableIdentitiesAcrossStates`, `glyphFollowsThePreference` (filled vs outline), `everyControlActionIsDeclared` (each `button`/`toggle` action ∈ manifest actions), `noWakeEver`, `activityAttributesCarryTheRenewedStart`.
- [ ] **Step 2:** Run `--filter CaffeinatePluginTests`; expect FAIL.
- [ ] **Step 3:** Implement plugin, faces, manifest, strings (EN + IT); then the app wiring, Settings and recorder. Run `swift run --package-path CascadeKit cascade-plugin validate CascadeKit/Sources/CascadePlugins/Resources/*.json` (with the `DEVELOPER_DIR` and `--scratch-path` above).
- [ ] **Step 4:** Run the whole CascadeKit suite and `-only-testing:CascadeTests`; expect PASS except the baseline Battery failure. Run `zsh scripts/build-development.sh`; expect success.
- [ ] **Step 5:** Commit `Rebuild Caffeinate as a stepper widget with a live activity and a shortcut`.

### Task 9: Docs and final verification

**Files:**
- Modify: `docs/plugins/content.md` (countdown node; rolling digits; activity regions), `docs/plugins/manifest.md` (activity surface now routed), `docs/plugins/README.md` (remove "plugin activities are accepted but not shown"), `CLAUDE.md` (Caffeinate line: options page, activity, shortcut; no longer "Music, until …" contradiction), spec status line (implemented)

- [ ] **Step 1:** Update the docs.
- [ ] **Step 2:** Manual checks (report each result): `pmset -g assertions` through start, ＋15m, stepper, display toggle, stop; compact/minimal/expanded with the notch closed and open, with Music playing; ⌃⌥⌘C start/stop; Reduce Motion; VoiceOver labels; Instruments idle check (no Cascade wakes from Caffeinate at rest).
- [ ] **Step 3:** Per `AGENTS.md`: build, update `/Applications/Cascade.app`, quit and relaunch Cascade, confirm it runs.
- [ ] **Step 4:** Commit `Document the Caffeinate redesign and plugin activities`.
