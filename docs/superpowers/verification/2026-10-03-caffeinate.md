# Caffeinate verification

Date: 3 October 2026. Branch: `cava/caffeinate`. Base: `39d86ec`.

## Build and isolation

The working checkout contains pre-existing staged iCloud duplicate files. They
were preserved. An archive of the base commit in
`/tmp/cascade-caffeinate-verification` received only the feature's canonical changes
and local signing configuration. All 23 changed/new source, resource and check
files match that snapshot by SHA-256. Documentation is not compiled.

Final command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CASCADE_DERIVED_DATA=/tmp/cascade-caffeinate-derived \
/bin/zsh scripts/build-development.sh
```

Result: `BUILD SUCCEEDED`. The build script updated `/Applications/Cascade.app`
to `/private/tmp/cascade-caffeinate-derived/Build/Products/Debug/Cascade.app`.
`codesign --verify --deep --strict` succeeded. The app bundle contains
`CaffeinateCredits.md`. Existing instances were terminated; the final build
restarted as PID 94214, with one Cascade process and the intended executable.
Build log: `/tmp/cascade-caffeinate-final-build.log`.

## Automated and native evidence

- Baseline integration: full SwiftPM suite passed 1,842 tests, serial execution;
  app suite passed 71 tests in 11 suites.
- After shutdown/layout corrections: both Caffeinate plugin tests passed, and
  all four Caffeinate app tests passed, including late acquisition after disable,
  stale accepted controls, unavailable lease and rendering inside the default
  168x74-point tile.
- The injected assertion check covers successful system/display ownership,
  repeated stop, partial-acquisition rollback, invalid replacement preserving an
  active session, and ownership retained after failed release for a later retry.
- The `--native` check creates real IOKit system and display assertions with a
  two-second deadline. Both appear active in powerd. After expiry they disappear
  from its active list without an app stop callback; the check allows bounded
  observation latency. Explicit release then removes their property records.
  `IOPMAssertionCopyProperties` retains the earlier level after native TurnOff,
  so expiry must be checked using `IOPMCopyAssertionsByProcess`'s active list.
- `pmset -g assertions` after the final restart showed no remaining assertion
  named `Cascade Caffeinate:`.
- Independent review's fixed-height overflow finding was corrected with 3x2/4x2
  sizes and proposal-filling layout. Follow-up review found no further P1/P2 issue.
- `git diff --check` passed for the feature's tracked modifications.

Logs: `/tmp/cascade-caffeinate-package-tests.log`,
`/tmp/cascade-caffeinate-app-tests.log`,
`/tmp/cascade-caffeinate-final-package-tests.log`,
`/tmp/cascade-caffeinate-final-app-tests.log`.
Offscreen preview: `/tmp/cascade-caffeinate-widget-preview.png`.

## Runtime samples and limits

Short samples with the expanded-notch inspection argument and Caffeinate inactive:

| Sample | CPU | RSS | top footprint |
| --- | ---: | ---: | ---: |
| Before, PID 89625 | 0.0% | 99,968 KiB | 32 MiB |
| Initial feature build, PID 92389 | 0.0% | 98,416 KiB | 30 MiB |

These are short inactive samples, not evidence of an attributable memory saving
or active-session/wakeup budgets. The final restarted process measured 0.0% and
94,096 KiB RSS (27 MiB top footprint), but the Mac was locked during that check,
so it is not a comparable visual scenario.

## Initial UI revision: adaptive size, finite motion and in-notch options TODO

The user capped the widget at 4x2, requested a text-free icon size, removed the
capsule background, and required options to cover the other widgets inside the
notch. The final manifest declares 4x2 (default), 3x2 and 1x1. ViewThatFits chooses
between text and a 32-point cup. The full face has a 44-point cup. There is no
capsule background or intermediate Updating label.

The symbol is separate from the revision-bound button, retaining its node model
through busy and accepted-state publications. Its off/on name change triggers a
finite native bounce; Reduce Motion removes that effect and the symbol transition.
The same shared renderer is used through the existing opt-in symbolEffect marker.
No repeating animation, timer, frame callback or provider wake is introduced.

The shared addon contract has no contextual options-page route. The external
AppKit menu was removed; details are passive. ADDON-NOTCH-OPTIONS in docs/TODO.md
records the common SDK/broker/visibility route, overlay ownership, restore/dismiss
behavior, multi-display handling and subsequent Caffeinate controls. Native
session duration/display support and bundled credits are retained.

Verification of this revision:

- Two Caffeinate tests first failed against the earlier view on actual assertions
  (six issues: external options control, old glyph, missing fit variants, capsule,
  absent symbol animation and Updating label), then passed against the revision.
- Twenty relevant package tests passed (Caffeinate, bundled manifests and node
  store). Nineteen shared rendering/router tests passed.
- Four app tests passed, with two cases for stale controls covering both full and
  compact toggle IDs. Offscreen images fit 226x74, 168x74 and 52x34-point proposals;
  the glyph model remains identical across busy and active publications.
- Follow-up independent review found no concrete P1/P2 issue.
- All ten revision source/resource/test files matched the verified snapshot by
  SHA-256; git diff --check passed.
- Canonical final build succeeded and updated /Applications/Cascade.app. Restart
  initially hit LaunchServices error -600; retry with open -n succeeded. The final
  process is PID 96932 at the intended derived-data executable. Signature, bundled
  credits and absence of residual Caffeinate assertions were verified.

Logs: /tmp/cascade-caffeinate-layout-red.log,
/tmp/cascade-caffeinate-layout-green.log,
/tmp/cascade-caffeinate-renderer-tests.log,
/tmp/cascade-caffeinate-layout-app-tests.log,
/tmp/cascade-caffeinate-layout-build.log.
Previews: /tmp/cascade-caffeinate-wide-preview.png,
/tmp/cascade-caffeinate-medium-preview.png,
/tmp/cascade-caffeinate-icon-preview.png.

The inactive expanded-notch inspection scenario measured 0.0% CPU before and
after this revision once settled. Before: 126,480 KiB RSS in the long-running
original process. Initial relaunch samples showed 10.7% and 14.4% CPU; about two
minutes later, three samples were 0.0%, with 102,640 KiB RSS. Different uptime
makes these memory samples unsuitable for attributing an improvement. Initial
activity was transient; no sustained idle regression was observed in these short
samples. They do not qualify animation CPU/wakeups or an active Caffeinate session.

## Pending real-app interaction

The native automation capture exposes no widget controls and returns a white
image. An earlier attempt also failed while the Mac was locked. The latest
pre-change attempt no longer reported the lock but still returned white. The
renderer previews are synthetic: physical resizing, cup clicks and animated
visual acceptance remain unverified, and matching before/after driven animation
CPU/wakeup measurements could not be performed through that inaccessible UI.

With visible access to the running app, enable/add Caffeinate, resize between
4x2/3x2 and 1x1, check the cup-only fallback, toggle both sizes, test Reduce Motion,
and confirm assertion cleanup when disabling the plugin or quitting. Options
inside the notch remain an explicit addon TODO, not a delivered floating menu.

## Slot correction after the user's 6x2 report

The earlier footprint claim checked raw manifest dimensions and was incorrect.
GridSpan.init(PluginWidgetSize) doubles columns: the previous 3x2 declaration
rendered as 6x2 and the revised raw 4x2 declaration would allow 8x2. Caffeinate
now declares 2x2 and 1x1, producing effective grid footprints 4x2 and 2x1. Its
wide face has a 104-point minimum with a 36-point cup; the compact face stays
text-free. In the representative 400x112-point grid interior, the actual router's
spans resolve to 110x74 and 52x34-point tile frames, and both render within them.

WidgetHost reconciles obsolete saved sizes on registration and restoration,
covering both arrival orders. It keeps the origin and chooses the largest
supported size contained by the old rectangle; if none fits, the placement is
removed so the widget appears in the gallery. Unknown providers retain their
saved placement until they register. Writes use the existing background store.

Regression evidence: the real router test failed with default GridSpan(8,2)
and the saved-state test failed on 6x2/8x2 before the fix. Afterward, 22 relevant
package tests and four app tests passed, including two full/compact action cases
and both registration/restoration orders. Independent review found no P1/P2.
Six corrected code/resource/test files match the build snapshot by SHA-256.
Canonical build succeeded and updated /Applications/Cascade.app. Before restart,
the real preference record contained a 6x2 Caffeinate tile at column 4, row 1.
After restart, the actual saved record contains 4x2 at the same column 4,
row 1. One final Cascade process (PID 98344) runs the intended updated executable;
codesign verification succeeded. This confirms the real saved-state migration,
independently of the unavailable UI capture.

Logs: /tmp/cascade-caffeinate-slots-red.log,
/tmp/cascade-caffeinate-slots-app-red.log,
/tmp/cascade-caffeinate-slots-green.log,
/tmp/cascade-caffeinate-slots-app-green.log,
/tmp/cascade-caffeinate-slots-build.log.

Durable check rule: assert the published widget's routed GridSpan and resolve
its actual tile bounds; a manifest-only width check cannot prove grid dimensions.
