# Spotlight droplet implementation plan

**Goal:** Delay native Spotlight until a Liquid Glass drop has detached from the
notch and expanded into the search capsule. Keep Apple's search and results.

**Design:** Use AppKit's NSGlassEffectContainerView with an anchored glass source
and a departing glass capsule. Start immediately, gather for about 70 ms, detach
over about 110 ms, and expand into a 520 × 87 point capsule over the remaining
220 ms. Respect Reduce Motion. The native keyboard shortcut is forwarded only
after detachment. AX observes and positions the native field's containing window;
native keyboard focus ends the temporary visual handoff.

**Constraints:** Keep the existing dirty development checkout and edits. No
system process injection, security changes, private Spotlight UI instantiation,
screen snapshots, or idle polling. macOS 26+ native glass, app deployment floor
14 with availability gating. Main animation code does no AX messaging. Native
keyboard events temporarily retained for the handoff must never be replayed to
an unrelated application. Disable/stop cancels animation and removes observers.

## Tasks

- [x] Build the native glass animation and pure motion model. Add behavior checks
  for continuity, separation before full expansion, exact landing bounds, and
  reduced motion. Interface: `SpotlightDropletPresenting.play(on:nativeSize:completion:)`
  passes the landing CGRect in AppKit global coordinates; `revealNative()` and
  `cancel()` release the temporary surface; `preview(on:)` is visual only.
- [x] Build bounded shortcut gating and an AX worker on its own serial queue.
  The shortcut tap calls the coordinator without AX or UI work in its callback.
  Native readiness requires an identified SpotlightSearchField and verified AX
  position. Use fresh references on each reconciliation. Test duplicate shortcut,
  cancellation, timeout, and event replay policy separately from system effects.
- [x] Wire a preference, launch action, visual preview, and status into
  CascadeServices/CascadeMenu. Start and stop with the other integrations.
- [x] Run focused checks and app build, review the new integration, exercise
  preview/native handoff on this device, update /Applications/Cascade.app through
  the existing build script, restart, and verify the updated app.

## Progress

Plan accepted from the user's explicit animation direction; implementation proceeds
without a separate approval round. Animation rendering and system coordination
have independent ownership and can be developed concurrently.


## Verification — 2026-09-09

Implemented in `Cascade/Features/Spotlight` and `Cascade/Integrations/Spotlight`.
The application menu exposes the enabled preference, an isolated visual preview,
and a native-opening action. Main-notch hover remains closed during the external
search presentation.

- Full CascadeKit suite: 133 tests in 15 suites passed, including the new external
  search/hover regression.
- `scripts/test-spotlight-droplet.sh`: five behavior groups passed; continuous
  geometry and merge spacing, detachment before widening, exact global landing,
  Reduce Motion, and invalid-size handling.
- `scripts/test-spotlight.sh`: handoff generations, shortcut validation and a
  simulated stalled worker followed by cancellation passed.
- Review corrections: stale animation tasks are discarded; every fresh AX proxy
  receives a bounded timeout; one inspection shares a total 120ms deadline;
  synchronous cancellation invalidates pending AX mutations. Incomplete window
  notification registration remains retryable. Setup receives a fresh budget.
- Visual calibration used a disposable AppKit harness compiled against the actual
  renderer. Frozen samples at 180ms and 220ms showed the neck; a 44pt initial merge
  distance retains it longer, then eases to 22pt from 220–300ms so the capsule stays
  detached during expansion. The final capsule is 520×87pt. Window captures verify
  shape; backdrop refraction in these isolated captures does not reproduce the
  complete desktop composition.
- Successful development build updated `/Applications/Cascade.app`. Updated
  application launched as PID18305 from CascadeDevelopment/Debug.
- Real Cmd-Space opening on this device reached `SpotlightSearchField` at
  AX(512,93), corresponding to native window (475,64): 32pt below the hardware
  notch. CUA typed `2+2`; Apple's calculator result was `2+2 = 4`.
- A drag attempt left the field at the same anchored coordinates. Native closing
  removed the field. No Spotlight handoff timeout was logged.

The integration targets the Campo-hosted Spotlight observed on this macOS 27
installation. It does not replace Apple's field or search implementation. Native
window discovery/positioning occurs after the native shortcut is delivered;
first-open or system animation behavior can therefore affect the final handoff.
Automatic checks do not validate visual quality across all wallpapers or displays.

Native glass API reference:
[NSGlassEffectContainerView](https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview).

A second Cmd-Space after 100ms cancelled the opening with no native field or
droplet left visible. A subsequent opening succeeded; the test query was cleared.
The application was then restarted again from the verified development build.

## Follow-up fixes — 2026-09-09

- The native glass container now receives a graphite gradient through public Core
  Image compositing. The finish follows the entire merged silhouette, including
  the neck, and visually approaches the observed Campo search capsule. This is a
  calibrated finish, not access to Spotlight's own material implementation.
- The temporary window yields below native Spotlight before handoff and is
  removed immediately on the first confirmed native visibility. It no longer
  waits for keyboard focus or the end of Campo's full-screen opening transition,
  and native handoff has no additional dissolve delay.
- Rapid shortcuts now preserve native opening/visibility across animation
  generations. A new droplet reuses a native window already opening or visible;
  it cannot issue a second opening toggle that would instead close that window.
  A requested close during Campo's opening waits for the native window to settle
  because this OS build can ignore toggles during its own animation. A later
  reopen supersedes that pending close. Escape's query-clearing behavior is
  distinguished through fresh window/focus observations without reading queries.
- Focused state-machine and AX cancellation checks passed, including replacement
  cancellation and a slow native opening across generations. All six droplet
  behavior groups passed, including the actual panel's layer ordering and
  immediate removal. `git diff --check` and the development build succeeded.
- Live testing of the updated app (PID21219) passed both three-toggle
  open/close/reopen and four-toggle open/close/reopen/close sequences, with 650ms
  before the first close and 100ms between subsequent toggles. The former ended
  with native Spotlight focused at AX(512,93), with no temporary glass window;
  the latter ended with both native Spotlight and the temporary window closed.
  The updated build is linked from `/Applications/Cascade.app`.

## Material and detachment correction — 2026-09-09

The previous opaque graphite gradient was calibrated against an isolated window
capture, whose appearance differs substantially from the desktop composition.
That calibration is superseded: the renderer now uses native clear glass with a
translucent black scrim inside the departing capsule, preserving the backdrop.
The opaque gray stops and Core Image alpha/compositing filters were removed.
Comparison used the same desktop region as real Spotlight. This approximates the
observed dark surface; it does not duplicate Spotlight's private material.

Detachment now completes by 180ms instead of 300ms. Gathering lasts 70ms, descent
110ms, and horizontal expansion retains its 220ms duration: 400ms overall instead
of 520ms. Frozen native-renderer samples verified the neck at 120ms and complete
separation at 180ms. The new 180ms check failed before the timing change and passed
afterward. All six droplet behavior groups, handoff/shortcut/AX checks, whitespace
validation, and the development build passed with the final renderer.
