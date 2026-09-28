# Define provider RAM thresholds and incidents

ID: 65
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 64

## Question

Which initial profile should turn a provider's valid footprint into a reduction of admissions, a health incident or a stop request? The proposal concerns only event-driven providers, not UI scenes or continuous audio.

## Context

[Attribution to the owner only](64-addon-memory-attribution.md) approved. The spec contains a 64 MiB target and a 96 MiB candidate threshold, but it does not say whether 64 MiB is already an incident, how to distinguish repeated episodes, or when to reopen admissions. ResourcePolicy's preventive reserves are a different mechanism. The footprint is already available in the physical batch; adding a classifier without these rules would invent behavior. [Survey and proposal](../../codex-addon/20260922-memory-owner/task64-report.md).

## Alternatives

1. **Progressive reduction with distinct episodes (recommended).** Adopt 64/96 MiB as the parameters of the first internal provider profile: above 64 MiB and up to 96 MiB inclusive, a new moderate episode closes only new admissions; a valid current sample at 64 MiB or less closes the episode and removes only the RAM block. A continuous stay above 64 MiB counts once, not at every sample. A new verified process can produce a new episode; wake, missing measurements and a new registration of the same process neither reset the block nor multiply incidents. Above 96 MiB, an immediate stop request at the first valid sample, with no additional grace; not a proof that the exit happened. The severe case prevails and does not also count as moderate in the same round.
2. **Severe threshold only.** 64 MiB stays an informational target with no pause and no moderate RAM incidents. Above 96 MiB a valid sample requests the stop. Simpler and tolerant of spikes, but it gives up the progressive intervention and the quarantine from moderate RAM episodes.

## Contract of the first alternative

- Unit MiB = 1,048,576 bytes; a missing/stale value or a wrong identity is not zero, and it neither opens new episodes nor reopens admissions. The footprint can be valid even at the first observation or when only the CPU computation fails.
- CPU and RAM keep independent blocks: new work is admitted only when neither of the two forbids it and the version is not in quarantine. Work already admitted keeps its deadlines; no new queue, replay or automatic deletion of its data.
- Use the shared per-version history: three moderate incidents in the already chosen 300-second window produce quarantine. If in the same round CPU and RAM both prove a new moderate, record at most one incident per owner, while still updating the state of both. RAM recovery does not reset the history or a quarantine.
- The RAM stop is expected and does not generate a crash retry. The physical reserves stay held until the exit is actually observed. A possible host launch to resume measuring does not clear the block or the history; ordinary work does not bypass the pause.
- No RAM attribution to the service's consumers. Neither the provider+scene sum nor the UI's 128/192 MiB thresholds are approved.
- For this first internal profile, the reduction consists of refusing new work, with no new message to the provider and no promise to free its cache. The earlier phrase "cache release first" remains a possible future addition to be specified, not a simulated action or an undefined prerequisite of the stop.

Both alternatives remain verifiable only with controlled adapters until native identity, measurement and stop are qualified. The launcher stays blocked. Neither alternative is implemented before the choice.

## Answer

On 23 September 2026 the user chooses 1, the progressive profile described above: above 64 MiB, new admissions paused and one moderate per episode; recovery at 64 MiB or less; above 96 MiB, expected stop. Shared history and deduplication per owner/round as in the contract; no attribution to consumers. Parameters of the internal provider profile, no native enabling or qualification.
