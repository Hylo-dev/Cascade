# Clarify how a CPU burst consumes the addon budget

ID: 46
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 45

## Question

Before connecting the CPU observations to violations, how do the candidates "50 ms over a sliding 10 s window" and "initial burst of 100 ms/job" coexist? Must the initial credit consume an addon budget that does not refill with new jobs/processes, or must it be additional for every job admitted by the host?

## Context

The [approved spec](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md) and the [C4 plan](../../../docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md) name both values but do not define their precedence, exemption or accumulation. The reader, reducer and coordinator deliver observations; AddonHealthStore accepts already classified violations, without defining the CPU budget. The [survey of 18 September](../../codex-addon/20260918-continuation/addon-remaining-work-audit.md) had also explicitly left the definition of the intervals/bursts open. An 80 ms job would be within the burst but beyond the ordinary 50 ms window: the classification cannot be derived from the two numbers alone. Restarting many jobs must not implicitly become a waiver of the quotas.

## Concrete alternatives to decide

1. **Shared addon credit (recommendation):** initial capacity 100 ms, recovery of 5 ms of CPU per elapsed second; every piece of work consumes the same credit, retained across jobs and provider restarts. The spec would explicitly move from a rigid sliding window to a refillable budget: it allows the initial spike but limits sustained consumption. The credit is not regenerated simply by creating a job.
2. **Additional burst for every job:** keep an additional 100 ms per admitted host job and 50 ms/10 s for the remaining work. A cumulative limit on bursts/job frequency must also be set; without that limit a sustained cap per addon cannot be inferred.

These are different policies, not interchangeable implementation details. Neither is applied by this ticket. The choice applies only to event-driven addons; continuous UI/audio profiles, attribution of shared services and native qualification remain separate. The launcher block is neither changed nor reopened.

The user asked to stop execution at a necessary design choice. Complete and verify the coordinator increment already in progress, then present this point; no worker implements the policy before the answer.

## Answer: user decision, 20 September 2026

The user chooses "the recommended one": a shared credit per addon with an initial capacity of 100 ms and a refill of 5 ms CPU/monotonic second. New jobs and provider restarts do not re-create the credit. This explicitly replaces the previous rigid 50 ms/10 s sliding window and the additional 100 ms/job burst.

The decision concerns event-driven addons. It grants no waiver to continuous UI/audio profiles, does not resolve the attribution of shared services or the native verification, and does not open the launcher. The alternatives above are historical: the first one is now approved.
