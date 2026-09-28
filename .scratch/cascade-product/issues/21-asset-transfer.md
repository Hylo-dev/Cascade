# Choose the image transfer between addon and host

ID: 21
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: codex-wayfinder-sync
Blocked by: none

## Question

Transfer compressed images in chunks through messages, or introduce a separate native capability for large buffers? The choice must keep the approved limits for images, messages, memory and privacy, reusing the available libraries.

## Answer

Resolution of 14 September 2026, based on the user's explicit answer "chunks through messages are fine" to the proposal of 64 KiB chunks.

Transfer in 64 KiB chunks over the message path is adopted, reusing Foundation. The limits already approved remain: compressed images up to 1 MiB / 1,000,000 pixels and ordinary messages up to 512 KiB. The alternative of dedicated large native buffers is not selected. The [analysis of the alternatives](../../../docs/superpowers/plans/2026-09-13-addon-asset-transfer-decision.md) document keeps the rationale and the constraints to be developed in the execution plan.

The decision concerns the mechanism. The dedicated frames and the internal assembly primitive with protected quotas and expiry are now implemented and reviewed; wiring to the authenticated transport and the SDK client is still to be done. The final evidence is in the [component report](../../../docs/superpowers/verification/2026-09-14-addon-asset-chunks.md). It does not change the launcher qualification or the C0d gate. The host/SDK prerequisite is delivered in the [SDK storage lifecycle verification](../../../docs/superpowers/verification/2026-09-13-addon-sdk-storage-lifecycle.md).

The ticket is closed because the user's choice has been acquired, not because the transfer is already operational. No new choice was attributed to the user during the map realignment.
