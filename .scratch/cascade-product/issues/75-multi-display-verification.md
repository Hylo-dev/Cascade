# Verify and deliver the multi-display notch

ID: 75
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/multi-display
Blocked by: 74

## Question

Implement and verify task 7 of the [multi-display plan](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) following the [spec](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). The execution tranche is authorized by the request of 25 September; close only with evidence and review.

## Answer

Implementation delivered on 26 September 2026. Added the verification of the shared lifecycle/deadline across three displays, updated the contracts and completed the cross-cutting review. The only final finding, early loss of the still-mounted instance during a replacement, was reproduced with the real controller and fixed through a union of the current/outgoing roots and a reconciliation before/after the application. [Final review](../../../.superpowers/sdd/2026-09-24-multi-display-notch/final-rereview-1.md): PASS/PASS.

Official Apple Development build succeeded, signature verified and `/Applications/Cascade.app` updated to the canonical build. Real restart verified: final process 39220 uses the updated CascadeDevelopment executable. Appearance UI, three modes, specific target and search verified on the built-in display; initial Follow focus preference restored.

Settings 17/17; new lifecycle regressions pass. The final full package (1,325 tests) is still exit 1: timeouts/assertions compared point by point with the baseline, and independent runtime modules unchanged. A fully green suite is not claimed. External hardware/mirroring and other unavailable native conditions, Spotlight end-to-end not observable through CUA and profiling not run remain explicit limits of the qualification, not successful tests. [Full record](../../../docs/superpowers/verification/2026-09-24-multi-display-notch.md), [plan](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md). No commit or merge; snapshot and evidence kept for the authorized in-place delivery.
