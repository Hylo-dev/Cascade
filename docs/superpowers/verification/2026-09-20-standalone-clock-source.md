# StandaloneClock: source increment

20 September 2026. [Ticket and scope](../../../.scratch/cascade-product/issues/44-standalone-clock-source.md).

## Delivery

[StandaloneClock](../../../Examples/StandaloneClock/README.md) is an independent SwiftPM library, with a validated manifest and a provider that uses only CascadeAddonSDK/CascadeContracts. It publishes hours and minutes in declarative form, with host-assigned identity and a monotonic revision. It creates no tick or resident work: drawing the clock belongs to the host. The expiry of each publication is 24 hours; the provider does not schedule a renewal.

Sol medium implementation, root review and integration with Ponytail. The SDK check explicitly includes the new package; the official build automatically inherits this check before compilation.

## Evidence

The full evidence and the scoped diff are in [20260920-clock-source](../../../.scratch/codex-addon/20260920-clock-source/).

- Build of the independent copy and **3 Swift tests**: PASS, repeated by root. Manifest, publications and recreation with a previous revision, unknown actions, wrong assignments, finished events and stop, non-finite time and revision exhaustion. All capability clients fail if invoked.
- SDK comparison: **78 public sources identical** to the current audit's inputs; no private target in the SDK fixture.
- Guarded build: **5 fixtures PASS**, including a private import added to Clock that stops the script before the build/signing/Applications update. The positive fixture intentionally reaches a missing Xcode project, without compiling the app.
- Audit on the checkout: **4 packages / 11 targets / 90 Swift sources / 140 imports, PASS**. Inputs rechecked after the delivery: unchanged.
- Full checker suite: **21 tests PASS, none skipped**, in 317 seconds. The relaunch record remains distinct from the source evidence.

The first invocation of the build fixtures lacked the required DEVELOPER_DIR and failed in setup; the log is preserved separately. The worker's initial empty-target is not a behavioral regression. The new Clock manifest check is instead verified RED→GREEN: before, it reached the toolchain evaluation without checking Clock; now it immediately rejects a missing Clock manifest.

## Limits

The declared minimum macOS remains 14; the tests are local with Xcode-beta on macOS27 arm64. No qualification of other OSes, native addon process, container signing, physical exit, OS transport or bundled/external parity. The production ClockWidget and the app's composition remain the previous ones. The launcher and C0d remain blocked. C6 is not concluded.

Since there are no changes to the app's code, this delivery produces no new Cascade binary. The relaunch uses the signed development build already linked in /Applications. The temporary caches of the Clock build/test are deleted after the verification, preserving the source copy, hashes, commands and results.

Relaunch completed: deep/strict signature verified, normal quit of PID90193, new PID34140 from the expected Applications path, stable for5 seconds. [Record](../../../.scratch/codex-addon/20260920-clock-source/restart-evidence.json). Last observed budget3% weekly, under20%. No agent left running.
