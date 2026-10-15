# Caffeinate Ruler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace Caffeinate's − / + stepper with a kernel-drawn ruler and a `For | Until | ∞` selector (∞ default), with the Display and Start buttons on the right.

**Architecture:** The `slider` node gains a `ruler` style drawn by the kernel (one `Canvas`, drag handled natively, one action on release). The service's `nextDuration` becomes `nextTarget` (`indefinite | duration | until`) with absolute set/mode actions. The plugin redraws the options page in layout A.

**Spec:** `docs/superpowers/specs/2026-10-07-caffeinate-redesign-design.md` §11 (binding), with §1–§10 where §11 is silent.

## Global Constraints

- macOS 15 floor; Swift 6; `CODE_STYLE.md` (Antirez `///` comments, column alignment, multi-argument calls broken with the opening paren on its own line, one SwiftUI modifier per line); `CLAUDE.md` resource rules (no idle wakes, no per-frame allocation outside the drawn ticks, main never blocks).
- No actors / `Task` in `CascadeContracts`, `CascadePluginSDK`, `CascadePlugins`, `CaffeinateService`; one `Mutex` per owner; never call out holding it.
- Ruler: 15-minute ticks, a label every 4 ticks (every hour); ticks bottom-aligned; passed ticks full tint, upcoming ticks at 0.28 alpha; height and alpha fall with distance from the centre indicator (centre: full height, full alpha; edge: about 45 % height, alpha → 0); a filled ▲ under the centre; tint = the node's own `foregroundStyle` colour (fallback white). Reduce Motion: no snapping animation.
- Duration range 15…1440 minutes; Until range: next quarter hour ≥ now + 15 min … now + 24 h; values are multiples of 15 minutes.
- Default target ∞. EN/IT strings: "For"/"Per", "Until"/"Fino a", "Until you stop it"/"Finché non lo fermi", "until %@"/"fino alle %@" (status line, kernel time where possible).
- Commands — CascadeKit: `cd CascadeKit && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --scratch-path "$HOME/Library/Developer/CascadeKitBuild" --filter <Suite>`; app: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Cascade.xcodeproj -scheme Cascade -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/CascadeDevelopment" -only-testing:CascadeTests/<Suite>` (run outside the sandbox if it hangs); build: `zsh scripts/build-development.sh` with the same `DEVELOPER_DIR`. Known pre-existing failure: `BatteryPluginTests.theFaceShowsThePercentageAndTheStatus`.

---

### Task 1: The ruler slider style (contract, SDK, kernel)

**Files:** `CascadeKit/Sources/CascadeContracts/Models/Nodes/PluginNodeKind.swift` (slider gains `style: PluginSliderStyle`, default `.standard`, decoding absent as standard), new `.../Nodes/Enums/PluginSliderStyle.swift` (`standard`, `ruler(labelEvery: Int, labels: PluginRulerLabels)`; `PluginRulerLabels`: `duration`, `clockTime`), validation (labelEvery 1…96; for `ruler` a `step` is required and `(max − min) / step` ≤ 2048), `CascadePluginSDK` builder (`Slider(value:in:step:style:action:)` with `style` defaulted), every exhaustive `switch` over slider kinds, `CascadeKit/Sources/CascadeKit/Components/Plugins/PluginNodeContent.swift` (render `ruler` with a new `PluginRulerSlider` view in `Components/Plugins/`), docs `docs/plugins/content.md`.

**Interfaces produced:** `PluginSliderStyle`, `PluginRulerLabels`; SDK `Slider(value: Double, in: ClosedRange<Double>, step: Double?, style: PluginSliderStyle = .standard, action: String)`; `PluginRulerSlider` drawing per the Global Constraints, using the existing slider plumbing (`thumb` binding / `store.drag` / release → one action), snapping to `step` on release.

- [ ] Tests first: contract round trip and validation (`labelEvery` 0 and 97 rejected; ruler without step rejected; absent style decodes standard); a pure geometry helper `RulerGeometry` (in `Core/Plugins/` or `Core/Time/`, `nonisolated`) with `ticks(value:min:max:step:width:spacing:) -> [RulerTick]` (offset, heightFraction, alpha, isPassed, labelIndex) — tests: centre tick full height/alpha, symmetric falloff, edge alpha ≈ 0, passed = value ≥ tick, ticks outside min/max omitted, at most ⌈width / spacing⌉ + 2 ticks; label text helper (`duration`: 60 → "1h", 90 → "1h 30m"; `clockTime`: formatted `.time` short in the given locale).
- [ ] Implement; the view draws only the visible ticks from `RulerGeometry`, label every `labelEvery`, ▲ indicator; drag with `DragGesture(minimumDistance: 0)`, horizontal translation / tick spacing → value; accessibility adjustable (increment/decrement by `step`, value = label text).
- [ ] Run focused suites + whole CascadeKit suite; commit "Draw a ruler slider in the kernel".

### Task 2: Targets and absolute actions (contract + service)

**Files:** `CascadeKit/Sources/CascadeContracts/Models/PluginMessages/PluginCaffeinateState.swift` + new `Enums/CaffeinateTarget.swift`; `Cascade/Core/Caffeinate/CaffeinateService.swift`, `CaffeinateCommand.swift`, `CaffeinatePreferences.swift`; tests `CascadeKit/Tests/CascadeContractsTests/CaffeinateStateTests.swift`, `CascadeTests/CaffeinateServiceTests.swift`.

**Interfaces produced:** `CaffeinateTarget: Hashable, Sendable { case indefinite; case duration(minutes: Int); case until(minuteOfDay: Int) }` with validation (duration 15…1440 multiple of 15; minuteOfDay 0…1425 multiple of 15) and `func end(startingAt: Date, calendar: Calendar) -> Date?` (nil for indefinite; until → next occurrence at least 15 min after start, in the calendar's time zone). `PluginCaffeinateState.nextTarget` replaces `nextDuration` (wire: `targetKind` "indefinite"/"duration"/"until" + `targetValue` number). Commands: `.setMode(CaffeinateTargetKind)`, `.setDuration(minutes:)`, `.setUntil(Date)` replacing `stepUp/stepDown`; actions `caffeinate.mode.indefinite|duration|until`, `caffeinate.duration.set` (number = minutes), `caffeinate.until.set` (number = seconds since 1970). Preferences persist the target (default `.indefinite`); remember the last duration and the last until so switching mode restores them (defaults 60 minutes and the next full hour).

- [ ] Tests first (service): start uses the target; mode switches while off/on per spec §11; `setDuration` while running moves the end (timeout updated, no release); `setUntil` in the past or > 24 h ahead is ignored with no emit; `.until` across midnight; DST-safe via injected calendar/time zone; preference round trip; lease/permission gates unchanged.
- [ ] Implement; remove step code; keep all existing guarantees (no gap, no call under lock).
- [ ] Run suites; commit "Let a Caffeinate session run for a while, until a time, or until stopped".

### Task 3: The options page in layout A, widget status, manifest

**Files:** `CascadeKit/Sources/CascadePlugins/Core/Caffeinate/*`, `com.cascade.caffeinate.json` (actions: start, stop, display, options, mode.indefinite, mode.duration, mode.until, duration.set, until.set), `CaffeinateWidget.xcstrings`, `CaffeinatePluginTests`, `FirstPartyPluginsTests`, `CascadeTests/CaffeinateFaceFitTests.swift`, spec §11 if details change, `CLAUDE.md` Caffeinate sentence (stepper → ruler).

- [ ] Options page (≈400×86): top band — a three-segment selector built from three `Button`s (ids `mode.duration`, `mode.until`, `mode.indefinite`; selected segment filled, accessibility labels "For", "Until", "Until you stop it" + selected state in the label) leading; round Display toggle (id `display`) and round power toggle (id `power.options`, amber play off / grey stop on) trailing. Bottom band — the ruler (`Slider(... style: .ruler(labelEvery: 4, labels: .duration|.clockTime))`, id `ruler`, amber, `caffeinate.duration.set` / `caffeinate.until.set`) across most of the width; trailing large time (26 pt rounded monospaced, own font/colour on time nodes): off — "1h 30m" / kernel `Text(date, style: .time)` of the until time / "∞"; running — countdown `Text(timerInterval:)` (For/Until) or elapsed (∞). With ∞ the ruler is replaced by "Until you stop it". Ruler value: off → the target's value; running For → minutes left rounded up to 15 (min 15); running Until → the session's end.
- [ ] Widget faces' status line by target: "∞ ›" / "1h 30m ›" / "until 18:00 ›" (kernel time), running unchanged.
- [ ] Tests: structure, ids, every action in the manifest, ruler style/labels per mode, ∞ hides the ruler, fit ≤ 400×86, strings EN+IT.
- [ ] Run suites + build; commit "Choose Caffeinate's session on a ruler".
