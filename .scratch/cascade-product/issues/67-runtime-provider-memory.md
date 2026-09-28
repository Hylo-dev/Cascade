# Connect provider memory, health and admissions

ID: 67
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 66

## Question

Compose into the runtime the physical RAM of the owner only, episodes per incarnation, independent CPU/RAM blocks and a single moderate incident per owner/round. Expected severe stop with no retry, reserves held until exit. Stale samples and wake do not reset episodes; recovery valid only on the owner's own process. Sol medium implements after 66, the root and the reviewer verify.

## Answer

Sol medium implemented the owner-only provider profile with episodes per incarnation, independent CPU/RAM pauses and deduplicated moderates; expected severe stop with no retry and reserves until exit. Root and independent Sol reviews PASS. 10 RAM tests, 176 targeted and 1,222 full/115 suites PASS; official signed build from 500 inputs and updated launch at PID 21839 verified. [Verification and limits](../../../docs/superpowers/verification/2026-09-23-addon-provider-memory.md). Launcher blocked; follow-up dependent on native tests already suspended, remaining quota 77%.
