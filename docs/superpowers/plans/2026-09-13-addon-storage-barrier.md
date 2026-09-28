# Global Storage Admission Barrier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Continue the approved C5 persistence boundary without reopening product decisions.

**Goal:** Never expose normal persistence operations until both checkpoint and keyed retained inventories are reconciled under their common governor.

**Architecture:** A persistent internal AddonStorageCoordinator privately owns both existing backends, a fixed complete retained registry, a readiness epoch and bounded owner capabilities. It opens checkpoint first and keyed last, keeps normal operations gated during startup/retry/close, and reuses the keyed object's durable ledger across reopening.

**Tech Stack:** Existing AddonStateStore, AddonKeyedStorage, ResourceGovernor, Foundation/POSIX storage; Swift6 and macOS14 floor.

**Spec:** C5 in 2026-09-10-addon-runtime-completion.md and docs/addons/storage.md prescribe this startup barrier. The user requested continuous implementation until a real design choice; this is an already prescribed dependency.

## Global Constraints

- Preserve dirty workspace, no bulk commits/resets. No native addon launches or C0d gate changes.
- Backend formats, quotas, path checks and atomic rename semantics remain unchanged. No second persistence backend or custom codec.
- Keep backend actor references and StateOwner/KeyedStorageOwner capabilities private. All normal operations pass through coordinator readiness and opaque owner checks.
- Support one fixed complete nonempty registry of1–256 retained identities, including disabled/uninstalled addons. Document the empty-registry and dynamic-registry integration limits; never omit retained identities silently.
- Proportional registry/session metadata must be prepaid through the common governor before coordinator retention. At most one coordinator operation/startup in flight, no unbounded waiter queue or polling.
- Close invalidates readiness/capabilities before awaiting backend work. In-flight accepted work may finish under existing backend commit semantics; new work is denied. Draining is not closed.
- Checkpoint close refunds its own pools and leaves files. Keyed close retains durable pools and metadata: keep and reopen the same keyed object/root inode, never duplicate that ledger on the same governor or call releaseAll.
- Partial failures stay unavailable, retain objects requiring cleanup, and can be retried without double charging or deleting committed data. Recheck startup authority after every await.
- Each backend still admits its own full inventory before recovery cleanup. The global gate forbids normal work until both succeed; no new cross-root atomic inventory transaction is claimed.
- No authenticated SDK storage transport, publication restoration or app bootstrap wiring is claimed by this host primitive.
- Full serial suite, frozen-input signed build, Applications update and verified normal restart before final delivery. Weekly usage must stay below60%.

## Task1 — Coordinator implementation and real filesystem tests

Files: new CascadeRuntime/Storage/AddonStorageCoordinator.swift and Tests/CascadeRuntimeTests/AddonStorageCoordinatorTests.swift. Use existing backend types and test resource/file seams; do not edit backend algorithms unless a reproduced integration bug requires a reviewed fix.

Interfaces: internal factory `make` validates/prepays coordinator registry metadata and returns an unavailable persistent object; `start() async throws` reconciles both roots; `close() async throws -> CloseStatus` distinguishes draining/closed. Host-only owner acquisition returns an opaque coordinator-owned capability tied to readiness epoch. Forward keyed read/write/remove and checkpoint read/write through bounded current-owner admission; do not export raw stores or owners. Keep the fixed registry/ledger reservation charged while the reusable coordinator remains closed, like keyed storage.

- [x] Write real-directory tests and observe a relevant compiling behavioral RED.
- [x] Implement fixed registry validation/prepaid metadata, ready epoch, private capabilities and guarded forwarding.
- [x] Verify second-root failure leaves no usable owner; committed bytes survive; retry after repair succeeds without checkpoint/keyed double accounting.
- [x] Verify no owner/work escapes suspended startup, close/cancellation invalidates startup, old capabilities fail after reopen and competing work is rejected.
- [x] Verify shared governor disk limits, keyed ledger persists across close/reopen, no silent refund or cleanup of committed user data.
- [x] Save exact diff/report; independent spec/quality review and fix concrete findings.

## Task2 — Evidence and delivery

- [x] Update storage docs with exact barrier contract, fixed registry/lifecycle bounds and remaining runtime/transport integration.
- [x] Run full serial suite in one normalized temporary copy (avoid duplicated build caches after prior disk pressure).
- [x] Verify frozen inputs, signed development build, Applications link and normal restart/new PID.
- [x] Record current allowance (25% consumed). Independent audit identified a genuine durable archive decision; pause for that choice as requested. See 2026-09-13-addon-restoration-archive-decision.md.

**Evidence:** 560 serial tests passed, 358 inputs frozen and reverified, signed build/link update succeeded, normal restart PID73683→76239 verified. See [verification](../verification/2026-09-13-addon-storage-barrier.md).
