# Define when CPU overruns become distinct violations

ID: 49
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 48

## Question

The shared credit is defined and the observations can now retain the debt. To apply "three moderate violations in five minutes", when does a new sample represent a new CPU violation?

## Context

The spec requires reducing grants after a moderate overrun and quarantining the version after three violations in five minutes. `AddonHealthStore` receives already classified violations: it does not decide whether a persistent debt represents one or more incidents. The choice changes the timing and the conditions of the quarantine, not only the representation of the data.

Example: an addon consumes 150 ms, exceeds the initial credit by 50 ms and then stays idle. The debt will stay visible for ten seconds. Counting every negative balance would produce three violations even without any other work: the recommendation excludes this double counting.

## Alternatives

1. **New consumption beyond the credit (recommendation).** At most one violation per addon per shared measurement round, if in that round more CPU is actually consumed beyond the available credit. Residual debt alone does not count. If the addon keeps consuming beyond the budget in three rounds within five minutes, it reaches quarantine; several processes of the same addon in the same round do not multiply the incidents. A round includes both periodic samples and explicit observations at job boundaries or under pressure: the frequency of rounds can therefore affect the detection time.
2. **One incident per debt episode.** The first move into negative counts; until the balance returns to at least zero a second incident is not counted. Three distinct episodes lead to quarantine. Continuous consumption that does not recover credit remains a single incident: before applying this model, a separate threshold/duration for stopping on a continuous overrun is also needed.

Incomplete samples must not be classified as zero consumption or as a healthy state; enabling the profile still requires qualified measurements and stop. This ticket does not open the launcher, does not attribute the costs of shared services and does not enable continuous UI/audio.

The user asked to continue up to a necessary design choice. Complete the review, tests and delivery of the authorized observational wiring, then present this choice. No counting policy is implemented before the answer.

## Answer: user decision, 21 September 2026

The user approves the recommended approach: new CPU consumption beyond the available credit, at most one moderate violation per addon and shared round. Residual debt alone does not count. Several processes of the same addon do not multiply the violations in the same round. The three incidents in five minutes for quarantining the version and the boundaries of the event-driven profile remain valid. Incomplete samples do not become zero or a healthy state.

The consent includes the behavior of periodic rounds and explicit observations already described above. It does not change the native gates or the continuous profiles.
