# Prepare the Clock provider with the public SDK only

ID: 44
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24

## Question

Prepare the Clock source foreseen by C6 as an independent example library, before the native container: declarative clock hourMinute publication, identity assigned by the host, no tick or loop in the provider. Reuse the SDK, the contracts and the conventions of the existing examples; do not connect the provider to the graphics process or replace the current widget.

## Scope

StandaloneClock source package with an explicit SDK dependency, a validatable manifest, a finite provider and behavioral checks. Independent build and the boundary check updated to include it. No invented signing/identity, no addon process launched, no bundled/native qualification or Clock migration declared. Sol medium implements the example; the root takes care of integrating the checks, the review and the delivery.

## Answer: 20 September 2026

Source delivery completed and reviewed by the root after the Sol medium implementation: [provider, manifest and guide](../../../Examples/StandaloneClock/README.md). Independent build and 3 Swift tests PASS, 21 checker tests with no skips and 5 build-script fixtures PASS. The mandatory check includes Clock: current audit 4 packages/11 targets/90 sources/140 imports. The SDK copy contains 78 public sources identical to the verified inputs.

[Verification and limits](../../../docs/superpowers/verification/2026-09-20-standalone-clock-source.md), [root review](../../codex-addon/20260920-clock-source/root-review.md), [outcomes](../../codex-addon/20260920-clock-source/results.json). No integration into the app, ClockWidget migration or native qualification; C6 and the launcher remain blocked. No new app binary needed: normal restart of the existing signed build verified, PID 90193→34140 and 5 s stability. Weekly budget observed at 3%, cap 20%; no agent left over.

Superseded on 2 October 2026: the `Examples/` packages were deleted with the addon SDK, and the clock is now the first-party `ClockPlugin`. Kept as a dated record.
