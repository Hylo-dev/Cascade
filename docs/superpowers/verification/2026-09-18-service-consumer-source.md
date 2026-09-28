# ServiceConsumer source example verification: 18 September 2026

**PASS within the scope of the source example, including the test improvements.** Created an independent package with three libraries: shared contract, provider of a synthetic value and consumer. The value 3 is demonstration data, neither a real history nor a service exposed by StandaloneFocus. [Example and instructions](../../../Examples/ServiceConsumer/README.md).

## Evidence

- Independent build succeeded; two real manifests validated. Actually reachable dependencies: CascadeAddonSDK, CascadeContracts and the transitive public CascadePresentation. The consumer does not depend on the provider's implementation.
- First suite: 14 tests passed and independent review PASS, with no P1/P2 findings. Two P3s on the tests were corrected without changing the production sources: causal rendezvous between invocation and early completion, cleanup of suspended tasks and checking of the specific error codes.
- Corrected suite: **16 Swift Testing tests passed**. No polling with yield or waiting based on arbitrary delays. The rendezvous regression was verified with a mutation of the external test only; an earlier compilation error is preserved and not presented as behavioral RED.

[Initial handoff](../../../.scratch/codex-addon/20260918-continuation/service-consumer-report.md), [independent review](../../../.scratch/codex-addon/20260918-continuation/service-independent-review.md), [final addendum PASS](../../../.scratch/codex-addon/20260918-continuation/service-independent-review-addendum.md), [test fixes](../../../.scratch/codex-addon/20260918-continuation/service-review-fix-report.md), [final hashes](../../../.scratch/codex-addon/20260918-continuation/service-review-fix-final-hashes.json), [16 tests](../../../.scratch/codex-addon/20260918-continuation/service-review-fix-final-tests.log), [library build](../../../.scratch/codex-addon/20260918-continuation/service-final-build.log).

The consumer checks assignment, supplied grants, scope, generation and civil deadlines; it validates the bounded payload before the finished publication. Stop and cancellation during a suspended response prevent its publication. The service completions belong to the provider/transport, while the consumer's refresh does not invent a completion for the outgoing call.

## Limits

The grants are snapshots supplied by the host: provider version, consent, REQUIRES resolution, canonical revocation and authenticated transport are not proven by the fixtures. The consumer's revisions are local to a new assignment, with no history restoration. No executable, signing, installation or control of native processes; C0d unchanged.

The initial tests use the frozen SDK package of 62 inputs. The [storage client delivery](2026-09-18-addon-storage-message-client.md) then verified this example again against the 64 updated public inputs in a full copy of the package, with all tests passing. The same delivery includes a signed build of the app and a verified relaunch; the example remains a source library. The full limits are in the README and in the linked reports.
