# Multi-display notch verification

Run: 25–26 September 2026. Scope: [specification](../specs/2026-09-24-multi-display-notch-design.md), [plan](../plans/2026-09-24-multi-display-notch.md) and [current contracts](../../architecture/live-activity-contracts.md).

## Environment and boundaries

Observed host: macOS 27.0, build 26A5425a; Xcode 27.0, build 27A5252f, selected through `/Applications/Xcode-beta.app/Contents/Developer`. The macOS 14 deployment target does not demonstrate runtime compatibility on macOS 14, which is not available in this session. Physical inventory: only the built-in Color LCD, main and online, mirroring disabled. No external display available.

The Swift Package tests use `/private/tmp/cascade-multidisplay-build`, caches `/private/tmp/cascade-clang-cache` and `/private/tmp/cascade-swiftpm-cache`. The first baseline build in `.build` inside iCloud was blocked by signing/resource fork; the external scratch avoids that condition. The `codex/interactive-notch` working tree remains uncommitted and keeps the concurrent Addon changes. The per-task snapshots, rather than HEAD, define the reviewed diffs.

The public AppKit probe run by the controller sees `screens=0 main=nil` in the sandbox and `screens=1 main=Built-in Retina Display` in the graphical session with escalation. This justifies the environment of the native tests, without qualifying the multi-monitor behavior.

## Automated tests

### Lifecycle and expiry on three displays

`NotchDisplayCoordinatorTests.threeDisplayCopiesShareOneLifecycleAndExpiry` uses three fake surfaces, the real shared host and its injected clock. It verifies three factories after a single activation, all copies of the same instance, all → focus → all switches with no new surfaces and no intermediate suspension, then an expiry reconciliation that empties every copy with a single suspension. A second reconciliation does not change projections or counts.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-swiftpm-cache \
swift test --disable-sandbox --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-multidisplay-build \
  --filter 'NotchDisplayCoordinatorTests|LiveActivityHostTests'
```

Result: **exit 0, 82 tests in 2 suites passed**. Log: `/private/tmp/task-7-covering-tests.log`. It is a verification of already implemented behavior: no artificial RED and no change to production code.

Reading `Core/Activities/LiveActivityHost.swift` confirms a single `deadlineTask` field: `scheduleExpiration()` picks the next expiry/stale date, cancels the previous task when the deadline changes and calls `expireNotices()`. The test invokes the reconciliation directly with the advanced clock: it does not count real system wakeups, nor does it demonstrate an energy profile.

### Final integration

The baseline before the changes, outside iCloud, is **exit 1**: 1,222 tests, 16 Addon runtime issues and one timeout/assertion `controlDragKeepsExpandedContentAliveUntilMouseUp` in the controller. Full log: `/private/tmp/cascade-multidisplay-baseline-clean.log`; the exact list is preserved in `baseline-test-issues.txt` in the SDD dossier. The issue counts are not equivalent to the number of failed tests.

**Final full-package after the fix from the overall review: exit 1, 1,325 tests across five targets**, log `/private/tmp/cascade-multidisplay-final-package-after-review.log`. Run by the controller in the graphical session: no crash from a missing `NSScreen`. The isolated diagnostic reruns described below do not change this outcome of the full run. The previous integrated run, before this fix, had 1,323 tests and seven issues in total (`/private/tmp/cascade-multidisplay-final-package.log`); it remains separate historical evidence.

| Target/group | Final outcome | Comparison with the baseline |
| --- | --- | --- |
| Runtime Addon | 832 tests; 19 issues | 13 issues repeat baseline cases; another 6 belong to `brokerPublicationWaitsForTheBlockedPhysicalObservation`, which passed in the baseline. This second case passes in isolation; exact cause not demonstrated. |
| Addon | 112 tests passed | No failures |
| CascadeKit | 272/273 passed; one issue in `controlDragKeepsExpandedContentAliveUntilMouseUp` | Same assertion `fixture.controller.state == .closed` as the baseline (now line 1385, previously 1012). Recurrence of the same symptom; it does not make the suite green. |
| Other targets | 91 + 17 tests passed | No failures |

The six issues of the broker case are recorded in `ServiceBrokerCPUAttributionTests.swift` at lines 314 and 286: one `Acquisition task did not start` and five `Observation release timed out`. They are not six distinct tests. The test uses `DispatchSemaphore` with a two-second timeout inside asynchronous work. The isolated suite `ServiceBrokerCPUAttributionTests` passes **8/8, exit 0, 0.032 s**, log `/private/tmp/cascade-multidisplay-final-runtime-isolation.log`. The isolated controller also passes **1/1, exit 0, suite 0.344 s**, log `/private/tmp/cascade-multidisplay-final-drag-isolation.log`.

The controller compared byte for byte against the baseline snapshot `Package.swift`, the ServiceBroker test and the four modules runtime (61 files), contracts (58), presentation (6), SDK (14): identical, with no added/removed files. The runtime target does not depend on CascadeKit/app. The runtime failure is therefore **new in the run, in unchanged modules, not reproduced in isolation**. Contention/scheduling is a plausible explanation, not a demonstrated causality. Those modules/tests were not modified, nor were assertions weakened, to get green. The full run remains exit 1.

**Final Settings: 17/17 passed, exit 0, TEST EXECUTE SUCCEEDED**, log `/private/tmp/cascade-multidisplay-final-settings-prebuilt.log`. In the graphical session, the controller ran the final bundle already built and signed with Apple Development during the two regressions of fix round 3:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Cascade.xcodeproj -scheme Cascade \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/cascade-task6-fix3-derived \
  test-without-building -only-testing:CascadeTests/SettingsTests
```

This final runtime test replaces the earlier partial evidence of 15 pre-fix tests and two final regressions. It does not rebuild the bundle and does not constitute the final delivery build. The approval timeouts of the earlier attempts prevented the commands from launching: they were neither security rejections nor build/signing errors.

The earlier verifications constitute bounded evidence: Task 5, 103 tests/6 suites of geometry and transitions; Task 6, 44 coordinator tests and the Spotlight coverage reported in the dossier. These counts are not added to the final suites, because they overlap. The final Task 6 review is PASS/PASS after three scoped fixes.

### Final fix of the transition between instances

The overall review reproduced an A→B replacement of the same activity in which A was still mounted but not yet recorded as outgoing. The previous union could suspend it and revoke its eligibility too early. Now the controller exposes the current and outgoing roots; the coordinator reconciles the lifecycle before the factories and again after the application. The identical application during the return to the compact shape is idempotent.

The two regressions with the real controller start from an A that is actually mounted, without artificially arranging the retention: animation and Reduce Motion pass 2/2 after the recorded RED. The updated coordinator test passes 1/1 and checks activation before the factory and a single final release. Logs: `/private/tmp/final-fix-red-mounted-handoff.log`, `/private/tmp/final-fix-green-mounted-handoff.log`, `/private/tmp/final-fix-green-coordinator-handoff.log`. The relevant run of 172 tests has only the same documented drag failure (`/private/tmp/final-fix-covering-tests.log`); the subsequent full-package above verifies the corrected integrated source. No assertion was weakened.

The 17 Settings tests verify the final settings/Spotlight source, which remained unchanged during this controller/coordinator fix; the core fix is covered by the new tests and by the new full run. The final scoped review is **PASS/PASS**, with finding I1 resolved and no regression caused by the fix detected (`final-rereview-1.md`). The updated build succeeded and the available native verification is reported below.

## Physical verification matrix

The fakes prove routing, selection, ownership and lifecycle; they do not prove AppKit window stacking, the desktop actually visible or hardware behavior. The PNG produced by the real rendering path, `software-notch-comparison.png`, was inspected with outcome PASS for both styles at rest, half and full opening, with/without activity. It remains synthetic geometric evidence.

| Required test | Available evidence | Native status |
| --- | --- | --- |
| Hardware + external, no activity, two styles | Fake inventories and renderer PNG | Not verified: external display absent |
| Two screens without a physical cut-out, independent styles | Synthetic routing/styles and geometry | Not verified: hardware absent |
| All, two activities, opening on A and copies on B | Coordinator/host tests, separate compact selection | Not verified on multiple physical displays |
| Window focus A, mouse B, local widget opening | Resolver and routing with injected input | Not verified on multiple physical displays |
| Window movement/change within the same app | Monitor/resolver and stable fake panels | Not verified on multiple physical displays |
| Specific B, UUID disconnection/reconnection | Inventory/routing tests | Not verified: external display absent |
| A open, request B then C, hover cancellation | Handoff/generations/still-valid request tests | Not verified on three physical displays |
| Arrival/expiry during morph | Transition tests and new shared expiry test | Not verified during native morph |
| Lock/unlock and stop/start | Lifecycle, invalidation and cleanup-order tests; real quit/relaunch completed | Relaunch verified; native lock/unlock not exercised |
| Lid closed | No physical evidence | Not verified |
| Fullscreen, Spaces, Mission Control | No native session exercised | Not verified |
| Mirroring | Normalized synthetic topology | Not verified: physical mirroring absent |
| Reduce Motion/Transparency, VoiceOver | Geometry tests; shared path for visual fallback | Native operation/accessibility not verified |
| Settings, popover, Spotlight | Ownership/anchor tests; signed Settings; Settings UI tested on the built-in display | Multi-display not verified; native Spotlight not qualified because of a tool impediment |

## Resources at rest and app delivery

The three-display test demonstrates a single activation and suspension of the provider, with no reallocation of surfaces when the focus changes. The controller source stops the morph and the host owns a shared scheduler. Music progress uses `TimelineView` in the expanded view during non-stale playback; the validity of the roots is covered by the host/controller tests. **Native profiling not performed**: the number of display links or TimelineViews active at rest was not measured, nor CPU, memory or wakeups. Reading the source does not replace this measurement.

**Final build and relaunch: completed on 26 September.** `scripts/build-development.sh` on the corrected source finished with exit 0 and `BUILD SUCCEEDED`; log `/private/tmp/cascade-multidisplay-final-build-after-review.log`. The Addon boundary check and the deep/strict signing succeeded. Apple Development signing, team `A6A5HQL6K4`, bundle `hylo.Cascade`. The link `/Applications/Cascade.app` points to the canonical build `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeDevelopment/Build/Products/Debug/Cascade.app`.

The instance observed before the relaunch had PID `14174`. Cascade was quit, reopened and finally launched with its own `--open-settings` option for the UI test. The final verified process has PID **39220** and uses exactly `CascadeDevelopment/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`; a final read of the link confirms the same destination. No app code changed after this build.

On the built-in display the closed hardware shape is visible. The native Appearance window shows the Built-in Retina Display row with status “Notch hardware” and the three Live Activities controls. “Tutti gli schermi” and “Schermo specifico” were selected; the latter shows the picker with the name and UUID of the built-in display. The initial preference **Segui il focus** was restored and verified. The searches “Dynamic Island” and “activity” return the relevant controls. Settings remains usable and closes normally. These observations qualify only the available display, not physical multi-monitor routing or stacking.

The native Spotlight test was not completed. After the open command, CUA could not open/observe `com.apple.Spotlight`: LaunchServices/RBS returned `Launch failed` (RBS code 5, POSIX error 162); the inventory available to the tool did not expose Spotlight/field. Opening, typing into and closing the native field were not observed, so no success is claimed and the impediment is not attributed to Cascade code. The state and integration tests remain the available evidence.

The successful build and relaunch do not by themselves qualify multi-monitor. Profiling, VoiceOver, native accessibility preferences, lock/unlock, Spaces/fullscreen and the macOS 14 runtime remain within the limits stated above.

## Preserved evidence

The local dossier `.superpowers/sdd/2026-09-24-multi-display-notch/` contains `final-verification-results.md`, `progress.md` with the rulings, per-task reports/reviews, source snapshots and `software-notch-comparison.png`. The `/private/tmp` paths identify the logs actually produced on this host and are not guaranteed portable artifacts. The controller's final observations are integrated above; the combinations not run remain explicitly unqualified.
