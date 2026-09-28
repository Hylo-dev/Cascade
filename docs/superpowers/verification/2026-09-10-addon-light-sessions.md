# Addon runtime: lights, sessions and result memory

Continuation of [services and checkpoints](2026-09-10-addon-services-storage.md). The user asked to verify their extension for the light effect, correct it if necessary and continue with the parts already designed. No new concession on process control. **Increment implemented and reviewed: 385 Swift tests passed, signed build succeeded and relaunch verified.**

## The user's lights preserved

25 files updated by the user were compared and copied into the local worktree: GlassLight, schema 2 of ContentDocument, SwiftUI preferences, source collection and invalidation, renderer and music response. Every copy was preceded by a check of the local version. No correction to their implementation turned out to be necessary.

The review verified the values and the limit of eight lights, compatibility with schema 1, cleanup of replaced, hidden or sensitive sources, protection from late deliveries, the absence of timers or additional capture, and static color when paused and with reduced motion. The contract remains the one chosen by the user. [Lights guide](../../architecture/glass-lighting.md).

The baseline with these changes passed **360 Swift tests**, exit 0: Runtime 133, Presentation 20, engine 169, Contracts 34, tool 4. The 23 additional cases compared with the earlier verification of 337 come from the user's work. `scripts/test-music-glass-light.sh` also passed, exit 0. Log: `/private/tmp/cascade-light-baseline-swift.log` and `/private/tmp/cascade-light-baseline-music.log`.

## C1a: negotiation and publications

The library supports protocol 1.0 and content schemas 1/2. Every connection agrees on a subset compatible with the provider's offer and with the manifest requirement verified by the host. All representations, including the future timeline ones, must use an agreed schema. Schema 2 remains required even when it contains no lights: no implicit removal of the effect or change of document version.

`PublicationStore` keeps the connection's authority, the generation, the sequence and the IDs assigned by the host. It validates the message before modifying the publications and updates the sequence only after a successful batch. A rejection keeps the earlier contents and revisions. A normal close keeps history and contents; replacement invalidates the old handle, and removal of the owner revokes the authority before erasing the state.

The registry admits at most 32 active connections and 256 publisher namespaces, with limits the host can reduce and local charges of 4,096 and 1,024 bytes. It does not preallocate buffers for all installed addons. These charges use the store's local budget; the connection to the runtime's shared limit remains to be done.

The **41 targeted tests** passed, exit 0: 18 new cases and 23 existing ones. The new tests showed behavioral failures before the implementation. The specification and quality review is approved without P1/P2. A later targeted check found two redundant JSON scans and encodings in the schema check: the two duplicate calls were removed, keeping the admission checks, and the same 41 targeted tests passed again. This is not a measurement of performance or energy consumption.

The verified identity, the digest and the admitted IDs come from the host. The new boundary does not verify signatures or audit tokens, does not decode transport frames and does not run service operations. It returns operations, completions and checkpoints as checked values: only the publications are applied. `endPublication` too remains an operation to be authorized and applied in the future coordinator. [Sessions guide](../../addons/sessions.md).

## C4a: unused capacity returned to the budget

`ResourceGovernor.reduceStateReservation` reduces an already existing state reservation in a single operation, without releasing it and reopening it. It verifies the canonical owner and reservation, admits only reductions and keeps the reservation's 1,024 bytes of metadata until the actual release. It also works when the budget is completely full. It does not modify process, job, asset or disk quotas.

Before sending, the broker still reserves input, metadata and the whole possible 65,536-byte response. After a final outcome it keeps input, metadata and the real result, returning the unused space. A three-byte response therefore returns 65,533 bytes to the budget. The response and the ID stay retained for the original ten minutes: no new authorization to repeat the command.

Response, error, timeout, disconnection and revocation use the already existing events for recovery. The corresponding flag lives in the request record, within the limits of 128 records per owner and 1,024 globally; no new timer, task or periodic check. The outcome becomes final before the wait on the governor. Recovering a result repeats, after the wait, the checks on permission, connection, binding and expiry. Expiry and shutdown do not recreate removed records; the process's reservations remain until its observed exit.

**42 targeted tests in three suites** passed, exit 0, with seven new cases. They cover full quota, maximum and small result, nine terminal events, revocation before and after recovery, changed binding and concurrent cleanup with foreign resources preserved. Final log: `/private/tmp/cascade-reduction-final.log`. The precise suspension point during a revocation is a code-level check: no fake governor or test hook was introduced to force that order. Independent specification and quality review approved without P1/P2; the revalidation after the wait on the governor was also checked. [Services guide](../../addons/services.md).

## Final verification and limits

The full suite after the changes passed **385 tests**, exit 0: Runtime 154, Presentation 20, engine 169, Contracts 38, tool 4. That is 25 new cases from this increment compared with the baseline with the user's lights. Log: `/private/tmp/cascade-light-sessions-final-swift.log`. All 25 files of the lights change keep the content verified in the baseline.

The final integration review approved specification and quality with no open P1/P2/P3 findings. 21 files were integrated with a prior hash check in the original checkout; the 318 build inputs match the compiled worktree. No commit or staging.

`scripts/build-development.sh` finished with exit 0 using Xcode beta and DerivedData `CascadeAddonDevelopment`. The `--deep --strict` signature verification succeeded and `/Applications/Cascade.app` points to the new build. Log: `/private/tmp/cascade-light-sessions-app-build.log`.

The previous instance, PID 89540, was closed normally without a forced termination. The new instance, **PID 94732**, was observed running and stable with its executable in `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`. The relaunch concerns the updated version, not the earlier `CascadeDevelopment` build. Evidence: `/private/tmp/cascade-light-sessions-restart.json`.

While the tests were being prepared, the full disk interrupted a compilation before execution: it is not counted as RED. Only temporary SwiftPM caches from this work were removed, after verifying their tag, their references to CascadeKit and the absence of processes using them; sources, logs and the app build are preserved.

The pre-existing `weakProducer` warning remains in the old PublicationStore tests. This verification does not measure energy or physical memory and does not qualify VoiceOver or the macOS 14 minimum on another system.

**The native feature remains incomplete.** C0 is not admitted: the death of the supervisor can leave a managed worker alive. The acceptance of work autonomously delegated to the system does not cover that case. Real transport, frame credits, native identity, shared coordinator, provider launch and widget migration remain to be wired and qualified. The [completion plan](../plans/2026-09-10-addon-runtime-completion.md) keeps these phases open.
