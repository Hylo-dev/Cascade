# Dedicated invocation messages verification: 18 September 2026

**PASS for the contracts and codecs, without activation in the runtime.** Four new Contracts files and one suite define the consumer request, the correlatable response and the invocation to the provider. The `.v1_3` profile describes the syntax; negotiation stays unchanged, with default1.0 and implemented maximum1.2.

## Evidence

- Development in an isolated Contracts harness: 77 tests / 9 suites passed, 12 new groups and 65 existing tests. Compilable behavioral REDs preserved; all 62 base inputs unchanged. The harness uses the installed Swift6.4 and tools minimum6.2; it does not prove a compiler6.2.
- Import into the checkout of only the five files, identical to the freeze; no temporary Package imported. Codex Sol high independent review **PASS**, with no mandatory P1/P2 fixes.
- **Full checkout suite: 990 tests in 90 suites PASS**: Runtime634/51, Presentation92/9, Kit170/19, Contracts77/9 and Tool17/2. The full verification is distinct from the initial harness.
- Apple Development build succeeded on **427 inputs**, compared with the checkout and with the 422 of the previous delivery, all unchanged. Signature verified, Applications link updated and normal relaunch **PID65073 → 68582**, expected executable and stable for five seconds.

Evidence: [preserved harness and handoff](../../../.scratch/codex-addon/20260918-continuation/service-frames-isolated/service-frames-artifacts/service-frames-handoff.md), [freeze](../../../.scratch/codex-addon/20260918-continuation/service-frames-isolated/service-frames-artifacts/service-frames-FROZEN.json), [exact import](../../../.scratch/codex-addon/20260918-continuation/service-frames-root-import.json), [independent review](../../../.scratch/codex-addon/20260918-continuation/service-frames-independent-review.md), [full suite](../../../.scratch/codex-addon/20260918-continuation/service-frames-full.log), [snapshot](../../../.scratch/codex-addon/20260918-continuation/service-frames-build-snapshot-manifest.json), [build](../../../.scratch/codex-addon/20260918-continuation/service-frames-signed-build.log), [relaunch](../../../.scratch/codex-addon/20260918-continuation/service-frames-restart-evidence.json). The absent paths declared by the freeze describe the moment before the import, not the current state.

## Contract and limits

The raw cap is192KiB, applied before the Foundation decoder; decoded payloads stay64KiB and rejection reasons4096byte of non-empty UTF-8, without truncation. Schema, discriminators and fields are closed. The uncertain outcome has a dedicated variant; refused(outcomeUnknown) is invalid. A rejection means no new dispatch caused by this exchange, not that an earlier logical request was not executed.

Maximum payloads with every base64 slash escaped pass through the three dedicated codecs; the largest P1 metadata are conservatively limited to711byte, for175479byte in total, below196608. The generic AddonEvent128KiB limit stays unchanged. Representations with Unicode/whitespace expansion beyond the cap are rejected. It is not evidence of Foundation workspace, RSS or double base64 encoding in an outer envelope.

**Decoding is not equivalent to a correlated response.** Before projecting a completed response into the SDK lifecycle, the consumer must call `reply.validate(matching: request)`: it verifies the outer ID, contract and operation and those of the nested response. Constructor/codec verify structure and limits, but admit an outer/nested mismatch that matching always rejects. Moving that rejection earlier is an optional P3 hardening, recorded without changing its boundary here. There is not yet a Runtime/SDK consumer of this new reply that skips the check.

Still to implement: handler/adapter with real receipts and resources, the complete input/completion/response path, generation composition, SDK executor and subscriptions. No complete public client, native transport, authenticated peer or complete C3 is declared. C0d keeps the unconditional exit78.
