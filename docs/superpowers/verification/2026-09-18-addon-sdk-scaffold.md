# SDK source generator verification: 18 September 2026

**PASS within the scope of the source project.** `cascade-addon init` generates a compilable SwiftPM package with a public provider, manifest, tests and instructions. The identifier and the SDK path are explicit. The command does not automatically run build, tests or shell, and rejects every existing destination, including empty directories and symlinks. [Getting started guide](../../addons/quickstart.md).

Independent review Codex Sol high PASS; the only P3 finding, on the cleanup comment, corrected and re-reviewed. RENAME_EXCL publication without replacing the destination; non-recursive cleanup with a check of the observed identities. No guarantee of isolation from arbitrary concurrent modifications with the same filesystem authority as the user, nor of persistence after a crash.

## Evidence

- Targeted tool tests: 17 tests / 2 suites PASS. External project generated from the final template: build and 5 tests / 1 suite PASS; imports and dependencies only the public SDK/contracts and their public dependencies. The case of a keyword name and of an identity coinciding with the earlier unrelated fixture verified.
- Final full suite: **896 tests / 84 suites PASS**: Runtime 578/48, Presentation 66/7, Kit 170/19, Contracts 65/8, Tool 17/2. No test errors in the final verification.
- First full attempt stopped by the non-writable module cache; the second with two issues in the pre-existing UI test because NSScreen.main is absent in the sandbox. Set the explicit cache and ran the suite with access to the graphical session; no modification or exclusion of the UI test. Earlier errors preserved.
- Debug Apple Development build succeeded from an exact local snapshot of 412 files, deep/strict signature verified; /Applications/Cascade.app link updated by the intended script.
- Normal quit and relaunch verified: PID 50978 → 17941, single expected executable, stable for 5 seconds. No forced termination.

[Implementer report](../../../.scratch/codex-addon/20260918-continuation/scaffold-report.md), [independent review and fix](../../../.scratch/codex-addon/20260918-continuation/scaffold-independent-review.md), [suite audit](../../../.scratch/codex-addon/20260918-continuation/scaffold-test-audit.json), [exact build manifest](../../../.scratch/codex-addon/20260918-continuation/scaffold-final-build-manifest.json), [build](../../../.scratch/codex-addon/20260918-continuation/scaffold-signed-build.log), [relaunch](../../../.scratch/codex-addon/20260918-continuation/scaffold-restart-evidence.json). Logs/commands/status and intermediate failures are preserved in the same directory; final snapshot /private/tmp/cascade-addon-scaffold-final-20260918.

## Limits still open

The result is a source library, not an installable addon package. Addon signing, bootstrap, native transport, revision restoration and real bundled/external parity remain distinct. No addon process launched and no macOS 14 runtime qualification claimed; C0d keeps exit 78. This delivery does not complete C12 or the whole addon system. No commit/staging/reset performed.
