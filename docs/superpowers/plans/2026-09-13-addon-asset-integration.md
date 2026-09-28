# C5 — canonical asset integration

Continue the approved C5 plan until a genuine architectural/design decision is
required; preserve the user's weekly usage ceiling of 60%.

## Existing decisions and bounded scope

Use the current ImageIO/CoreGraphics decoder, ResourceGovernor and actual-lifetime
raster coordinator. AssetState is synchronous state owned directly by AddonRuntime;
publication and asset commits happen together after the final asynchronous admission.

Self-produced asset imports bind to the current authenticated connection and exact
host-assigned publication, verified publisher/addon, digest and feature. No shared
cache or service-derived import is introduced. Broker private partitions already
exist in HostServicePermission; do not create a second account authority or use
ContentDocument.Privacy as permission. Per-publication scope is an initial restriction,
not a promise of future cross-publication reuse.

Each import creates an opaque provider alias and immutable raster revision. A
connection exit invalidates import aliases but preserves backings pinned by committed
publications. A new connection imports fresh aliases. End, expiry, disable and stop
remove logical authority; CoreGraphics' last reference controls physical disposal.
All admitted timeline entries and representations contribute declared references.

## Work

- [x] Add allocation-free visitors for declared references and canonical prepared records.
- [x] Implement bounded AssetState, metadata accounting, proposal validation and lifecycle,
  including explicit release of unused imports without ending published image ownership.
- [x] Integrate authenticated import and atomic publication/asset commit in AddonRuntime.
- [x] Include observed publication revision in presentation resolver requests.
- [x] Verify failure rollback, connection replay, exact scope, expiry, real image lifetime,
  quota pressure and cancellation/disable during suspended admission.
- [x] Independently review, run full serial suite, build signed Cascade, update Applications,
  restart and verify the new process.

## Boundaries

No SDK wire import, native transport/launcher, cross-publication cache sharing or
service-private asset transfer is claimed by this increment. Native launcher safety
qualification remains required before real addon execution. Continue other approved
work if these are technical dependencies; ask only for an unresolved design choice.

## Verified result

536 serial package tests passed (29 new), independent review clear, signed build
succeeded, all 350 build/test inputs matched the frozen copy. Applications link
updated; normal restart verified with new PID 69877. Weekly usage last read: 19%.
See [verification](../verification/2026-09-13-addon-asset-integration.md).

The public SDK reuse choice was presented as: publication-specific aliases or sharing
between publications of the same addon within compatible privacy scopes. No public
asset contract was fixed in that increment. The user subsequently approved sharing;
see [the implemented continuation](2026-09-13-addon-asset-sharing.md).
