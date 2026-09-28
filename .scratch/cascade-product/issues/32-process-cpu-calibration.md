# Independently verify the CPU metric units

ID: 32
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 25

## Question

Compare the CPU reader already delivered with an independent measurement on the test's local process, to verify the units without introducing a launcher, control of other processes or managed-exit guarantees.

## Context

Explicit C4 requirement on independent calibration, still open in the [metrics verification](../../../docs/superpowers/verification/2026-09-18-addon-process-metrics.md). Diagnostic test limited to the current machine and to its own process; production sources unchanged. The macOS 14/Intel qualification and C0d remain separate.

## Progress

Taken on to define and run a short, bounded check, with the test sources, hashes, raw measurements and limits kept. No result declared yet.

## Answer

Three samples of the exact copies of the reader/reducer agree with the POSIX getrusage intervals; independent review PASS, sources unchanged. [Evidence and limits](../../../docs/superpowers/verification/2026-09-18-addon-process-cpu-calibration.md). The result qualifies only the CPU scale on macOS 27 arm64/self-process; complete C4 and native control remain separate.
