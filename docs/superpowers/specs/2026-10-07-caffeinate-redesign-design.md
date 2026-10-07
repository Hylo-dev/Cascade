# Cascade: Caffeinate, redesigned

Date: 7 October 2026. Status: implemented on branch `cava/caffeinate-redesign` (7 October 2026); see the plan's ledger rulings in the PR description. It replaces the Caffeinate widget, its options page and its native owner as they stand on `cava/widget-fullscreen`, and it routes plugin activities for the first time.

The UI follows Apple's Human Interface Guidelines (Live Activities, Steppers, Toggles, Color, Accessibility, Motion) and the Dynamic Island's design system: a key tint on black, a glyph leading, a value trailing, rounded tabular digits, a minimal presentation when the island is shared.

## 1. Why

The current Caffeinate works, but it is more machinery than the feature needs and less feature than the user wants.

- **Machinery.** A main-actor controller hops to an actor for every IOKit call and back through `Task`s, a `Timer` on the main run loop owns the deadline, and an `isBusy` state leaks into the UI as dimmed controls. Three power switches with different identities share one action, and `CaffeinateCommand` decodes node identities to tell them apart. Changing the duration of a running session releases and re-acquires the assertions.
- **Features.** Seven fixed durations, no way to see a session while the notch is closed, no way to start one without opening the notch.

### Success criteria

- A running session is visible with the notch closed, as a live activity, and its time left ticks without waking the plugin.
- Duration is any multiple of 15 minutes up to 24 hours, or indefinite, from one stepper.
- A global shortcut starts and stops a session without any permission prompt.
- At rest Caffeinate costs no armed timer, no awake thread and no main-thread work. During a session the only periodic work is the kernel's countdown: about one wake a minute above five minutes left, one a second below.
- Extending a running session never leaves a gap in which the Mac could sleep.
- No private code path: Caffeinate's activity goes through the same contract, kernel and router any plugin would use.

## 2. Decisions

| # | Decision |
|---|---|
| D1 | Start over on behaviour, UI and features. |
| D2 | In scope: flexible duration, a live activity, a global shortcut. Out of scope: automatic rules (apps, power, displays), App Intents, a menu item. |
| D3 | Plugin activity routing is built in this project; Caffeinate is its first client. No native activity for Caffeinate. |
| D4 | Duration is a stepper only, no presets. The scale is ∞, 15m, 30m … 24h in 15-minute steps; − from 15m reaches ∞. |
| D5 | Tapping the widget's disc or using the shortcut starts with the last duration used. |
| D6 | The shortcut is a global hot key, configurable or off in Settings, default ⌃⌥⌘C. |
| D7 | Keep display awake stays, as a global preference, on by default. |
| D8 | Compact activity: glyph leading, time left trailing as `2h` (≥ 1 h), `24m` (5–59 min), `4:59` (< 5 min), nothing for ∞. Every digit change rolls like Music's time labels. |
| D9 | The glyph is `cup.and.heat.waves.fill` by default; Settings offer `mug.fill`, `cup.and.heat.waves.fill` and `pill.fill`. |
| D10 | Expanded activity in the iOS Timer style: round **Stop** (tinted) and **＋15m** (grey, absent for ∞) leading, the large time trailing with "until 16:30"; for ∞ the large time counts up from the start, with "active for". |
| D11 | Widget: the disc is the switch, the text opens the options page. The options page has two rows: state and Start/Stop; stepper with end time and the display switch. |
| D12 | The activity keeps the 8-hour cap. Past it the activity ends, the session goes on, the widget stays the source of truth, and any user gesture on the session opens a new activity. |
| D13 | The native owner is one `nonisolated` class with a `Mutex`, a serial queue and one timer; no actor, no main-actor logic. |

## 3. Contract and state (`CascadeContracts`)

`PluginCaffeinateState` is the whole, immutable snapshot Cascade sends on the `caffeinate` source. It carries absolute values only, never a counter.

| Field | Type | Meaning |
|---|---|---|
| `startedAt` | `Date?` | `nil` means off. Also drives "active for" on an indefinite session. |
| `endsAt` | `Date?` | `nil` with `startedAt` set means indefinite. |
| `activityStartedAt` | `Date?` | Start of the current activity; every user gesture on the session renews it (D12). |
| `nextDuration` | `CaffeinateDuration` | The next session's length, which is the last one used. |
| `keepsDisplayAwake` | `Bool` | Global preference, default `true`. |
| `glyph` | `CaffeinateGlyph` | `.cupHeatWaves` (default), `.mug`, `.pill`. |
| `failure` | `CaffeinateFailure?` | Typed: `.assertionRefused(code)`, `.extensionRefused(code)`. The plugin localizes it. |

`CaffeinateDuration` is `.indefinite` or `.minutes(n)` with `n` a multiple of 15 in 15…1440. It owns the scale, `stepUp()` and `stepDown()`, so the plugin and the service share one definition. Decoding rejects anything off the scale.

Actions, declared in the manifest:

| Action | Effect |
|---|---|
| `caffeinate.start`, `caffeinate.stop` | Absolute. The disc and the pills are `Toggle`s carrying the value. |
| `caffeinate.extend` | ＋15 minutes on the current session's end. The only relative action; the broker's control revision drops a stale or repeated one. |
| `caffeinate.duration.down`, `caffeinate.duration.up` | While off, move `nextDuration` one step. While active, the stepper's value is the time left rounded up to the scale (∞ when indefinite); a step sets `endsAt = now + ` the neighbouring value, so − from 15m makes the session indefinite and + from ∞ makes it 15 minutes from now. `nextDuration` follows the stepped value. |
| `caffeinate.display` | Absolute toggle of the preference. |
| `caffeinate.options` | Opens the options page (existing). |

Removed: `isBusy`, `minutes`, the string `error`, `CaffeinateCommand` and node-identity decoding. One snapshot is published per transition: start, stop, extend, step, expiry, preference change. None while time passes.

## 4. `CaffeinateService` (app)

A `nonisolated final class`, `Sendable`, holding `Mutex<CaffeinateSession?>` and running on one serial `DispatchQueue` at `.utility`. Its seams are injected: `CaffeinateAssertions` (IOKit, or a fake), `CaffeinatePreferences` (`UserDefaults`), and a clock.

**A command.** The broker accepts an action, `PluginSystem.actionHandler` calls the service, which hops onto its queue; it decides the transition under the lock and copies, releases the lock, calls IOKit, records the outcome under the lock, then emits the snapshot. Nothing is called while the lock is held; the main thread is never involved.

**Assertions.** `PreventUserIdleSystemSleep` always; `PreventUserIdleDisplaySleep` too when `keepsDisplayAwake`. Both carry the IOKit timeout `endsAt − now` with `kIOPMAssertionTimeoutActionTurnOff`, so the Mac sleeps on time even if Cascade hangs or crashes, and the system drops them when the process exits.

- Extend, step and switching between timed and indefinite update the existing assertions' timeout with `IOPMAssertionSetProperty(kIOPMAssertionTimeoutKey)` (0 means none), so there is never an instant without an assertion. The spike of 7 October confirmed it: powerd honours the new timeout and measures it from the moment it is set (a 4-second assertion extended at second 2 to 10 seconds expired between seconds 11 and 14, its unextended twin at 4).
- Toggling the display preference during a session acquires or releases the display assertion alone.
- A refused acquisition leaves the previous state intact and publishes `failure`. A failed release keeps its identifier and is retried on the next stop and at expiry.

**Time.** One `DispatchSourceTimer` on a `wallDeadline` at `endsAt`, so it honours sleep and clock changes; at expiry it publishes off and releases the expired identifiers. With no timed session it is disarmed. `NSWorkspace.didWakeNotification` re-checks `endsAt` on wake.

**Lifecycle.** The `caffeinate` source is leased while the plugin is enabled. When the lease ends (the user disables the plugin, or the kernel quarantines it) the service stops the session: no orphaned assertion without UI. A session survives a PluginHost restart, since the service owns it and the kernel keeps the publication. Quitting Cascade waits on nothing.

**Preferences.** `nextDuration`, `keepsDisplayAwake`, `glyph` and the shortcut are read once at `init` and written only when they change.

**Shortcut.** `CaffeinateHotKey` registers with `RegisterEventHotKey` (Carbon): no Accessibility permission, no event monitor. Its handler arrives on main and only calls `service.toggle()`, a `queue.async`. Toggle starts with `nextDuration` or stops, and renews `activityStartedAt`.

At rest: no awake thread, no armed timer, one Carbon handler, one notification observer.

## 5. Plugin and UI (`CascadePlugins`)

`CaffeinatePlugin` stays `eventDriven`: no polling, no `wake`. It rebuilds its documents only when the snapshot changes and answers `refresh` with the last one. One feature, `awake`, on two surfaces.

### Widget

- **2x1.** A disc with the glyph (the start/stop `Toggle`) and a text block (the `Button` that opens the options page). Off: grey disc, outline glyph, "Caffeinate" over "1h 30m ›", the next duration. On: tinted disc, filled glyph, time left by the compact rules (D8), or "active for 1h 24m" when indefinite.
- **1x1.** The disc alone, still the switch.
- State is never colour alone: the glyph's fill and the text change too. Every control has an accessibility label ("Start Caffeinate", "Stop Caffeinate", "Caffeinate Options") and a spoken value ("24 minutes left").

### Options page

About 400 × 86 points below Cascade's Back control, two rows:

1. The disc, "Caffeinate" and the state in words: "Your Mac sleeps normally", "Awake until 16:30", "Awake until you stop it". Trailing, one prominent **Start** pill in the tint, or a neutral **Stop** pill.
2. The stepper `− 1h 30m +` with "until 16:30" beside it, and the "Keep display awake" switch trailing. The value is always visible next to the stepper; at the limits (∞, 24h) the matching button is disabled, not hidden. The kernel formats the end time in the user's locale.

### Live activity

Published only while a session runs and within the current activity's 8 hours; withdrawn when the session stops.

| Presentation | Content |
|---|---|
| Compact leading | The glyph in the tint. |
| Compact trailing | `Text(countdownTo: endsAt, style: .compact)`; empty for ∞. |
| Minimal | The glyph alone. |
| Expanded | Top: glyph and "Caffeinate". Leading: round **Stop** (tinted) and **＋15m** (grey, absent for ∞). Trailing: the large `Text(timerInterval:)` with "until 16:30", or for ∞ the elapsed time counting up with "active for". |

The key tint is amber `#FFC454` on black. Digits are SF Pro Rounded, tabular. At most two actions, both about the session. The glyph changes from outline to filled with `.symbolEffect`, `.identity` under Reduce Motion. Copy lives in `CaffeinateWidget.xcstrings` (English and Italian); the `h` and `m` units come from system formatting, not literals.

### Settings

In the widget's Settings section: a glyph picker previewing the three symbols, a shortcut recorder with a None button, and the Keep display awake switch. They write through the service, the single source of these values.

### Manifest

Feature `awake`: `surfaces` widget (`2x1`, `1x1`) and `activity`; source `caffeinate`; permission `power.keepAwake`; the actions of §3; `supportsFullscreen`.

## 6. Plugin activity routing (`CascadeContracts`, `CascadeKit`)

**Contract.** An activity follows the notice's existing idiom instead of a new document field. Its document's root is a `regions` node with **four** children, in this order: compact leading, compact trailing, minimal, expanded (a notice's has three). Its publication carries `PluginActivityAttributes` beside the document, as a notice carries `PluginNoticeAttributes`: `startedAt` (the start of the 8-hour lifetime), `relevance` (0…1) and `accessibilityLabel`. Attributes are required on, and only valid on, an `.activity` publication. The existing document limits apply. The plugin ends its activity by withdrawing the publication. Controls in the regions go through the broker like a widget's.

**Accepted actions carry their action.** Today the broker hands a native owner only the request (plugin, node, revision, value), which is why the old Caffeinate decoded node identities. `PluginEngine.submit`'s acceptance callback now also receives the `PluginActionEvent` the broker resolved (feature, action, value), and `PluginSystem.actionHandler` receives `(PluginPublicationKey, PluginActionEvent)`. Native owners switch on action names.

**Router.** `PluginSurfaceRouter.route(activity:)` creates, updates and removes a `PluginActivity` adapter that implements `NotchLiveActivity` as `PluginWidget` implements `NotchWidget`. It draws its roots with `PluginNodeView` from a `PluginNodeStore`, so a new publication touches only the nodes its diff names.

**Arbitration.** `LiveActivityHost`'s existing relevance and order, shared with `MediaLiveActivity`; no new rule. Caffeinate declares relevance 0.3, so playing music takes the compact and Caffeinate drops to minimal, as on the island.

**Visibility.** Compact and minimal are visible with the notch closed (plugin engine spec §5). Opening or closing the notch wakes no plugin.

**The 8-hour cap.** `PluginActivity.lifetime` is `NotchActivityLifetime(startedAt: attributes.startedAt)`, and `LiveActivityHost` already ends a live activity at its deadline; the kernel adds nothing. A gesture that renews `activityStartedAt` republishes with a new `startedAt`, which the host presents as a new lifetime.

## 7. Countdown node and rolling digits

**Node.** `PluginNodeKind.countdown(end: Date, style: .compact)`, built with `Text(countdownTo:style:)`, formats `2h`, `24m`, `4:59`, `0:00`: whole hours (floored) from one hour, whole minutes (floored) from five minutes, `m:ss` below, through the system's `Duration` formatting. Elapsed and large times reuse `.timer(start:end:countsDown:)`.

**Drawing.** A `TimelineView` with a custom `TimelineSchedule` that yields only the instants at which the text changes: hour or minute boundaries above five minutes, every second below. SwiftUI suspends the timeline while the view is not visible, so no timer of ours runs.

**Digits.** `MusicTimeLabelView` moves from `Cascade/Components/Music` into CascadeKit as `RollingDigitsLabelView` (font and colour now parameters, taken from the time node's own `.font` and `.foregroundStyle` modifiers): a push transition on the layers of the digits that changed, never `numericText` (measured at ~16 % of a core against ~0.2 %). The countdown node, the `.timer` node and Music all use it. Under Reduce Motion digits change in place.

## 8. Errors and edge cases

| Case | Behaviour |
|---|---|
| IOKit refuses at start | Stays off, publishes `failure`. The widget shows a warning glyph and "Couldn't prevent sleep"; the options page adds the code. Cleared by the next gesture. No activity. |
| Extension refused | The session and its end stay as they were; `failure` is published. The fallback never touches the old assertion before the new one exists. |
| Release fails | The identifier is kept and retried. Published state is off: the assertion has its own IOKit timeout. |
| Lid closed past the end | The wall-clock timer and the wake check end the session; nothing is replayed. |
| Clock or time zone change | `endsAt` is absolute; the end time redraws in the new locale, the time left stays right. |
| Past 8 hours | The activity is withdrawn, the session continues, the widget shows it; a gesture opens a new activity. |
| PluginHost restart | The session continues; the kernel keeps the publication; a `refresh` follows the restart. |
| Plugin disabled or quarantined | The lease ends, the service stops the session, the UI goes. |
| Late or repeated action | Start, stop, steps and display are absolute or idempotent; a stale extend is dropped by the broker's revision. |
| Stepper at a limit | The button is disabled; the service rejects an off-scale value anyway. |
| Shortcut taken | `RegisterEventHotKey` fails; Settings say "Shortcut unavailable"; no silent fallback. |
| Quit | Nothing waits on main; the system releases the process's assertions. |

## 9. Testing and verification

**Unit tests (Swift Testing, test first).**

- `CaffeinateServiceTests` with fake assertions, a test clock and in-memory preferences: start, stop, indefinite; extend and step without a gap; steps while off; display during a session; refused start and rollback; failed release retried; expiry and wake; lease end; shortcut toggle; no call made while the lock is held.
- `CaffeinateDurationTests`: the scale, steps and limits.
- `PluginCaffeinateStateTests`: event round trip, rejection of invalid fields.
- `CaffeinatePluginTests`: documents for off, timed, indefinite and failure; no publication for an unchanged snapshot; activity withdrawn when off; no ＋15m for indefinite; stable node identities across publications.
- Contract and kernel: activity regions and attributes validation; accepted actions carry their event; router create, update and remove of `PluginActivity`; arbitration against a native activity of higher relevance dropping Caffeinate to minimal.
- Countdown: schedule boundaries; `2h`, `24m`, `4:59`, `0:00` across locales.

**Manual, before merge.**

- `pmset -g assertions` through start, extend, step and display: the right assertions, the timeout updated, no gap.
- Instruments (Time Profiler, Energy Log): nothing at rest; about one wake a minute above five minutes; about 0.2 % of a core below.
- Compact, minimal and expanded with the notch closed and open, with Music playing, on an external display without a notch, with Reduce Motion and Increase Contrast, with VoiceOver.

**Delivery order.** Contract (state, duration, activity attributes, countdown node); accepted actions with their event; `CaffeinateService` and the shortcut; `RollingDigitsLabel` and the kernel countdown; activity routing; plugin and documents; Settings; docs (`content.md`, `manifest.md`, `README.md`); removal of the old controller, session, command and face.

## 10. Out of scope

Automatic rules, App Intents and a menu item; Music as a plugin and its tier-2 components; slot pages and layout arbitration beyond `LiveActivityHost`'s existing rules; external plugins.
