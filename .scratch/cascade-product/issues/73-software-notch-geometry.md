# Design the software Notch and the droplet Dynamic Island

ID: 73
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/multi-display
Blocked by: 72

## Question

Implement and verify task 5 of the [multi-display plan](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) following the [spec](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). The execution tranche is authorized by the request of 25 September; close only with evidence and review.

## Answer

Implemented the software protrusion, independent activity measurements and the droplet outline. Transitions keep shape, mask and hit test consistent; a style change closes the surface first. Compatibility of the public context preserved.

Evidence: 103 tests in six suites, 30 coordinator tests and a PNG comparison of the renderer. Independent review PASS/PASS after one corrective round: [report](../../../.superpowers/sdd/2026-09-24-multi-display-notch/task-5-rereview-1.md). The synthetic geometric comparison does not qualify a physical external monitor; the connection of Settings and Spotlight is in the next ticket.
