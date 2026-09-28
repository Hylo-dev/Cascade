# Process observations verification: 18 September 2026

**PASS for bounded reading and reduction; full C4 still partial.** Added an internal reader of the public `proc_pid_rusage` v0 API and a pure reducer of CPU intervals. Identity observed in the same record, missing counters distinguished from zero, Mach conversion with checked overflow, and memory bounded to one previous sample. No polling, termination, authentication or link to enforcement introduced. [Contract and limits](../../architecture/addon-resource-observations.md).

## Checks

- 33 targeted tests / 1 suite PASS, including an ABI check that reads only the already existing test process. Behavioral RED verified; two earlier compilation errors preserved without presenting them as behavioral RED.
- Full suite: **929 tests / 85 suites PASS**: Runtime 611/49, Presentation 66/7, Kit 170/19, Contracts 65/8, Tool 17/2. UI tests run with access to the graphical session.
- Independent review Codex Sol high PASS within scope. Two wording P3s corrected: the injected test does not observe the flavor of the native call; the still missing independent CPU comparison and the limits on recognizing new executions of the same image are documented explicitly.
- Apple Development build succeeded from a local snapshot of 415 files, deep/strict signature valid and /Applications/Cascade.app link updated. Normal quit and relaunch: PID 17941 → 25731, single expected executable, stable for 5 seconds.

[Implementer report](../../../.scratch/codex-addon/20260918-continuation/metrics-report.md), [independent review](../../../.scratch/codex-addon/20260918-continuation/metrics-independent-review.md), [suite audit](../../../.scratch/codex-addon/20260918-continuation/metrics-test-audit.json), [build manifest](../../../.scratch/codex-addon/20260918-continuation/metrics-build-snapshot-manifest.json), [signed build](../../../.scratch/codex-addon/20260918-continuation/metrics-signed-build.log), [relaunch](../../../.scratch/codex-addon/20260918-continuation/metrics-restart-evidence.json).

After the suite and the build, the only difference in the three implementation files is the correction of the test comment from “PID/flavor” to “PID/order”; no executable statement changed. The build manifest correctly preserves the historical comment; the review addendum records the final hash. No test rerun for this purely descriptive change. The ScaffoldWriter comment difference detected in the worker's audit had already been corrected and reviewed in the previous delivery: [root reconciliation](../../../.scratch/codex-addon/20260918-continuation/metrics-root-scope-reconciliation.json).

## Missing qualifications

The counter units are supported by Apple's sources and by synthetic tests, not by a measured independent calibration. The ABI test took place on arm64/macOS 27; macOS 14 and Intel were not qualified. Still remaining: authenticated addon/process association, common sampling and disarming, integration with health and thresholds, measurement of overruns and actually observed termination. Metrics or ESRCH alone do not authorize releasing the reservations. The C0d gate keeps `exit 78`; no qualification of the launcher or of the full native control.

## Later update: independent calibration

The missing calibration described above refers to the initial delivery. The [later independent test](2026-09-18-addon-process-cpu-calibration.md) verified the units with identical copies of the reader/reducer against getrusage, with a PASS review. Qualification limited to macOS27 arm64/self-process; no source modified and no extension to enforcement, macOS14/Intel or managed exit.
