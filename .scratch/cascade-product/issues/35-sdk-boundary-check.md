# Verify the public boundaries of the SDK and the examples

ID: 35
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24, 26, 27

## Question

Implement the boundary check foreseen by the addon plan: verify the graph of the public SDK targets and the Swift imports of the examples, rejecting dependencies on the host's private modules without altering the runtime.

## Context

Check foreseen in C6/C12 of the [completion plan](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md). The existing public targets are CascadeAddonSDK, CascadeContracts and CascadePresentation; Runtime, CascadeKit and the host tool stay outside this surface. The examples keep the explicit local public dependency already approved.

## Progress

Taken on by the main task, in an isolated temporary directory and with dedicated caches. No change to the sources or caches owned by the subscriptions worker. The check will use the manifests evaluated by SwiftPM and the Swift syntax tree; it does not replace compilation, sandboxing or native parity tests.

### Isolated verification and review

Corrected implementation frozen: 20 Python/parser/SwiftPM/CLI tests PASS; immutable baseline 3 packages/9 targets/85 sources/126 imports PASS. The final independent review is PASS after four fixes, documented in the [verification](../../../docs/superpowers/verification/2026-09-18-addon-sdk-boundary-check.md). The four scripts were imported exactly and the check of the checkout with the complete client passes: 3 packages/9 targets/88 sources/132 imports. The verifications of the source perimeter are completed; the app delivery of the subscriptions remains separate. The check can be run explicitly; the mandatory integration into the build script is still a separate increment. No native qualification inferred.

## Answer

Source check delivered: four scripts imported exactly, 20 tests with the real parser/SwiftPM and independent review PASS. The latest audit of the corrected checkout passes on 3 packages/9 targets/88 sources/132 imports, with no changes to the 483 frozen inputs. [Evidence and limits](../../../docs/superpowers/verification/2026-09-18-addon-sdk-boundary-check.md). The perimeter of this ticket does not change app code and does not require a new launcher: the app delivery of the subscriptions continues separately. The [mandatory wiring into the build](37-required-sdk-build-check.md) remains a separate increment; C6/C12 and native parity are not completed.
