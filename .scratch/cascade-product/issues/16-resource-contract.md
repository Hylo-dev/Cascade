# Define budgets, isolation and failure recovery

ID: 16
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 05, 06, 13

## Question

Which measurable thresholds for memory, CPU, energy, wakeups, opening latency and smoothness must Cascade respect, idle and with real activities? Decide diagnostics, policies for slow extensions, crashes and permission revocation, and verification of the audio path. Separate protocol promises from limits the system can really enforce: code in the same process does not become isolated because it exposes suspend(). Include Reduce Motion, Reduce Transparency and keyboard/VoiceOver in the relevant validation criteria.

## Progress of 9 September 2026

Approved: preventive admission of managed operations, shared services with revocable grants, on-demand processes and supervision with recovery/quarantine. Rigid application quotas and observed CPU/RAM thresholds are kept distinct; freezing is excluded from the default. Identical controls and budgets for team and external addons.

The [spec](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md) proposes initial values; [P2](../../../docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md) applies them and [P4](../../../docs/superpowers/plans/2026-09-09-addon-runtime-04-release.md) measures them. Still open: qualified values, continuous UI/audio profiles, the total cost of services and tests on hardware/OS; no benchmark is already concluded by this decision.

## Realignment of 14 September 2026

The reservations of the shared governor, the protected accounting of rasters/decoders and the resources of storage operations are implemented and reviewed. The user chose SwiftData for the durable archive; saving, restoring, the complete inventory, writing on significant changes and the checkpoint limited to shutdown have dedicated verifications in the [current plan](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md).

The [approved disk policy](../../../docs/superpowers/plans/2026-09-13-addon-swiftdata-disk-policy-decision.md) keeps in the count any overruns produced by the framework's internal files and blocks subsequent writes. Allocations controlled by the app remain subject to preventive admission. SwiftData, Foundation and ImageIO/CoreGraphics are reused; no alternative database or codec was added.

Still open: native CPU/footprint measurements, the actual exit of processes, continuous audio/UI profiles, the overall cost of services and the hardware/OS matrix. The functional tests are not energy benchmarks nor proof of a rigid limit on the frameworks' internal consumption. The ticket's global dependencies remain valid.
