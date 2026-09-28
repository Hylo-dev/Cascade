# SDK/runtime asset wiring: Codex continuation

Status: **completed and delivered**. Wayfinder ticket resolved, independent review PASS, signed build and relaunch verified.

## Scope

Continuation of [Wire the asset messages to the runtime and the SDK client](../../../.scratch/cascade-product/issues/23-asset-message-integration.md), on the [approved specification](../plans/2026-09-15-addon-asset-message-integration.md). On 18 September the user asked for Codex agents only, with model/level chosen according to difficulty; the explicit waiver of the 35% reservation remains valid. No submission to DeepSeek, commit, staging or reset in the continuation.

The internal path uses schema 1 asset frames, cumulative negotiation 1.2, canonical connections/assignments, allocation protection and the serial SDK client. The tests forward messages to the real runtime through a local test bridge and use the real Foundation codec, assembler, ImageIO and AssetState.

## Implementation and scoped tests

- **Revocation of the transfer only:** end/expiry of a publication does not permanently close the process's assembler; its reuse waits for the earlier cleanup. The pending correction was compared with the preimages and approved by the [scoped review](../../../.scratch/codex-addon/20260918/nonterminal-review.md). The reuse tests after end/expiry pass in the new integration checks.
- **Connection close:** revokes session and import, preserves durable publications/pins and physical resources/uncertain work until the actual observations. It also handles a process already stopping and archive quiescence, authenticates the canonical handles and makes stale/foreign/repeated closes harmless. RED→GREEN documented, last check: 132 tests / 7 suites; [report](../../../.scratch/codex-addon/20260918/connection-report.md) and [review with P2 resolved](../../../.scratch/codex-addon/20260918/connection-review.md).
- **SDK and draining:** tests of late cancellation on release and of concurrent close with finish/share/release, with DEBUG observation of participation in the drain. A controlled mutation that removes the wait fails in all three cases; the correct source was restored exactly. Last check: 79 tests / 3 suites, of which 43 SDK/storage and 36 integration; [report](../../../.scratch/codex-addon/20260918/sdk-report.md) and [review, P2/P3 resolved](../../../.scratch/codex-addon/20260918/sdk-review.md).

The totals sum all Swift Testing summaries per target. Parameterized tests can have more cases than the single counted declaration. The scoped checks do not replace the final full suite.

## Correction raised by the final review

The first [overall review](../../../.scratch/codex-addon/20260918/review-round1/final-review.md) approves the runtime criteria but finds a P2: after the response was validated, the SDK completion could observe the close, drain it and still return success. The correction orders successful finalization and close under the same lock. If the close wins, the client keeps the slot during the drain and returns `sessionRevoked`; a close that follows an already successful finalization does not retroactively change the result. Late cancellation alone keeps the known success.

The new DEBUG checkpoint after validation reproduced the defect in the three finish/share/release cases: compilation succeeded, exit 1, three behavioral errors. After the fix, the targeted **65 tests / 2 suites** pass, including the six cases of close before/after validation, the three checks of success preceding the close and the existing cancellation tests. [Report, preimages and commands](../../../.scratch/codex-addon/20260918/finalization-report.md). The [independent reassessment](../../../.scratch/codex-addon/20260918/final-review-round2.md) is **PASS**, with no remaining findings, and inherits the earlier runtime acceptance.

## Real matrix and full suite

The [safety matrix](../../../.scratch/codex-addon/20260918/safety-evidence.md) runs 32 parameterized cases of protected admission/native ImageIO frame against stop, observed exit, disabling, end, expiry and exact close, including a process already stopping and quiescence. It also covers earlier/foreign identities, real contention with actions, single decode, last CGImage loan and failed refunds. The checkpoints observe real mechanisms; they do not simulate authorizations, accounting or decoded images.

The new regression test compiled and reproduced **two refund attempts for the same token in a single drain**, against the limit of one; it was not a double credit. The correction collects the exited assemblers in the single final phase of the drain and keeps the token's owner when the refund fails. [Report and commands](../../../.scratch/codex-addon/20260918/safety-report.md).

- Targeted check: **268 tests / 25 suites**, exit 0.
- Full suite with access to the graphical session: **883 tests / 83 suites**, exit 0, zero issues: runtime 578/48, presentation 66/7, CascadeKit 170/19, contracts 65/8, tool 4/1. [Audit of the five targets](../../../.scratch/codex-addon/20260918/root-test-audit.json), [log](../../../.scratch/codex-addon/20260918/finalization-full.log), [status](../../../.scratch/codex-addon/20260918/finalization-full.status).
- The first full run in the sandbox had two failures in the same parameterized UI test, because of `NSScreen.main == nil`. The second run passed 882 tests on the same sources with access to the graphical session; after the SDK fix the new full suite passes 883: no UI change, exclusion or weakening of the tests. The original log remains preserved.
- Four public documents updated and 22 local links verified. The limits of the injected channel and the atomic finalization relative to the SDK close are explicit.
- **285 final inputs frozen**, with hashes, copies and diffs against the dirty resumption baseline and the original one; no drift at the root check. [Manifest](../../../.scratch/codex-addon/20260918/final-manifest.json), [delta](../../../.scratch/codex-addon/20260918/final-delta.json). `git diff --check` succeeded.

## Review and delivery

Final independent review by Codex Astra high: **PASS** on the frozen inputs. [Verdict](../../../.scratch/codex-addon/20260918/final-review-round2.md).

Debug build run with `scripts/build-development.sh`, Xcode beta and DerivedData `CascadeAddonDevelopment`: **BUILD SUCCEEDED**, exit 0, `codesign --verify --deep --strict` verification succeeded. Apple Development signing as the project specifies; no ad hoc signing. The script updated `/Applications/Cascade.app` to the compiled build. [Log](../../../.scratch/codex-addon/20260918/build.log), [status](../../../.scratch/codex-addon/20260918/build.status).

The first build was stuck before compilation in `NSFileCoordinator` while reading the iCloud project. It was interrupted with SIGINT (exit 130), without terminating Cascade or system services. After the 126 dataless files were recovered, the successful build uses a local copy of **408 identical files** in `/private/tmp/cascade-addon-delivery-20260918`, with the same script, configuration and DerivedData. [Copy manifest](../../../.scratch/codex-addon/20260918/build-snapshot-manifest.json), [diagnosis](../../../.scratch/codex-addon/20260918/build-wait.sample.txt), [interrupted attempt](../../../.scratch/codex-addon/20260918/build-icloud-blocked.log). A first attempt from the local copy failed because `Config/Cascade-Info.plist` was omitted from the copy (exit 65); the original file was added unchanged before the successful build. [Preserved log](../../../.scratch/codex-addon/20260918/build-snapshot-incomplete.log). The identity of the 408 files between checkout and copy was verified again after the build.

Cascade was closed normally and reopened from the Applications link. Verified: a single new process, **PID 50978**, the exact executable path and stability for five seconds. [Relaunch evidence](../../../.scratch/codex-addon/20260918/restart-evidence.json). All 285 reviewed inputs remain identical after build and relaunch.

Only [Wire the asset messages to the runtime and the SDK client](../../../.scratch/cascade-product/issues/23-asset-message-integration.md) was resolved. The other decisions remain open according to their own dependencies.

## Provenance and limits

[Codex baseline and progress](../../../.scratch/codex-addon/20260918/ledger.md): 285 initial inputs copied with hashes; the 19 original preimages of the modified files were recovered from iCloud and verified. The diffs include the originally untracked sources; HEAD alone does not represent the delta. The pre-existing dirty state is preserved.

No OS adapter, production authenticated bootstrap, decoder/launcher process qualification, macOS 14 runtime verification, final MainActor/SwiftUI integration or distribution is declared complete. C0d remains closed and this tranche does not complete the whole addon platform.
