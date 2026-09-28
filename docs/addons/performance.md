# Addon performance and resources

## Designing finite work

Publish bounded declarative content and finite timelines; use the countdown and clock of the [renderer](content.md) instead of keeping a provider task that sends updates on every tick. The model separates the lifetime of the content from the lifetime of the process. Retention of values, deadlines and revisions are described in the [lifecycle](lifecycle.md); the complete evidence with an absent native provider remains distinct from the behavior of the components.

Handle `resourceDenied`, `rateLimited`, deadlines and revocations explicitly. An uncertain result does not authorize an automatic repetition of effects. Bound inputs, results and retained state, releasing resources according to their contract; do not treat a stop request or a transport receipt as an observed exit.

## Enforced limits and accounting

The baseline implements payload validation and admission through `ResourcePolicy`/`ResourceGovernor`. For ordinary requests the governor checks the per-owner and global costs before recording a reservation. Disk reconciliation also records data that is already present beyond the quota; that debt prevents new growth without hiding the existing bytes. The quotas cover different quantities: publications, jobs, providers, scenes, retained state, assets, admitted memory and disk. The costs include reservation metadata; a resource declaration in the manifest is not a grant, and the package's origin does not select a privileged policy.

For the limits on documents, trees, timelines and frames, use the [protocol](protocol.md); for pixels and transfers, the [assets](assets.md); for persistent state, [storage](storage.md); for queues, jobs and action history, the [lifecycle](lifecycle.md) and the [actions](actions.md). The [services](services.md) page details reservations before dispatch, shared capacities and outcome lifetimes. These budgets must not be added up as if they formed a single process memory limit.

Wire size, reserved cost and observed footprint are different measures. An accepted frame does not prove a limit on Foundation allocations or on RSS; a provider cost in the governor does not constitute a memory sandbox. Process reservations remain until the observed exit in the host model: the exit inputs modeled in the tests do not qualify native termination.

## Measurements actually available

The internal reader observes process resources; the reducer computes CPU intervals from compatible samples. Missing data, or data referring to a different identity, does not become zero usage. The [observations contract](../architecture/addon-resource-observations.md) describes continuity, overflow and the limits of identity.

The [independent calibration](../superpowers/verification/2026-09-18-addon-process-cpu-calibration.md) compares identical copies of the reader and reducer with `getrusage(RUSAGE_SELF)` on macOS 27 arm64. It qualifies the scale and unit conversion for the diagnostic process, without qualifying the absolute precision of kernel accounting or of the clock. The footprint that is read is not a qualified RSS measurement of the installed addon.

Still to be connected: authenticated addon/process association, shared sampling and disarm, thresholds, health, and actual stop. No guarantees are delivered for latency, p99, wakeups, sustained usage or performance on macOS 14/Intel. A source test or a successful reservation does not close the qualification of native resource control.
