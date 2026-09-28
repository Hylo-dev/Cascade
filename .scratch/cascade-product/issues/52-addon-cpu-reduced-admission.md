# Define the reduction of new work after a CPU overrun

ID: 52
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 51

## Question

After a moderate violation and before quarantine, which concrete reduction must the host apply to new event-driven work?

## Context

The spec requires "reduction of grants and a request to release", while `AddonHealthStore` keeps the incidents and returns `keep` for the first two, `quarantine` at the third within five minutes. The `keep` value is not already an implementation of the required reduction. The current policy admits at most one job per addon: reducing only the parallelism to one would change nothing.

The credit and the counting of overruns are defined. What is missing is the condition for reopening admissions after a violation and the visible behavior of requests in the meantime. This is a choice about how the product works: a user action may have to wait or receive a resource-temporarily-unavailable response.

## Concrete alternatives

1. **Refuse new work until the debt is repaid (recommendation).** After a violation, new jobs and actions that require work from the provider immediately receive a temporarily-unavailable outcome; no additional queue or automatic replay. Work already admitted keeps its planned deadlines. The credit must return positive before reopening; there is no need to rebuild all 100 ms. With 50 ms of debt and no other consumption, recovery takes about ten seconds. The third violation keeps the already approved quarantine.
2. **Wait for the full credit to be restored.** Same temporary refusal, but reopening only when all 100 ms are available. With 50 ms of debt and no other consumption, recovery takes thirty seconds. It gives more margin to the first subsequent piece of work, with longer waits.

An unknown sample or an accounting error does not authorize reopening; the profile still requires reliable measurements and a qualified stop. This choice does not change quotas, incident counting, per-version quarantine, the deadlines of work already admitted or the launcher block. Already published declarative state and physical reserves keep their own lifecycles.

Complete and verify the already authorized observational composition before presenting the choice. Neither of these policies is implemented before the user's answer.

## Answer

On 21 September 2026 the user chooses **1**: immediately refuse new event-driven work and new actions that require work from the provider after an overrun, until a complete and reliable measurement demonstrates strictly positive credit. No additional queue or automatic replay; there is no need to rebuild all 100 ms. Missing samples/errors do not reopen. Work already admitted keeps its deadlines and its own completion paths. Per-version quarantine and the blocked launcher remain unchanged. The implementation is assigned to the ticket [Apply the temporary refusal of new addon work](53-addon-cpu-admission.md).
