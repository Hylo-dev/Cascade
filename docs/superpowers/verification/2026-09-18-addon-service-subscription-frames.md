# Service control and update contracts

18 September 2026. **Implementation integrated, review PASS and signed delivery verified: 1048 tests / 94 suites.** This verification does not activate protocol 1.4.

The [plan](../plans/2026-09-18-addon-service-subscription-frames.md) defines six new files: control requests and responses, source start and output, a dedicated codec and tests. The existing invocation codec remains unchanged. The closed forms distinguish acceptance of the acquisition intent from the terminal result; the updates correlate the source and the start nonce. The serialized values do not constitute provider authority, proof of availability or consumer authorization.

## Isolated evidence

- 14 targeted tests and 91 Contracts tests in 10 suites PASS on the isolated harness with Xcode-beta / Swift 6.4; these are not results for the whole of CascadeKit.
- 67 pre-existing sources/tests/fixtures preserved byte for byte. Six additions frozen, no change to the previous contracts or to the real package.
- Frames bounded to 196608 bytes before decode and payloads to 65536 bytes. All-FF payloads with fully escaped slashes pass through the source/event codecs. The conservative wrappers are 476 bytes per update, 1424 per event and 7189 per source start, all under 8192.
- Phase/kind/result matrix, correlation, extra/null/unknown fields, rejection reason limits, maximum metadata and separation from the previous codecs verified. A rejection cannot use the outcomeUnknown code.

The first compiling behavioral RED contains one test and one error, before the implementation. The later run of the expanded tests on permissive scaffolding detects 224 violations: it is a later mutation test, not the original RED of every assertion. The early phases did not capture all the input hashes; the Swift/Package inputs of the final GREEN runs are frozen, with the fixtures protected by the baseline manifest. The preliminary toolchain errors are preserved separately.

[Handoff and logs](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-evidence/handoff.md) · [Independent review PASS](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-independent-review.md) · [Hashes of the six files](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-evidence/new-file-hashes.json).

## Limits and delivery

Still to be verified in the runtime: phase ordering, current authority, source lifetime, effective quotas, receipts, cancellation and event delivery. No evidence of RSS memory, native transport, process death or macOS 14 / Intel compatibility is inferred from these tests. The full public client and the 1.4 negotiation remain to be implemented.

Root imported only the six reviewed files, without the harness helpers. The 463 previous inputs remained identical; the freeze now includes 469 inputs. The full suite passes with **1048 tests in 94 suites**, exit 0, 63.54 s. The exact copy for the build contains 439 inputs; Debug Apple Development build, signature verification and `/Applications/Cascade.app` link PASS, exit 0, 11.7 s. Normal relaunch PID **18542 → 20946**, correct executable and stable for 5 s. The runtime negotiation remains at most 1.3.

[Root import and checks](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-root-import.json) · [Verified relaunch](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-restart-evidence.json). SHA256 of the executable: `0712922cbb2d0337875e768474d172c7d34648700797c8d41d349b0b9b2ad13a`.
