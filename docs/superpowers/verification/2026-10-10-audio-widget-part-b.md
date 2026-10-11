# Audio widget, Part B: verification

Part B is per-app audio: `AudioHost`, the XPC service that runs one process tap, private
aggregate and render kernel per controlled app; the reconciler that decides what to build;
the supervision (3 s command deadline, 64 MiB, given up after three faults in five minutes,
a Settings row with Restart); the stored intents; and the mixer's app columns with the
per-app output picker and its "Follow system" entry. The design is
`docs/superpowers/specs/2026-10-09-audio-widget-design.md`, with the amendments of 10 and 11
October. Part A is verified in `2026-10-09-audio-widget-part-a.md`; the spikes Part B relies
on are `2026-10-09-audio-lifecycle-spike.md` (answered) and
`2026-10-10-audio-tap-permission-spike.md` (the permission runs P1 to P4 are still pending).

## 1. Automated results

Run on branch `cava/audio-mixer`, Xcode (`/Applications/Xcode.app`) at HEAD `82bdff1` (the
three final review fixes) plus the documentation changes of this task.

| Command | Result |
| --- | --- |
| `swift test --package-path CascadeKit` | One failure, the known one listed below. Per target, Swift Testing: CascadeRuntimeTests 66 tests passed; CascadePluginsTests 52 tests, 1 issue; CascadePluginToolTests 7 passed; CascadePluginEngineTests 163 passed; CascadeKitTests 508 passed; CascadeContractsTests 110 passed; CascadeAudioHostTests 111 passed (including `AudioRenderKernelTests`, `AudioReconcilerTests` and `AudioProcessGroupingTests`). |
| `CASCADE_APPLICATIONS_DIRECTORY=/private/tmp/cascade-audio-apps xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-audio-dd -only-testing:CascadeTests test` | `** TEST SUCCEEDED **`, Swift Testing: 105 tests in 9 suites passed. |

The full `xcodebuild ... test` (without `-only-testing`) also runs `CascadeUITests`, which
launches the app; it was not run, so the UI tests were not checked.

Failure in the CascadeKit package suite:

1. `BatteryPluginTests.theFaceShowsThePercentageAndTheStatus`: expects `"Low Power"` but the
   face shows `"Low Power Mode"`. Known and pre-existing, unrelated to the audio work, left as
   is.

`AudioMixerComponentTests.mixerWithoutAModelDrawsNothingButKeepsRendering`, which failed in
Part A's full run, passed in this one.

## 2. Manual checks

Each item is for the controller to fill in with the user, on a real MacBook with the audio
widget placed on the grid and System Audio Recording allowed for Cascade.

### Per-app volume and mute

- [ ] YouTube playing in Safari and in Chrome appears as one column per browser, not one per helper process. pending: run with the user
- [ ] Setting an app to 25 % audibly lowers only that app, and the global volume is unchanged. pending: run with the user
- [ ] Muting an app silences it at once and un-muting restores it at its gain, with no click. pending: run with the user
- [ ] An app returned to 100 %, unmuted and following the system leaves no tap behind (it plays on the native path). pending: run with the user

### Findings on real browsers

- Safari plays through `com.apple.WebKit.GPU`, whose executable lives in a system cryptex with no `.app` in its path. The path rule alone listed it as a column named `com.apple.WebKit.GPU` with no icon. It is now resolved through the responsible process (`responsibility_get_pid_responsible_for_pid`, a private libsystem SPI resolved dynamically; when absent the process keeps its own bundle ID): measured, that process is responsible to `Safari.app`, Brave's helpers to `Brave Browser.app`, and a WebKit GPU process serving `WebThumbnailExtension.appex` falls through to its own bundle ID.
- Chromium browsers (Brave, Chrome) and their installed web apps (for example a "YouTube" PWA from Brave) play all audio through ONE utility process (`--utility-sub-type=audio.mojom.AudioService`), responsible to the browser. A PWA therefore cannot be separated from the browser's tabs at the Core Audio level: it appears as the browser's column. That is a platform limit, not a bug.

### Outputs

- [ ] An app sent to AirPods only plays on the AirPods and not on the speakers. pending: run with the user
- [ ] The same app sent to the AirPods and the speakers plays on both, in either order of selection (the first one chosen is the clock). pending: run with the user
- [ ] An app sent to the AirPods while the speakers are the system output (a mixdown tap) plays on the AirPods only and stays audible; an app following the system output uses the cheaper stream tap. pending: run with the user
- [ ] Moving the system output away from the device an app is pinned to hands the app over with a crossfade and no gap, because its tap changes from the device's stream to the mixdown. pending: run with the user
- [ ] "Cascade" never appears as an app column, with an app controlled and playing (AudioHost's own output is not listed). pending: run with the user
- [ ] Switching an app's output crossfades with no audible click or gap. pending: run with the user
- [ ] "Follow system" makes the app follow the system output again, including when that output changes. pending: run with the user

### Lifecycle

- [ ] 50 sleep/wake cycles with an app at 25 %: after each wake the app is at 25 % again, with no burst at 100 % beyond the gap measured for the rebuild. pending: run with the user
- [ ] Disconnecting the AirPods while an app plays to them: the column shows the fallback output, the preference is kept, and reconnecting restores it. pending: run with the user
- [ ] `kill -9` of AudioHost while an app is controlled: the app is audible at once, the columns recover, and the intents are replayed (the app is at its gain again). pending: run with the user
- [ ] Three `kill -9` of AudioHost within five minutes: Cascade gives up, per-app audio returns to native, Settings (Widget page, Plugins section) shows AudioHost given up, and Restart brings it back with the intents replayed. pending: run with the user
- [ ] `kill -9` of Cascade while an app is controlled leaves the app audible, and a relaunch removes any leftover multi-output aggregate. pending: run with the user

### Permission

- [ ] With System Audio Recording denied for Cascade: what the first per-app control does (creation fails, or the app is silenced, or it stays audible), and whether `captureAllowed` can be known. pending: run with the user, together with the permission spike's runs P1 to P4. Until it is measured the spec says the behaviour is not yet known, `captureAllowed` stays unknown (`nil`) and the mixer treats that as allowed.

### Idle cost and gates

- [ ] With neutral intents (every app at 100 %, unmuted, following the system) and the notch closed, AudioHost is not running (Activity Monitor). pending: run with the user
- [ ] With one controlled app, then ten, AudioHost's CPU against the spec's gates (below 1 % for one stereo app at 48 kHz, below 3 % for ten). pending: run with the user
- [ ] With one controlled app, then ten, AudioHost's private memory against the gates (at most 16 MiB for one, 48 MiB for ten) and below the 64 MiB limit. pending: run with the user
- [ ] Cascade's own CPU and idle wakeups at rest are unchanged compared with `main`. pending: run with the user

## 3. Open hardware questions

Recorded while building; the code assumes one answer to each, and a run on real devices may
disagree.

1. **A stacked aggregate's output buffer list.** The aggregate lists the output streams of
   every sub-device, one `AudioBuffer` per stream, and the render kernel now writes the same
   frame into the first stream of every sub-device. It learns where each one begins from the
   stream counts the pipeline asks the HAL for (`outputStreamCount`), as the prefix sums of
   the outputs in order: the first device at buffer 0, the second after the streams of the
   first, and so on. Each destination is mapped to its own channel count, and the gain ramp
   advances once per frame. What remains to verify on hardware is that the aggregate's buffer
   order really matches the sub-device order (main first, then the others as listed): if it
   does not, the audio would reach a device other than the one chosen, or none. Also to see
   is that an output whose stream count is zero or unknown fails the build and the app
   returns to native audio, as does one whose sample width differs from the main output's.
2. **Non-float device formats.** The pipeline build fails today for a device whose stream
   format is not 32-bit float, so such an output is not controllable and the app returns to
   native audio. How common that is on real devices is not known.
3. **The real wake path.** The reconciler's handling of wake is covered by tests over a fake,
   but the `NSWorkspace` wake notification reaching the real service has not been run. The
   50-cycle check above is the first time it will be.

## 4. Known minor limitations

- Denied capture permission is built (read-only columns, banner to System Settings) but
  never triggered by a measured denial; see the Permission item.
