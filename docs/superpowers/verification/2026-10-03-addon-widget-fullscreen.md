# Addon widget detail qualification

The reusable options contract, accepted-action authority and native notch
container are implemented in `codex/widget-fullscreen`. This record distinguishes
automated package checks, compiled-app checks and physical interaction evidence.
The external native launcher remains on HOLD; no production transport/presenter
assembly or individual Display/Audio addon is claimed.

## Package evidence

Initial implementation: 249 focused checks and 1,872 full serial package tests
passed. The full log contains expected CoreData corruption diagnostics from
`unreadableOwnerModelDoesNotCloseNormalStorageForAnotherRegisteredOwner`; that
fault-injection test passed. Boundary audit passed: four packages, eleven
targets, 227 Swift files and 346 imports. The unchanged managed-death check
returned expected exit 78, with the unresolved pre-trace parent-selection gate.

Independent review identified fallible asset validation after UI projection.
The RED regression rejected an unimported alias but recorded a second presenter
call and a replaced valid detail. The fix prepares and validates the complete
batch before projection, then commits through nonthrowing helpers. Its focused
covering run passed 119 runtime and nine navigation tests. Full serial checks
passed 1,874 tests (902 runtime, 435 Kit, 185 contracts, 162 presentation, 125
plugin engine, 45 plugins, 20 SDK/tool), and the boundary audit passed unchanged.
An additional focused assertion verifies the specific invalid-alias error and
successful retry at the unchanged sequence. A test-only mixed-output
classification error was corrected; it was not another production defect.
Evidence: `/private/tmp/cascade-widget-fullscreen-fix-1-*.log`.

The whole-feature review found no Critical/Important defect, and one Minor
metric ambiguity: visible host count did not establish retained-root lifetime.
Genuine weak-owner checks then exposed mounted SwiftUI document retention after
rapid stop. Cleanup now settles the two cleared native hosts once, only when
active/outgoing content existed. Both normal and Reduce Motion mounted checks
pass, including immediate owner release after stop. The scoped fix review
approved all findings with no new breakage. Final focused checks passed 116
tests; fresh full serial checks passed **1,875** tests (902 runtime, 436 Kit,
185 contracts, 162 presentation, 125 plugin engine, 45 plugins, 20 SDK/tool).
Expected CoreData corruption and pasteboard sandbox diagnostics remain disclosed.
Evidence: `/private/tmp/cascade-widget-options-lifetime-*.log`.

## Baseline measurement

Base commit `2ff46d96c1fda59c8acd1cdb8fe70d39c7b0f317` was built with the
canonical Xcode-beta script and the same local signing configuration. Normal
startup retained the user's ordinary preferences. Nine process `top` samples
were taken five seconds apart; the last five exclude early startup. Physical
footprint was sampled separately. This is physical footprint, not private
resident memory; wakeup and frame timing measurements were unavailable.

| Requested scenario | Mean CPU, last five | Maximum CPU, last five | Physical footprint |
| --- | ---: | ---: | ---: |
| Normal closed, PID 28533 | 2.12% | 3.8% | 34,915,360 bytes |
| `--inspect-expanded-notch`, PID 28786 | 0.50% | 2.5% | 33,473,544 bytes |

Raw baseline evidence is at `/private/tmp/widget-fullscreen-matched-baseline.json`
and the corresponding `*-top.txt` / `*-footprint.txt` files. The expanded
argument requested opening; the computer-use surface returned an empty
transparent panel, so actual visible opening and input were not verified.
The expanded row therefore cannot qualify interactive animation performance.

The updated build used the same nine-sample method and normal startup paths:

| Requested scenario | Mean CPU, last five | Maximum CPU, last five | Physical footprint |
| --- | ---: | ---: | ---: |
| Normal closed, PID 48153 | 0.18% | 0.9% | 27,755,480 bytes |
| `--inspect-expanded-notch`, PID 48720 | 0.00% | 0.0% | 30,442,480 bytes |

Raw after evidence is `/private/tmp/widget-fullscreen-after-closed.json` and
`/private/tmp/widget-fullscreen-after-expanded.json`, with corresponding sample
logs. These measurements establish idle process costs in the requested scenarios;
background sources and visible opening were not independently matched. Computer
use still returned an empty white panel and no content accessibility controls.
The numbers do not establish animation, private-memory, wakeup or latency budgets.

## Product and authority decisions

Only a genuinely visible ordinary compact widget can mint a host origin.
The latest pending compact click wins: B supersedes A before a reply, and Back
invalidates late replies. A selected contextual page/activity hides the ordinary
grid, so it offers no source entry under this design. Tests preserve the separate
contextual slot and restore the reachable ordinary selection; they do not claim
restoring a selected shelf reached through a hidden widget.

Replay history retains at most 256 charged bindings across all live connection
generations, 128 bytes each (32 KiB total). Exhaustion rejects new openings until
canonical owner/generation invalidation refunds capacity. Refresh and dismissal
remain available. Back never silently erases replay history.

## Remaining qualification

The shared core at `4048598593a387207a8859cac4a1bda70c391be8` passed the
canonical Xcode-beta development build, signature check and application-link
update (exit 0, `/private/tmp/cascade-widget-fullscreen-feature-build.log`).
The build emitted the existing AppIntents metadata-extraction warning and an
unknown `SWIFT_DEBUG_INFORMATION_VERSION` environment warning; it was not a
warning-free build. Scoped independent re-review found all findings addressed,
with no new Critical/Important breakage.

The final source at `0fa653bd7b9d990e2b7036eb33f02b64e60aa44a` also passed
the canonical build, strict signature verification and application-link update,
exit 0: `/private/tmp/cascade-widget-fullscreen-final-build.log`. The existing
AppIntents/environment warnings remain. The additional Debug failure diagnostic
charges every traversal attempt before depth/visited rejection, stops at maximum
depth, and performs at most two hit tests through the same bounded traversal.
Its focused review approved the correction with no new findings. Strict Swift 6
MainActor/import-visibility compilation and whitespace checks passed; unchanged
package code did not require another full suite run.

The Debug fixture is implemented and the full build passed. Real input/visual
inspection and interaction performance are pending. Computer use initially
reported a locked Mac and failed automatic unlock; the user was asked to unlock
it. Later it could read the shell without the lock error, but menu/Cmd-Q actions
returned `AXError.actionUnsupported` and the screenshot remained an empty white
panel. No physical input or visual clearance is claimed from that surface.
Physical multiple-display behavior and production adapter assembly require
their own evidence.

The first full app build with the fixture returned exit 65:
`missing import of defining module 'CascadeKit' [#MemberImportVisibility]`
in `AddonWidgetDetailChecks.swift`. The isolated typecheck had not enabled this
Xcode import-visibility requirement. The diagnostic is preserved in
`/private/tmp/cascade-widget-fullscreen-fixture-build.log`; the required import
was added and the canonical retry passed (exit 0,
`/private/tmp/cascade-widget-fullscreen-fixture-build-retry.log`). The retry
verified signing and updated `/Applications/Cascade.app` to
`/private/tmp/cascade-widget-fullscreen-feature-derived/Build/Products/Debug/Cascade.app`.
The build emitted existing AppIntents/environment debug-information warnings.

The isolated fixture/check compiler now enables Swift 6 `MemberImportVisibility`.
The compiled SDK CLI accepts manifest features with true/false fullscreen values
and rejects a string value. SDK usage snippets typecheck. The public JSON schema
defines an optional boolean defaulting to false; its syntax and field assertions
passed, but no external JSON-schema validator was installed for this work.

The app exposes `--preview-addon-widget-detail` and
`--check-addon-widget-detail`. The finite check drives native accessibility
actions and the real Back button, checking compact action separation,
same-lease refresh, stale controls, delayed A/B replies, rapid retargeting and
withdrawal. The actual signed compiled check was executed after the shell became
readable and returned exit 1: `Visible accessibility button unavailable: Mock
brightness 60% +`. A diagnostic rebuild reproduced the failure. The ordinary
widget is mounted in the visible expanded panel with its two SwiftUI button
proxies, but the hosting accessibility group reports zero children. A single
Debug activation experiment changed app activity from false to true, with the
same empty AX group and failure; that hypothesis was falsified and the activation
experiment was removed. This evidence does not identify a production detail
defect or qualify the native route. Logs are
`/private/tmp/cascade-widget-fullscreen-native-check.log`,
`/private/tmp/cascade-widget-fullscreen-native-diagnostic.log` and
`/private/tmp/cascade-widget-fullscreen-native-activation.log`.
The public accessibility hit test at each of the two mounted native button
proxy centers also returned only the empty hosting group. The check still
returned exit 1; no action fallback, visibility change or origin bypass was
introduced. Renderer/board/tile grouping was traced and no applicable parent
accessibility-hiding modifier was found. Environment versus implementation
remains unresolved, so this is an explicit failed qualification check, not a
production pass or a confirmed lock-only diagnosis. Final probe log:
`/private/tmp/cascade-widget-fullscreen-native-hit-test.log`.
The final diagnostic source was executed again and terminated in under one second
with exit 1. It reports: `Native check unqualified: no enabled AX button labelled
Mock brightness 60% +; see host snapshot; environment versus implementation cause
unresolved`. Evidence: `/private/tmp/cascade-widget-fullscreen-native-final.log`.
The check and preview together retain a valid
detail after completion for idle measurement; the check alone exits after its
result. This is programmatic app evidence when run, not physical input.

To finish qualification in an unlocked session, quit the normal app and run:

```sh
open -n -a /Applications/Cascade.app --args --check-addon-widget-detail --preview-addon-widget-detail
```

Verify the compact title, independent mock brightness control, native Back and
Escape; inspect header clearance and animations; then measure the same normal
closed/expanded scenarios as the baseline and the separately isolated detail
scenario. Capture stdout by launching the built executable directly for the
finite check. Multiple-display qualification needs physical displays.

## Normal relaunch

After the final finite check exited and released its fixture, LaunchServices
started the successful updated build normally on 2026-10-03 at 19:23:10 UTC,
without preview/check arguments: PID **51182**, executable
`/private/tmp/cascade-widget-fullscreen-feature-derived/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`.
The application link resolved to that bundle and exactly one intended process
was found. Record: `/private/tmp/widget-fullscreen-final-normal-relaunch.json`.
This proves relaunch/process identity, not unlocked visual/input qualification.
