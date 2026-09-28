# Order the releases and define the completion criteria

ID: 17
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 06, 08, 09, 10, 11, 12, 13, 14, 15, 16, 18

## Question

How should the agreed product be divided into verifiable releases, keeping modularity as the main goal? Establish the content of the first release, an end-to-end test with an extension developed outside the host, dependencies, feasibility gates, the hardware/OS matrix, signed/notarized distribution and the Homebrew path. The result prepares implementable specs for subsystems; it must not introduce dates or estimates without information about the team.

## Progress of 9 September 2026

The [execution plan of the addon subsystem](../../../docs/superpowers/plans/2026-09-09-addon-runtime.md), requested by the user, is available: P0 platform, P1 contracts/SDK, P2 runtime/resources, P3 adoption by the Cascade widgets, P4 distribution/qualification. It includes dependencies, files, interfaces, behavioral tests, measurements and exit criteria; all implementation tasks are still to be carried out.

The global ticket remains open: this sequence does not decide the release of all the other features, dates, public notarization or Homebrew. Using the shared system for every future team widget is, instead, an approved roadmap constraint.

## Realignment of 14 September 2026

The addon subsystem is now tracked by the [current completion plan](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md), which supplements the historical P0–P4 plan. The latest [verified delivery](../../../docs/superpowers/verification/2026-09-14-addon-asset-chunks.md) records 795 serial tests in 80 suites, 400 identical inputs, an approved review, a signed build and the launch of the updated version. These numbers describe the verification of the integrated code, not a percentage of the product completed.

Still remaining: the native transport and the qualification of the launcher, wiring the asset transfer to the authenticated channel, the concrete clients and the wiring to the app lifecycle, Clock/FocusTimer on the shared path, the migration of the other widgets and the packaging/distribution and compatibility tests. The choice of chunks is in the [dedicated ticket](21-asset-transfer.md); frames and the internal assembler are implemented, while the runtime/SDK path is still to be wired. The global release decisions and their dependencies remain open.
