# Share Live Activity selection and lifecycle

ID: 71
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 69

## Question

Implement and verify task 3 of the [multi-display plan](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) following the [spec](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). The execution tranche is authorized by the request of 25 September; close only with evidence and review.

## Answer

Separate compact/expanded selection and per-instance visibility union delivered. The copies share activation and deadline; terminal revocation extended to outgoing instances, bounded state and a fallback independent of the live role. 57 targeted tests passed; independent review PASS/PASS after two scoped fixes. The coordinator will also consume the new view validity contract.
