# Dedicated service invocation frames — next contract increment

Status: implemented, reviewed and delivered; not negotiated. Root selects P1 of the [technical transport design](../../../.scratch/codex-addon/20260918-continuation/service-transport-contract-design.md) under the user’s sustained Codex-only continuation. No native or product exception is required to implement pure syntax. The contract increment is independent of the lifecycle. Root authorizes implementation/testing in a small isolated Contracts-only harness while the lifecycle is reviewed. Integrate the five files into the live package only after the lifecycle delivery; the harness is not a full-package PASS. Shared root cache is not available to this worker.

## Scope

Exactly five new files: Contracts/ServiceInvocationRequest.swift, ServiceInvocationReply.swift, ServiceProviderFrame.swift, ServiceFrameCodec.swift, and ContractsTests/ServiceFrameCodecTests.swift under CascadeKit. No changes to existing Contracts, Runtime, SDK, Package, examples, protocol negotiator or launcher. Root owns guides/tracker/review/delivery. Preserve the dirty checkout; no Git mutation/worktrees/commits. Existing negotiated maximum stays1.2, default1.0; standalone syntax does not advertise service support.

Implement the exact P1 schema1 DTOs and .v1_3 syntax profile described in the design. Consumer request contains grantID plus existing ServiceInvocation, no owner/partition/provider/session authority. Reply carries requestID,contractID,operation and exactly one completed/refused/outcomeUnknown result. Provider frame wraps existing ServiceInvocation with providerInvoke kind. Closed shapes and checked init/decode/encode; nested existing values validate unchanged. Reply matching validates all identity fields, and completed response uses existing InvocationCompletion correlation. Generic AddonEvent cap stays128KiB.

Root clarification: refuse `AddonFailure.Code.outcomeUnknown` inside the refused result. The dedicated outcomeUnknown result represents uncertainty; do not allow contradictory result/code pairs. Refused means no new dispatch caused by this exchange, not proof that a retained logical request never ran and not SDK rejectedBeforeHandoff. Every remaining failure code retains its existing meaning. Failure reasons must be nonempty and <=4096 UTF-8 bytes without silent truncation.

## Bounds

Raw cap196608bytes, decoded payload65536, reason4096. Validate nonnil syntax profile and raw cap before Foundation decoding, revalidate DTO then check actual encoded bytes. Use sorted-key JSON; no new wire version or schema activation. Full all0xff64KiB base64 is87384chars; maximum slash escaping174768bytes. Enumerate P1 wrapper fixed keys/maximum IDs/finite numeric date in tests; reserve at most8192bytes of metadata in the mathematical bound, not as a memory allocator claim. Do not implement speculative P3 fields/owner/event wrappers now. Failure/control-character bound24576 plus header stays below raw cap. Oversized Unicode-escaped/whitespace spellings reject by raw cap, without reducing decoded payload limit. No double-base64 outer-envelope claim.

## Finite verification

Follow P1’s12 meaningful test groups, including all results; full consumer/provider payloads and maximum identifier lengths; raw oversized versus decoded oversized; closed shapes/schema/kind/result, UUID/type/deadline failures; mismatch for every reply result; exact reason byte limits/unknown code/contradictory refused outcomeUnknown; nil profile; dedicated full provider frame succeeds while equivalent generic event remains beyond its unchanged bound. Parameterized cases may share test bodies; do not target a predetermined total. No redundant tests mirroring simple property assignments.

Capture preimages, meaningful compiling RED then GREEN with actual logs, exact frozen diff/hashmanifest. Reuse adjacent contract tests once needed, not full package/app delivery from the worker. Root independent review then full package and exact signed app build/link/normal restart. Pure codec tests do not measure allocator/RSS or authenticate peers. Public full AddonServiceClient, subscriptions and P2/P3 host/SDK wiring remain subsequent work; no unimplemented stubs are shipped as a complete client.

## Delivery

[990 tests / 90 suites, independent PASS and signed delivery](../verification/2026-09-18-addon-service-invocation-frames.md). Optional intrinsic outer/nested rejection remains P3; entire-reply validate(matching:) is mandatory before projection.
