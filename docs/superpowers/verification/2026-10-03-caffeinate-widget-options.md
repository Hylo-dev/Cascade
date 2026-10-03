# Caffeinate widget options evidence

## Scope

The builtin PluginHost compatibility widget uses the shared native notch options
container. Its cup toggles the native session; the text/disclosure or icon-only
widget context action opens duration, display, Stop and inline acknowledgments.
The underlying ordinary page and contextual slot are preserved. External addon
production transport and native managed-launcher qualification remain on hold.

Follow-up base: `1298bc4d149d7e8d8fef0a3d5e5a8493ef913bb0`.
Initial integration head: `396946a322f04229e329fadef120853b99c61099`.
Final UI source: `65e80c34119b27f0bdc7382d59ee40ac4136ef67`.
Independent review and finishing evidence are recorded below.

## Automated and native-resource checks

- Final integration serial package suite: 1,887 tests passed, exit 0. Counts are
  902 + 125 + 46 + 165 + 441 + 188 + 20. Log:
  `/private/tmp/caffeinate-options-full-complete.log`.
- Actual app controller suite: 5 tests passed, including two copied-control cases.
  Native-before/native-after deadlines are compared exactly; decoded wire
  deadlines are compared independently. Log:
  `/private/tmp/caffeinate-options-app-tests5.log`, `TEST SUCCEEDED`, exit 0.
- Real IOKit ownership, rollback, OS deadline and release checks passed before
  and after the integration. Logs:
  `/private/tmp/caffeinate-options-native-{before,after}.log`.
- Final incremental canonical build passed, including addon boundary checks,
  deep/strict signature verification and application-link update. Log:
  `/private/tmp/caffeinate-options-canonical-final-build.log`, `BUILD SUCCEEDED`, exit 0.

These checks establish contract, broker, lifecycle and native-resource behavior.
They do not establish successful input through the rendered production widget.

## Actual compiled-app UI attempt

The final signed executable ran `--check-caffeinate-options` as PID 61963 and
exited 1. It used a unique cleaned preference suite and genuine rendered
accessibility controls, with no manufactured origin or acceptance:

```text
FAIL: compiled-app Caffeinate options check: No enabled rendered Caffeinate AX control; native UI check unqualified
```

The first cup lookup failed; the check did not reach options, duration, display,
Stop, credits or native Back. Log and exact executable/link record:
`/private/tmp/caffeinate-options-native-app-check.{log,json}`.

A LaunchServices preview then started the same signed build as PID 62044 with
`--preview-caffeinate-options`. The native UI tool reported that the Mac was
locked and automatic unlock could not unlock it. Manual unlock was requested;
no answer or unlock is inferred. Earlier screen capture had separately failed
with ScreenCaptureKit `-3811`. The cause of the internal AX lookup failure is not
established by those external-tool failures.

Native cup/options input, context action, Back/Escape, visual transition acceptance,
physical input and hardware multiple-display behavior remain unqualified.

## Runtime measurement limits

The isolated Caffeinate preview PID 62044 used nine five-second `top` samples.
Its final five samples were all 0.0% CPU; separate physical footprint was
26,362,840 bytes (25.14 MiB), peak 26,543,064 bytes. Raw files:
`/private/tmp/caffeinate-options-preview-idle.{json,top.txt,footprint.txt}`.
This was a locked-screen idle sample of the isolated preview, with no proven
visible options page or input scenario. It is not a transition budget pass.

The earlier normal-launch baseline (PID 48153) was 0.18% mean CPU across the
last five samples, 0.9% maximum and 27,755,480 bytes physical footprint. Raw files:
`/private/tmp/widget-fullscreen-after-closed.{json,top.txt,footprint.txt}`.
That baseline's production code matches the follow-up base: the intervening
`0fa653b..1298bc4` changes are only plan/verification documents. The isolated
preview and normal launch have different source composition and cannot be
compared as a matched before/after performance scenario.

Physical footprint is not private resident RAM. CPU wakeups, active-session
reconfiguration and actual open/Back animation costs still require an unlocked,
driven app scenario.

## User-requested design correction

Back now uses `chevron.left`. Both native Back and Settings refuse first responder
and use `focusRingType = .none`. A separate invisible `NSResponder` preserves the
nonactivating panel's Escape route. The previous behavior deliberately focused
Back; its regression failed with seven issues before the correction and passed
afterward. Logs: `/private/tmp/caffeinate-options-keyboard-target-red.log` and
`/private/tmp/caffeinate-options-authority-final-focused.log`.

The additional Caffeinate controls now have a session header, seven equal duration
segments, an explicit display switch and a quiet Stop/credits footer. The existing
cup amber identifies the selected duration and enabled state. The top alignment
keeps the header stable when credits disclose. The design adds no SDK primitive,
dependency, periodic timer or per-frame state. The [design record](../plans/2026-10-03-caffeinate-options-design.md)
documents the Impeccable/Taste adaptation to the native product.

Actual compiled plugin components were rendered with SwiftUI `ImageRenderer`,
using the real provider, document, store and renderer at 388-point content width.
English and Italian were rendered from their compiled resource bundles. Off,
active and busy fitting heights are 164 points; credits and error-with-credits
are 213 points. All fit the 220-point container; aggregate document counts range
from 53 to 78 nodes. Images were inspected for hierarchy, wrapping and clipping.
Raw renderer and results: `/private/tmp/render-caffeinate-design.swift`,
`/private/tmp/caffeinate-design-{en,it}.json` and corresponding PNGs. These renders
are component evidence; they do not include the AppKit chrome, physical notch,
input, hover or transition performance.

## Final authorization review

The independent original review found two Important defects: a retained actual
renderer callback borrowing a reopened page's origin, and accepted detail actions
losing origin before native delivery. Commit `bd5bab1bab7e62ee2deea5ea35f44b814acc5cda`
captures immutable origins throughout rendering and validates them immediately
before a synchronous native-effect continuation. Regression probes failed before
that correction. The scoped re-review confirms both original cases are addressed.

The re-review still requires changes in the generic compatibility seam:

- Important/P2: moving the same control ID from options to compact content can
  let a revoked actual renderer callback submit through the plain path, because
  the store chooses authorization from current node membership.
- Minor/P3: a slider release after revocation returns before clearing the shared
  dragging/optimistic state; a later reopening can retain its old thumb value.

Both were reproduced with actual compiled renderer callbacks in controlled
hosts. Logs: `/private/tmp/caffeinate-options-authority-rereview-probe.log` and
`/private/tmp/caffeinate-options-authority-slider-probe.log`. Caffeinate's current
provider does not migrate controls between roots and has no slider. These are
explicit open generic cases in `docs/TODO.md`; this branch is not globally
qualified for arbitrary fullscreen addon widgets. The SDD final-review cap
permits one fix wave and one scoped re-review, so these residuals were adjudicated
at that cap rather than silently discarded. External production transport and
managed-launcher HOLD remain unchanged.

## Final verification and launch

- Final serial suite at the UI source above: 1,891 tests passed, exit 0;
  902 + 125 + 46 + 165 + 445 + 188 + 20. Log:
  `/private/tmp/caffeinate-options-authority-final-full.log`.
- Focused final coverage: 54 tests passed, including the native navigation-focus
  regression and real Button/Toggle closure revocation tests. The accepted-effect
  test covers seven invalidation cases. Log:
  `/private/tmp/caffeinate-options-authority-final-focused.log`.
- Canonical signed application build passed with boundary checks, signature
  verification and application-link update, exit 0. Log:
  `/private/tmp/caffeinate-options-redesign-build.log`.
- The final compiled-app check ran as PID 67614 and exited 1 with the same
  `No enabled rendered Caffeinate AX control; native UI check unqualified` failure.
  Log and identity: `/private/tmp/caffeinate-options-redesign-native-check.{log,json}`.
  The UI tool separately reported the Mac locked, then after the final normal
  launch returned only window/menu chrome without widget controls. Neither result
  establishes the cause of the internal AX failure or a successful click scenario.
- The final normal LaunchServices restart verified PID 67923 with no diagnostic
  arguments and `/Applications/Cascade.app` pointing to
  `/private/tmp/cascade-widget-fullscreen-feature-derived/Build/Products/Debug/Cascade.app`.
  Record: `/private/tmp/caffeinate-options-redesign-final-launch.json`.

The isolated preview's identical nine-sample method yielded 2.28% mean CPU and
5.5% maximum in the last five samples, with 33,244,144 bytes (31.70 MiB) physical
footprint, versus the earlier preview's 0.0% and 25.14 MiB. The final samples were
variable; no driven or proven visible options scenario was captured. These are
preliminary idle observations and are not a matched transition or wakeup pass.
The parser was corrected to accept `top`'s `total/running` thread-count form using
the existing samples, without repeating them. Raw files:
`/private/tmp/caffeinate-options-redesign-preview-idle.{json,top.txt,footprint.txt}`.

The final normal launch then stayed at 0.0% CPU across all nine samples; physical
footprint was 27,362,288 bytes (26.09 MiB), peak 30,671,952 bytes. Normal-launch
idle observations using the same method are:

| Metric | Earlier normal baseline | Final normal launch |
| --- | ---: | ---: |
| Last-five mean process CPU | 0.18% | 0.0% |
| Last-five maximum process CPU | 0.9% | 0.0% |
| Physical footprint | 26.47 MiB | 26.09 MiB |

Final raw files: `/private/tmp/caffeinate-options-redesign-normal-idle.{json,top.txt,footprint.txt}`.
These are idle observations, not a driven open/Back scenario. They neither explain
the variable preview sample nor qualify animation cost, physical input, wakeups
or private resident RAM.

## Mandatory top band and icon-only heading follow-up

The user requested a mandatory border/reserved top band for the physical cutout,
Back and Settings, and only the cup in Caffeinate's heading. The shared host now
clips incoming and outgoing options hosts at the allocated body boundary and
draws a native one-pixel divider below the navigation band. A native vertical
ScrollView keeps longer detail content reachable inside that boundary. Its
document measures naturally; credits and errors scroll without growing the notch.
The existing physical/software notch header calculation and navigation controls
remain host-owned. The divider follows increased-contrast settings and is hidden
when the page is cleared. Existing finite transitions and focus behavior remain.

Caffeinate's cup now sits beside the duration segments. Visible title/status and
the extra duration heading are removed; the status remains accessible on the cup,
and actual errors still have a separate inline message. No timer, dependency,
SDK primitive or per-frame callback was added.

The earlier 220-point component measurement did not prove fit inside the actual
configured notch body. The follow-up renders use 400-point width and the standard
144-point notch: 32-point physical cutout/navigation height, 4-point top inset,
16-point bottom inset, and a 92-point body. Normal, active and busy content now
measure exactly 92 points in English and Italian. Credits measure 137 points;
credits plus error measure 156 points, and use the shared scroll area. Aggregate
documents contain 46–70 nodes. Native host export confirms the cup/controls stay
below the divider and Back/Settings occupy the reserved band in the inspected
initial render. Native exports are controlled offscreen component evidence,
not physical input or a camera-cutout screenshot.

Evidence:

- RED: `/private/tmp/caffeinate-header-red.log`, exit 1, two expected failures for
  unclipped native content and missing divider.
- GREEN: `/private/tmp/caffeinate-header-green-final.log`, exit 0, 33 tests passed
  (3 provider tests + 30 native host/navigation tests). The new regression also
  confirms a 300-point document can scroll inside the 92-point clipped viewport,
  and clearing the page hides the divider. Existing lifetime/focus/retarget checks pass.
- Component/native render harness: `/private/tmp/render-caffeinate-header.swift`;
  metrics `/private/tmp/caffeinate-header-design-{en,it}.json` and corresponding
  PNGs. The initial isolated native export failed with SIGABRT in AppKit's
  `_RegisterApplication`; running the same compiled local renderer outside the
  filesystem sandbox completed for both languages, exit 0. No product code
  change was used to bypass that harness environment failure.
- Canonical signed build: `/private/tmp/caffeinate-header-app-build.log`, exit 0,
  `BUILD SUCCEEDED`, signature/boundary verification and application-link update.
- Normal restart: `/private/tmp/caffeinate-header-final-launch.json`, PID 70590,
  exact feature-build executable with no diagnostic arguments. The link still
  targets `/private/tmp/cascade-widget-fullscreen-feature-derived/Build/Products/Debug/Cascade.app`.

The two previously recorded generic authorization/slider residuals remain open;
this bounded presentation change does not alter those paths. Physical input,
multiple-display and driven animation/wakeup qualification remain separate.
The final UI-tool inspection again returned only window/menu chrome, without
widget controls; this is not a successful real-app input check.

The normal-launch idle comparison uses the same nine five-second samples and
separate physical-footprint measurement:

| Metric | Before this follow-up (PID 67923) | After (PID 70590) |
| --- | ---: | ---: |
| Last-five mean and maximum process CPU | 0.0% / 0.0% | 0.0% / 0.0% |
| Physical footprint | 26.09 MiB | 25.19 MiB |

After raw files: `/private/tmp/caffeinate-header-normal-idle.{json,top.txt,footprint.txt}`.
The final footprint is 26,412,016 bytes, peak 30,164,024 bytes. Idle observations
do not establish a causal memory saving or qualify scrolling/animation costs.
