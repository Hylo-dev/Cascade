# Spotlight and the notch: live macOS 27 experiment

Date: 9 September 2026. This is an exploratory spike, not a shipped Cascade feature.
The user authorized opening, moving, and using Spotlight and the notch, then
explicitly requested simulation of Command-Space. The app's production sources
were not changed. Temporary native Swift probes live under `.scratch/`.

## Outcome

**Option 1 is feasible at the window-control level on this device.** The real
Spotlight capsule can be centered immediately below the notch. Accessibility
movement notifications permit correcting a displacement without an idle polling
loop. Apple's native input and calculator result continue to work. A temporary
black companion surface was animated behind the native window to explore the
visual connection; its final appearance is not approved or production-ready.

**Option 2 has specific private research targets, but no demonstrated replacement
of the native text field.** Its AX value is writable and updates real search
results, while its position and size are not writable. See the separate
[system-functions investigation](spotlight-system-functions-macos27.md) for the
private field/results split, shared manager, and Campo remote-view infrastructure.

## Measured environment and identity

| Item | Measured value |
| --- | --- |
| OS | macOS 27.0, build `26A5425a` |
| Display | One display, 1470 × 956 logical points |
| Hardware safe-area top | 32 points |
| Visible frame | `(0, 0, 1470, 923)` in AppKit coordinates |
| Actual Spotlight owner | `/System/Applications/Siri AI.app`, bundle `com.apple.campo`, PID 1330 during the probe |
| Native search identifier | `SpotlightSearchField` |
| Native window layer | 23 |
| Existing Cascade layer | 25 |
| Temporary connector layer | 22, behind the native search window |
| AX client trust | `AXIsProcessTrusted() == true`; no permission setting changed |

Launching `/System/Library/CoreServices/Spotlight.app` failed with RBS launch error
5 / POSIX 162. The legacy process was absent even while the user confirmed that
Spotlight was visible. The launch configuration conditionally disables the legacy
Spotlight job for `IntelligenceFlow/Campo`. Simulated Command-Space opened the real
panel. Selecting `com.apple.campo` subsequently allowed native UI inspection.

The visible search must be identified by its actual owner and descendant field,
not by an application name or the first window. Campo also has a separate 900 × 770
chat window. No attempt was made to reposition that window.

## Experiments and evidence

### Settled geometry and the animation surface

During an opening transition, AX and the window list reported a host as large as
`(0, 33, 1470, 923)`. After settling, the empty capsule was `(475, 175, 520, 87)`.
The field inside it was `(512, 204, 413, 28)`.

This distinction matters: a display-sized intermediate host must not be treated
as the capsule's final dimensions. The disposable lab skips such geometry. A
production implementation must explicitly handle settling and cancellation.

### Position write, clamping, and restoration

The native window reported `AXPosition` and `AXSize` writable. The field reported
both nonwritable, while `AXValue` was writable. Window resizing was not attempted.

```text
MOVE requested=(475, 19) -> AX success
MOVED window=(475, 33), field=(512, 62)
RESTORE requested=(475, 175) -> AX success
RESTORED window=(475, 175), field=(512, 204)
```

macOS clamps the window below the menu bar on this display. An attempted negative
Y position also read back at 33. The native capsule can abut the notch's bottom;
it cannot be assumed to cover the hardware area by moving its window above that
boundary. A separate connector supplies the proposed visual expansion.

### Movement notifications and correction

The lab registered successfully for `AXWindowCreated`, `AXFocusedWindowChanged`,
`AXApplicationHidden`, `AXApplicationShown`, `AXMoved`, `AXResized`, and
`AXUIElementDestroyed`. It coalesced callbacks with a one-shot 20 ms dispatch.
There is no recurring timer or window scan while idle; the run deadline is one-shot.

In the four-second controlled test:

```text
PIN start -> (475, 33), success
DISPLACE -> (545, 133), success
PIN reason=AXMoved -> (475, 33), success
AFTER_DISPLACE (475, 33), matching target
RESTORE -> (475, 175), success
DONE corrections=2 notifications=12
```

This demonstrates correction after a move, not prevention before the first frame
of a drag. A CUA drag gesture was also attempted; it exposed the native category
list and produced no additional correction in that run. It does not establish
that the tested gesture moved the window. Continuous physical dragging and visual
jitter remain to be evaluated separately.

### Native search and results expansion

Setting `SpotlightSearchField` to the synthetic query `2+2` through AX produced the
native calculator result `2+2 = 4`. No result was launched and no personal query
was entered. The query was cleared afterward.

With the calculator result visible, the settled native frame was
`(475, 33, 520, 263)`, and the field remained at `(512, 62)` while its width changed
to 450. A category-list state measured height 313. Consequently, anchoring must
preserve the top edge as results grow, and a field-covering overlay cannot assume
fixed input width or a fixed result height.

AX value forwarding is a useful demonstrated seam for a possible custom input
prototype. It does not solve focus ownership, IME composition, selection, VoiceOver,
keyboard navigation, result activation, or hiding the native field. Those behaviors
were not tested and must not be claimed as a completed text-field replacement.

### Lifecycle and cleanup

Escape removed the identified Spotlight window from the on-screen list and AX
window enumeration. Command-Space reopened it. During the first lifecycle run,
cleanup through a retained AX proxy failed with `-25202` (`invalidUIElement`), even
though a freshly enumerated search window was available. A fresh reference then
restored `(475, 175)` successfully.

The lab was corrected to retain freshly enumerated references and re-enumerate
before cleanup. The original pre-test position is kept across reopenings. If the
window is closed at the deadline, the lab reports that restoration is unavailable;
this remains a disposable-harness limitation, not acceptable production behavior.

The subsequent lifecycle run reconfirmed displacement correction, but had no
exposed search window at its deadline (`corrections=2`, `notifications=15`). It
correctly reported restoration unavailable. Thus the revised cleanup must not be
described as a fully verified lifecycle fix. A final `open 'spotlight:'` invocation
was accepted by Launch Services but did not yield an AX search field in the
following inspection; direct URL invocation is not a verified opening mechanism.
The final native search window was closed, and restoration of its remembered
position after that closure was not confirmed.

## Visual experiment and scope

The lab creates a nonactivating, mouse-transparent AppKit panel behind Spotlight,
with a black `CAShapeLayer` interpolating from a notch-sized outline to a surface
520 points wide. It uses a 240 ms transition and respects Reduce Motion. Native
text entry keeps keyboard focus. The ordinary Cascade notch remains above it.

This is a geometry/layering experiment. It uses temporary dimensions, a separate
outline, and one display. Captures of the native window verified its input and
results, but did not capture the complete composed desktop. The material seam,
perceived expansion, overlap with Cascade hover content, close animation, Spaces,
fullscreen, other displays, and energy use have not received final visual or
performance validation. The prototype must not be presented as finished fusion.

For integration, add a small app-level Spotlight coordinator and an explicit
external-surface presentation contract in CascadeKit. Reuse Cascade's morph engine
and screen resolver; keep native search, result selection, and dismissal in Campo.
Perform AX messaging outside the main animation path, bound timeouts, react to
workspace/AX lifecycle events, and restore the native position when disabling.
The current harness's main-run-loop AX calls are suitable only for this brief probe.

## Reproduce the disposable probes

These sources are deliberately excluded from the app targets:

- `.scratch/spotlight-window-probe.swift`: geometry and attribute inspection;
  `--move` tests displacement and restoration. `--restore X Y` explicitly restores
  a measured baseline on the current display. Avoid supplying unrelated coordinates.
- `.scratch/spotlight-fusion-lab.swift`: 45-second animated connector/pinning trial;
  `--self-test` injects a controlled window displacement, and `--brief` shortens
  the run to four seconds. Open the native panel before starting it.

Compile with the installed Xcode-beta Swift compiler and an output under
`/private/tmp`; these are not installable app builds. Compile and run only with
existing AX authorization. Keep a visible search window at the deadline for the
automatic position restore. The original measured baseline in this session was
`(475, 175)`; do not reuse it as a universal screen default.

Apple's APIs define how to query writability and subscribe to supported events;
the measured Spotlight behavior above is specific to this OS build, not an Apple
Spotlight positioning guarantee.
[AXUIElementIsAttributeSettable](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable),
[AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification).

## Final workspace state

All temporary lab processes exited. Cascade was terminated and relaunched through
`/Applications/Cascade.app`; its new PID was 13889, with the expected executable
under `DerivedData/CascadeDevelopment/Build/Products/Debug/Cascade.app`. The native
UI capture confirmed the notch was rendered after restart. The application link
still points at that existing development build. No app source or app target was
changed, so no new application build was required. The two disposable Swift probes
compiled successfully, and `git diff --check` passed.
