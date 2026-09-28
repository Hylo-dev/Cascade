# Define the CPU attribution of services to consumers

ID: 55
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 54

## Question

How should the CPU consumption measured in a shared provider's process be attributed to consumers, without pretending to have a precise measurement of each individual piece of work?

## Context

The spec requires counting the process once in the global total and also attributing the delegated work to the consumers, to prevent them from getting around their own quota. The decisions on credit and violations expressly left this attribution separate. The current reader measures the user+system CPU of the whole process: an interval can include invocations from different consumers, shared sources and internal work. It does not directly measure the share caused by each one.

After the refusal of new work and the wiring of the deadlines, the next increment must choose a charging rule, with visible consequences on the availability and quarantine of consumers. The rule does not change the provider's credit and does not multiply the physically measured global consumption.

## Alternatives to evaluate with the user

1. **Conservative attribution (initial recommendation).** The entire consumption of the interval concerned is also charged to each consumer with active work/interest for that provider. It avoids granting extra credit through sharing, but can penalize a consumer for work requested by another.
2. **Split among active consumers.** The cost of the interval is divided among the consumers concerned according to an explicit uniform rule. It reduces the penalty of sharing, but can underestimate the consumer that caused almost all of the work. It is an accounting policy, not a per-request measurement.

Example: 40 ms of provider CPU with two active consumers means 40 ms for each with the first rule, 20 ms each with the second; the global total stays 40 ms in both cases. The behavior of intervals without consumers and of incomplete samples must stay explicit. Do not implement either alternative before the choice; first complete the tranche already authorized.


The recommendation favors the requirement of not getting around quotas through sharing; the cost is the possible penalization of another consumer. The uniform split can instead dilute the cost by adding barely active interests. In both cases, the interests and the work must come from the host's canonical ledger and refer to the observed interval; the absence of attributable consumers does not create an invented charge, and unknown/incomplete measurements do not become zero consumption.

References: [resource spec](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md), [exclusion from the burst choice](46-addon-cpu-burst-policy.md), [exclusion from the counting choice](49-addon-cpu-violation-counting.md). The independent review of 21 September confirms that none of those choices has already resolved the split.


## Answer

On 22 September 2026 the user chose **1, conservative attribution**: the provider's entire measured CPU consumption is also attributed to every consumer with active canonical work/interest in the interval. The global physical cost stays counted once; the provider's account stays unchanged. The possible penalization of a consumer for someone else's work in the same shared interval is accepted. Several interests of the same consumer do not multiply the same interval; incomplete measurements stay unknown, not zero. The tracking must keep work that finished between two samples, without inferring it only from the interests still present at the time of the reading. Bounded internal implementation, launcher always blocked.
