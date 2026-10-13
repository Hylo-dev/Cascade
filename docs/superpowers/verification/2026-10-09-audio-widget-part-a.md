# Audio widget, Part A: verification

Part A is the volume bar widget, the detail page with the global mixer, the `audio.system`
kernel service and the multi-output. Per-app volume (`AudioHost`, `audio.apps`,
`audio.capture`) is Part B and is not built. The design is
`docs/superpowers/specs/2026-10-09-audio-widget-design.md`; the lifecycle answers the
multi-output relies on are in `2026-10-09-audio-lifecycle-spike.md`.

## 1. Automated results

Run on branch `cava/audio-mixer`, Xcode-beta toolchain (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`).

| Command | Result |
| --- | --- |
| `swift test --package-path CascadeKit` | Two failures, listed below. Per target: 66 tests passed; CascadePluginsTests 51 tests, 1 issue; 7 passed; 163 passed; CascadeKitTests 461 tests, 1 issue; 99 passed. |
| `xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-audio-dd -only-testing:CascadeTests test` | `** TEST SUCCEEDED **`, Swift Testing: 82 tests in 7 suites passed. |
| `zsh scripts/test-volume.sh` | `Volume behavior tests: 43 passed` |
| `cascade-plugin validate CascadeKit/Sources/CascadePlugins/Resources/*.json` | All six manifests valid: audio, battery, bluetooth, clock, power, volume. |

The full `xcodebuild ... test` (without `-only-testing`) also runs `CascadeUITests`, which
launches the app; its runner reported "The test runner hung before establishing
connection" and executed 0 tests, so the unit tests were run on their own. The UI tests
were not checked.

Failures in the CascadeKit suite:

1. `BatteryPluginTests.theFaceShowsThePercentageAndTheStatus`: expects `"Low Power"` but
   the face shows `"Low Power Mode"`. Known and pre-existing, unrelated to the audio
   work, left as is.
2. `AudioMixerComponentTests.mixerWithoutAModelDrawsNothingButKeepsRendering`: expects 0
   drawn pixels and gets 6869. It passes alone, in pairs with each other test of its
   suite, and in the probe that renders `Color.clear`, `EmptyView` and
   `AudioMixerComponent()` in isolation (all 0). It fails every time the whole suite
   runs, with or without `--no-parallel`, so some combination of the suite's other
   renders leaves state behind; the component itself draws `Color.clear` without a
   model. This one is new on this branch (Task 8's tests) and is not fixed here.

## 2. Manual checks

Each item is for the controller to fill in with the user, on a real MacBook with the audio
widget placed on the grid.

### The bar (1x2 widget)

- [ ] The fill matches the system volume. pending: run with the user
- [ ] The icon follows the level and the mute, and the output change updates it (built-in, Bluetooth, display). pending: run with the user
- [ ] Scroll with the trackpad changes the level smoothly. pending: run with the user
- [ ] Scroll with a mouse wheel changes the level by steps. pending: run with the user
- [ ] Dragging on the bar sets the level. pending: run with the user
- [ ] A drag that leaves the notch does not collapse it, and ends cleanly on release. pending: run with the user
- [ ] A click opens the detail page. pending: run with the user
- [ ] A long press starts widget editing, not a click. pending: run with the user
- [ ] Changing the output in System Settings updates the icon and the level. pending: run with the user

### The mixer (detail page)

- [ ] The global capsule shows the level and the percentage, and follows a drag and a scroll as the bar does. pending: run with the user
- [ ] The mute button toggles the system mute, and the bar follows. pending: run with the user
- [ ] The output picker lists every output, marks the selected one, and a choice in single mode switches the system output and closes the picker. pending: run with the user
- [ ] In several mode, a choice toggles that device and the picker stays open; the `+N` badge counts the outputs beyond the first. pending: run with the user
- [ ] The apps area says "Apps appear here when they play audio". pending: run with the user

### The multi-output

- [ ] Choosing two devices creates the aggregate and both play the same audio. pending: run with the user
- [ ] The volume keys change the volume on both devices. pending: run with the user
- [ ] Turning several devices off, down to one, returns to a single real output. pending: run with the user
- [ ] Quitting Cascade leaves no aggregate device in Audio MIDI Setup. pending: run with the user
- [ ] `kill -9` on Cascade, then a relaunch, removes the leftover aggregate. pending: run with the user
- [ ] Switching the audio widget off while a multi-output is active restores a real output. pending: run with the user

### VoiceOver

- [ ] The bar's capsule is announced with its label and value, and adjustable with the up and down actions. pending: run with the user
- [ ] The mixer's capsule is announced and adjustable the same way. pending: run with the user

### Idle cost

- [ ] With the notch closed and the bar placed, Cascade's CPU at rest is unchanged within 0.1 % compared with `main` on the same machine (Activity Monitor). pending: run with the user
- [ ] No new idle wakeups compared with `main` (Activity Monitor, Idle Wake Ups). pending: run with the user

## 3. Known minor limitations

- A mouse wheel never shows the percentage on the bar; only a trackpad scroll and a drag do.
- The icon's ink flips at the edge of the fill, around 20 to 30 %, so the icon is briefly half in each color.
- A file drag over an open detail page selects the shelf underneath instead of the detail.
- Only a press on the capsule and on the empty apps area close the output picker; a press elsewhere on the page leaves it open.
