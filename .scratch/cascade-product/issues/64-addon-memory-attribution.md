# Define whom the observed memory of services is attributed to

ID: 64
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 63

## Question

Should the RAM footprint of a process that offers a shared service affect only the health of the owner addon, or also that of its direct and indirect consumers?

## Context

The [conservative CPU](55-addon-delegated-cpu-attribution.md) and [active chains](57-addon-transitive-cpu-attribution.md) decisions concern work consumed during an interval. Observed RAM is instead a current resident quantity: it includes runtime, libraries and shared caches, with no measure of the memory caused by a single request. The reader exposes the footprint but the coordinator does not classify it yet. [Survey of the sources](../../codex-addon/20260922-transitive-cpu/post63-memory-audit.md).

## Alternatives

1. **Only the addon that owns the process (recommended).** B's RAM affects B even if A uses one of its services. Each process is observed only once; its footprint is not copied into the consumers. It matches the available physical measure and avoids penalizing A for B's libraries and caches that others also use. On its own it does not prevent shifting a request that increases memory onto the service: quotas on the resources controlled by the broker are still needed.
2. **Active consumers too, as for the CPU.** B's RAM is also counted for A and for the active ancestors, deduplicating identity/process. It counters the shifting of costs onto services, but it can limit or penalize an addon for resident memory it did not cause. The global physical total is still counted once.

This choice concerns attribution only. The provider's 64/96 MiB and the UI's 128/192 MiB remain candidates: effective thresholds, the provider/scene sum and episode counting require a later contract before enforcement. No option reopens the launcher or turns the pure runtime into a native guarantee. No RAM implementation is authorized by the survey alone.

## Answer

User choice: **1: only the addon that owns the process.** An observed footprint
belongs exclusively to the verified identity of the measured physical process. It is not
copied to direct or transitive consumers of services, even if the broker interest is
canonical and active. The physical measure and the global total are still counted once.

This resolution does not approve thresholds, provider+UI aggregation, episode
counting, quarantine or a stop action; the provider's 64/96 MiB and the UI's 128/192 MiB remain
candidates. The native identity, read and stop gate stays closed.

Documentation updated by Terra medium and reviewed by the root; no source modified. [Verification of the decision and restart](../../codex-addon/20260922-memory-owner/verification.md).
