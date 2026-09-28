# Charge CPU intervals to verified consumers

ID: 56
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 55

## Question

Extend the coordinator's accounting with verified recipients for every physical binding, produced later by the runtime's canonical ledger. The entire interval goes to the provider and to every distinct consumer; same CPU account, no duplication of readings or of the physical total. Bounded and atomic preflight, errors and incomplete intervals propagated, one classification per owner/round. Keep the pre-existing behavior when no attributions exist. Sol medium implements; the root and an independent review verify. This unit does not declare the attribution wired to the broker or the app.


## Answer

Completed on 22 September 2026 by Sol medium with root and independent Sol review PASS. The coordinator accepts verified recipients per exact binding and charges them in the same physical round: it deduplicates self/duplicates, same persistent account, one final classification per owner, no duplication of measurements. Complete validation and admission of the new accounts before any reading or change; input that is not due does not create accounts. Incompleteness and failure stay explicit. The original arithmetic interval is kept by using charge per row, including the UInt64.max+1 regression still valid within credit; failure at the real debt limit stays persistent.

Eight new tests; 126 targeted tests and 1,161 full tests/105 suites PASS, exit 0. [Independent review](../../codex-addon/20260922-delegated-cpu/task-56-independent-review.md), [evidence and delivery](../../../docs/superpowers/verification/2026-09-22-addon-delegated-cpu.md). The broker/runtime producer is not implemented: the choice on indirect recipients remains in [Decide CPU attribution in service chains](57-addon-transitive-cpu-attribution.md). No native activation or SDK change.
