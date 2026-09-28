# Define the widget and Live Activity contracts

ID: 06
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 05

## Question

Which public contracts distinguish widget, instance, compact activity content, expansion, actions and data source? Define versioning and capability negotiation, supported sizes, availability, a UI lifecycle separate from ongoing activities, updates and commands, source app identity and behavior with an absent or incompatible extension. Establish what remains of the existing NotchWidget and what requires a distinct contract, without binding a transport not yet chosen.

## Progress of 9 September 2026

Approved: a common SDK, composable descriptions in Swift rendered with SwiftUI, publications independent of the connection, typed actions, REQUIRES per feature and remote scenes for advanced UI. NotchWidget and the activity protocols become the bridge's internal boundary; all future team widgets use the public addon API.

[P1](../../../docs/superpowers/plans/2026-09-09-addon-runtime-01-contracts.md) defines types, schema, resolver and renderer; [P3](../../../docs/superpowers/plans/2026-09-09-addon-runtime-03-adoption.md) migrates the team's modules. The ticket stays open to stabilize the APIs on the tests of the launcher and of real consumers; the proposed contracts are not declared already implemented.

## Realignment of 14 September 2026

The contracts are no longer only proposed: Contracts, base SDK, resolver, publications, actions and services have implementations and tests. The internal host also has authenticated admission and storage response; the new SDK component correlates a single pending request and handles cancellation, late responses and closing. References: [host handler](../../../docs/superpowers/verification/2026-09-13-addon-authenticated-storage-handler.md), [SDK lifecycle](../../../docs/superpowers/verification/2026-09-13-addon-sdk-storage-lifecycle.md).

Image sharing has been approved and implemented with independent aliases on the same raster and host-controlled partitions: [sharing verification](../../../docs/superpowers/verification/2026-09-13-addon-asset-sharing.md). The dedicated frames and the internal assembler are implemented and reviewed; what remains is the connection to the authenticated channel and to the concrete client: [chunked asset component](../../../docs/superpowers/verification/2026-09-14-addon-asset-chunks.md). The choice of the transfer mechanism is recorded separately in [Choose the image transfer between addon and host](21-asset-transfer.md).

The ticket stays open for stabilization on the real authenticated channel, the concrete SDK clients, the real consumers and the migration of the widgets. A verified contract or internal component does not by itself constitute a working external addon.
