# Independent calibration of the CPU units: 18 September 2026

**PASS on the reading and reduction path, limited to macOS27 arm64 and to the test's process.** Identical copies of the two production sources were compiled with a local diagnostic. The native reader acquires the counters; the reducer applies the Mach conversion. The `getrusage(RUSAGE_SELF)` reference sums user/system seconds and microseconds separately, without reusing the Mach timebase or counters to build the reference.

## Results

Effective timebase125/3, Swift6.4 and SDK CLT27.0, macOS27.0 build26A5425a. The converted values all fall inside the reference intervals; the tolerance of2000µs declared before the test was not needed.

| Sample | Reducer CPU, µs | POSIX interval, µs | CPU / acquisition time |
| --- | ---: | ---: | ---: |
| 1 | 150064.791 | 150062–150074 | 99.998473% |
| 2 | 150021.583 | 150016–150027 | 100.000111% |
| 3 | 150020.666 | 150014–150027 | 97.002418% |

The references are acquired before and after each reading. The interval of the difference is `[current before − previous after, current after − previous before]`; widths12, 11 and13µs. The slight excess over100% in the second sample falls within the acquisition/quantization uncertainty. The negative checks on the same data reject ticks treated as nanoseconds, as microseconds or converted with an inverse timebase: no additional load.

Three serial loads recorded about0.45s of CPU; the value454435µs is the CPU from birth **to the last acquisition**, not the exact measurement at exit. The runner waited for the normal exit with status0 in0.6898s. The separate compilation took33.93s. The workload limits and the timeouts are diagnostic guards, not a CPU enforcement mechanism for the process. Private cache removed; no change to production, tests or the app.

[Preserved report and probe](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-report.md), [raw observations](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-observations.json), [diagnostic source](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-main.swift), [probe command/outcome](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-probe-log.json), [evidence hashes](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-evidence-sha256.json), [independent review PASS](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-independent-review.md). The review recomputed the arithmetic and the hashes without rerunning the test. The clarifications above take precedence over the more general wording of the frozen report.

## Limits

The APIs may share the kernel's accounting: the comparison qualifies scale and conversion, not the absolute precision of that accounting. The percentage reuses the reducer's time denominator; it is not an independent measurement of the clock's accuracy. There is no experimental nanosecond precision, nor a hermetic archive of the compiler/SDK and the inherited environment.

Identity is obtained explicitly from the diagnostic process alone. No addon authentication, RSS measurement, macOS14/Intel guarantee, common sampling/disarming, threshold, quota refund or managed exit is qualified. Full C4 and C0d remain open; the C0d driver was neither run nor modified. The result is a read-only verification of the already delivered code, not a new build of the app. The services integration continues separately.
