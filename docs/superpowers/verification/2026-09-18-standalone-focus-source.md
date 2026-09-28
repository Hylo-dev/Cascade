# StandaloneFocus source example verification: 18 September 2026

**PASS within the scope of the source library.** Implemented an independent provider with start, pause, resume and end, a declarative countdown, host-assigned identity and a bounded persistent record. Recreating the provider does not reset revisions or receipts. [Example and integration contract](../../../Examples/StandaloneFocus/README.md).

## Final evidence

- Library build outside the checkout succeeded; **37 Swift Testing tests passed**, plus internal parameterized/matrix cases. The XCTest summary of zero tests is not the Swift Testing suite count.
- Direct dependencies exclusively CascadeAddonSDK/CascadeContracts; CascadePresentation is a transitive public dependency. Package configured with an explicit absolute SDK path, with no hidden fallback or invented remote repository. Nine new files verified against the external copy.
- Independent review Codex Sol high **PASS**, after three P2 findings and the completion of the fix for unusable history. Every behavioral error was reproduced in a compilable RED; earlier failures and handoffs are preserved.

A valid request remains outcomeUnknown when the authoritative history cannot be read or interpreted. An outcome already recovered from an exact receipt instead remains known even if writing the next snapshot fails; no candidate publication is returned. Unknown fields, even in a receipt's nested error, cause the state to be rejected and the bytes to be preserved. Valid history keeps the revision check after the oldest receipts are evicted: no promise of unbounded historical memory.

[Review with final addendum](../../../.scratch/codex-addon/20260918-continuation/focus-independent-review.md), [final handoff](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-handoff.md), [freeze and hashes](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-frozen-handoff.json), [37 tests](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-green.log), [library build](../../../.scratch/codex-addon/20260918-continuation/focus-history-fix-library-build.log). Earlier fixes: [first batch](../../../.scratch/codex-addon/20260918-continuation/focus-review-fix-handoff.md); [first historical handoff](../../../.scratch/codex-addon/20260918-continuation/focus-handoff.md).

## Scope and follow-up

The initial tests use the frozen SDK package of 62 inputs. The [storage client delivery](2026-09-18-addon-storage-message-client.md) then verified this example again against the 64 updated public inputs in a full copy of the package, with all tests passing. The same delivery includes a signed build of the app and a verified relaunch; the example remains a source library.

Authoritative storage and a single writer per assignment are required. Persistence and output admission are not a single transaction; a persisted token does not prove admission of the expiry. The refresh can reconcile the state, without guaranteeing a lost callback. No executable, signed container, real Focus service, migration of a builtin, addon launch or native parity is declared verified. Full C7/C12, macOS 14 at runtime and the C0d gate remain distinct and open.
