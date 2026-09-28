# Decide CPU attribution in service chains

ID: 57
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 56

## Question

If A uses B and B uses C in the same interval, is the measured consumption of C also attributed to A, or only to the direct consumer B?

## Context

[Define the CPU attribution of services to consumers](55-addon-delegated-cpu-attribution.md) resolved the formula: the complete interval to each active canonical consumer, without splitting the cost and without multiplying the physical total. It did not resolve propagation across several services. The arithmetic coordinator can receive a deduplicated set; the next wiring to the broker must instead produce that set according to an explicit rule.

The spec requires not offloading costs outside one's own quota, but does not define the transitive closure. The resolver's static path orders the processes to start and does not prove the work actually delegated. A shared provider can use another service for its own work or for a different consumer: not even a chain of active interests demonstrates the causality of the single request.

## Alternatives

1. **Conservative propagation along active interests (recommended).** In the example, 40 ms of CPU of C are charged to C, B and A. It prevents A from getting around its quota by inserting an intermediary; it accepts attributing to A also B's internal work or work requested by B's other consumers. Only canonical relations active in the interval are followed, not dependencies that are installed but unused. Each identity pays at most once per process/interval, even if several paths lead to the same dependency.
2. **Direct consumers only.** The 40 ms of C are charged to C and B. A pays for B's CPU, but not for what B delegates further; less indirect penalization, with the explicit limit that A's quota can be circumvented by using intermediaries.

In both cases the physical total stays 40 ms. Neither alternative is implemented before the answer. The review of the sources carried out by Terra and the root confirms that this choice has not already been resolved; the synchronization between ledgers and samples remains a separate technical problem.


## Answer

On 22 September 2026 the user chose 1: **conservative propagation along the active canonical chains**. In A→B→C, the consumption of C falls on C, B and A, once per identity/process/interval even when there are several paths. The cost of sharing and of the intermediate provider's internal work is accepted. Static dependencies without active interests are not used. The relations of the chain must be simultaneously active for at least part of the interval: the union of edges that existed at disjoint moments does not invent a chain. The physical global is always counted once.
