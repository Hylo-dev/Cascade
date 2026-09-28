# Addon observation coordinator: delivery of 20 September 2026

**Outcome: PASS for the internal component**, after root review and Sol medium independent review with one round of fixes. The [Wayfinder ticket](../../../.scratch/cascade-product/issues/45-process-metrics-coordinator.md) is closed; C4 as a whole and the launcher stay open/blocked.

## Delivered increment

`ProcessMetricsCoordinator` groups explicit observation registrations and reuses `ProcessMetricsReader`/`ProcessMetricsReducer`. A single periodic deadline, initially 1 Hz and never more frequent, no catch-up of missed ticks and disarming on an empty set. Samples at job boundaries or under pressure do not postpone the periodic deadline. Conflicting identities and tokens are rejected; duplicate registrations keep the baseline; exact removal does not touch a replacement. A missing read is not equivalent to zero and does not block the others.

The component serializes the reads in its own actor but installs no timer/task and is not connected to the app or to the process authority. Maximum observation capacity 1,024 registrations, default 4: it is not admission of new processes nor an additional governor quota. A mismatched identity/observed exit withdraws only the registration, without freeing reservations or proving physical exit.

## Verification

- Terra medium: bounded survey of the frontier. Sol medium: implementation; a second Sol medium: independent review; root: code reading, requirements comparison, requested fixes and replay of the whole suite.
- 47 metrics tests in 2 suites PASS, including 14 new coordinator tests. First, the normal compilable scaffold failed behaviorally; the nanosecond-fractions regression failed with 5 expectations before the fix.
- **1,098 package tests in 97 suites PASS**, command `swift test --disable-sandbox --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-tests --skip-build --no-parallel`, Xcode-beta toolchain, in the desktop session. The same targets were compiled by the focused command before the replay.
- The baseline was 1,084 tests. Two AppKit `NSScreen.main` expectations did not pass in the sandbox; the same binaries passed in the desktop session, with no changes to those tests.
- The review fixed the clock advancing on duplicate registrations, the extreme time values, the loss of sub-nanosecond precision and a retain cycle in the fixture. The final code keeps `Duration` directly with bounded arithmetic. No important finding remains.
- Existing reader byte-identical; final hashes of the three reviewed files preserved. No other pre-existing source among the 388 initial inputs was modified.

## Build and launch

The first official build stayed stuck before compilation in `NSFileCoordinator`, while reading the iCloud project. A one-second sample documents the wait; only the related `xcodebuild` was interrupted.

The same official build then succeeded on a local copy with **479 inputs verified identical before and after the build**. SDK check: 4 packages, 11 targets, 90 Swift sources, 140 imports PASS. `scripts/build-development.sh`, Apple Development signature and `codesign --verify --deep --strict` PASS. The script updated `/Applications/Cascade.app` to the build in `CascadeDevelopment/Build/Products/Debug/Cascade.app`.

Normal close and relaunch verified: PID 10620 → **18882**, executable matching the Applications link and stable for 5 seconds. No new addon process or native prototype was activated.

[Evidence, logs and hashes](../../../.scratch/codex-addon/20260920-wayfinder-continuation/root-review.md); [final independent review](../../../.scratch/codex-addon/20260920-wayfinder-continuation/task-45-rereview.md); [launch result](../../../.scratch/codex-addon/20260920-wayfinder-continuation/delivery.json).

## Boundary and stopping point

Remaining: canonical native binding, driving from the shared wakeup, governor/health integration, enforcement and real process testing. macOS14/Intel, supervisor consumption and continuous profiles are not qualified.

The user requires a stop at a design choice or below 75% remaining budget. Remaining budget observed at delivery: **93%** (7% consumed). The stop concerns the [CPU burst semantics](../../../.scratch/cascade-product/issues/46-addon-cpu-burst-policy.md): the specification does not define how 100ms/job coexists with 50ms/10s. No policy was selected or implemented. The launcher stays blocked by the decision already made, without proposing it again.
