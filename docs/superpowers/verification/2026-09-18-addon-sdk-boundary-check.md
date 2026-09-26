# SDK source boundary checker — delivered source verification

Status: **PASS, source tooling delivered**. The four corrected scripts are imported exactly, their independent review passes, and the final live audit passes. This does not complete C6/C12 or native SDK parity. The [binding plan](../plans/2026-09-18-addon-sdk-boundary-check.md) scopes the checker to the three public SDK targets and two independent source examples.

## Final evidence

The exact four hashes and file modes are in `.scratch/codex-addon/20260918-continuation/sdk-boundary-check-corrected-freeze.json`; corrected source copies are in `sdk-boundary-check-corrected-delivery/`. The [independent corrected review](../../../.scratch/codex-addon/20260918-continuation/sdk-boundary-check-corrected-independent-review.md) returns PASS. Root rechecked all four live file hashes and modes at ticket resolution.

Twenty Python unit/integration tests pass with no skips, the actual compiled SwiftParser/SwiftSyntax scanner and real SwiftPM manifest evaluations:36.417s, wrapper40.51s. The immutable baseline audit passes in9.55s:3 packages/9 targets/85 Swift files/126 imports. Evidence is retained under `sdk-boundary-check-evidence/`, including `review-final-tests-status.json` and `review-final-baseline-status.json`.

After importing the complete corrected service client, `sdk-boundary-check-corrected-live-status.json` and its stdout/stderr record the final current-source audit: **3 packages/9 targets/88 Swift files/132 imports PASS**, exit0 in10.19s. All483 frozen source/config/script hashes remain unchanged. The JSON audit records selected toolchain, three manifest and three description command arrays, and input hashes. Execution is limited to Apple Swift6.4/macOS27 arm64; other compiler/OS combinations are not certified.

## Review corrections and historical evidence

The initial15-test candidate passed its baseline but independent review found four gaps: app-module Cascade imports, importing-target ownership for @testable, actual SwiftPM-selected sources and version-specific manifest provenance. Corrections explicitly reject the app host module, allow @testable only for an example's own test targets, obtain exact source lists from selected SwiftPM describe output, and reject unsupported Package@swift variants before evaluation and if added during audit. All four findings are closed by the corrected review. Original snapshots/logs remain historical.

Behavioral RED evidence is retained separately from setup failures. The original wrapper initially lacked an explicit selected SDK argument; `review-f2-green.log` contains a unit-fixture error and is not passing evidence. Final20-test results supersede these attempts. The reviewer independently rechecked88 baseline input digests and ran bounded policy probes; it did not rerun the compiler/SwiftPM suite. Graph target kinds and described Swift module category/path are checked; no separate describe target-kind comparison is claimed.

## Integration and limits

[Testing guidance](../../addons/testing.md) documents the real command, optional full test fixture, trusted-manifest assumption and unsupported version-specific profile. This tool evaluates trusted development manifests; it is not a sandbox for arbitrary Package.swift. It audits static imports and the selected target graph, not alternate manifest environments, macro expansion, dynamic loading, allocator behavior, native process admission or bundled/external parity.

The checker introduces no app/API/package dependency and never executes providers, native probes, app build or lifecycle commands. Its source-only ticket is complete independently of the ongoing subscription app delivery; no new app restart is attributed to this tool. It is currently invoked explicitly. [Mandatory use before development build](../../../.scratch/cascade-product/issues/37-required-sdk-build-check.md) is the next separately tracked increment; broader legacy registration migration remains open.
