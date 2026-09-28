# Addon runtime: progress on 10 September 2026

The feature is not complete. The C0 investigation has finished with outcome **blocked**; independent parts of C2, C4 and C12 are available, extended in the continuation described below. The user later [accepted the risk of delegated work](../specs/2026-09-10-addon-control-policy.md). The plan was updated on that boundary alone; no launcher has been enabled and the other technical defects remain to be resolved.

## Code implemented and reviewed

- `PublicationStore.accept([Publication], owner:)`: up to 16 distinct identities, one shared instant, atomic update of contents/quotas/revisions. The failure of one entry restores every previous entry. One count per batch, with no copies of the store. Four new tests, including a mutation test that detects the omission of the byte restoration.
- `ResourcePolicy` and `ResourceGovernor`: host reservations, per-addon and global limits on work, content, admitted memory and disk; reservation metadata counted; canonical release per owner and automatic release at the end of the operation, even on error. Ten new tests. The memory values are admission estimates and not instantaneous process limits; they are not yet connected to the launcher, scheduler or broker.
- `cascade-addon validate`: a Swift executable that depends only on the public contracts. It reads regular files with a limit before parsing, uses AddonManifest.decode and returns distinct outcomes for invalid data and wrong arguments. Four new tests and verification of the real executable. [Guide](../../addons/README.md).
- C0 harness: report validator and regressions so that an observation error is not taken as proof of exit, nor a missing message as authenticated invalidation. Shared five-second deadline within the limits of the required waits. Ten validator tests and eight for the evidence producer; they do not replace native observations.

## Verification of the first increment

Full suite: `swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-swift-build --no-parallel --disable-sandbox`, Xcode beta. **248 tests passed**, exit 0: Runtime 49, Presentation 15, engine 156, Contracts 24, tool 4. Log `/private/tmp/cascade-completion-current-all-tests.log`.

The behavioral REDs and the targeted GREENs are preserved. The reviews of the three Swift parts passed; the three findings of the C0 review were also corrected and reassessed. No commit or staging of the pre-existing work.

The [native tests](2026-09-10-addon-launcher-decision.md) preserve the counterexamples. Twenty termination sequences of the direct child and forty echoes produced measurements, without qualifying the launcher. The worker can survive the supervisor and can start a harmless fixture through Launch Services; the executable change keeps the diagnostic channel. The later harness fixes have new deterministic tests; they are not presented as a new run of the old native experiments.

App build: **succeeded**, exit 0, with the official script from the verified local copy. The start from the iCloud checkout had stalled in NSFileCoordinator before compilation, confirmed by sample; before the new attempt 259 identical input files were compared. Deep/strict signing verified and `/Applications/Cascade.app` updated to the `CascadeAddonDevelopment` build. Relaunch verified: PID59576 → PID65407, same expected path in DerivedData. Logs `/private/tmp/cascade-completion-current-app-build-local.log` and `/private/tmp/cascade-completion-current-restart.json`. The toolchain emitted warnings about the SWIFT_DEBUG_INFORMATION variables in the post-action; no compilation errors. The overall review of this increment passed and does not certify completion of the feature.

## Continuation after the decision on direct control

- `ActionJournal`: duplicate request without new work, distinction between send/receipt/outcome, uncertain result without automatic retry, rejection of responses from other generations; space for the response reserved before the command.
- `AddonScheduler`: one job per addon and two global, four pending commands, coalesced updates, priority with aging and slots released only on the actual completion of the job. Expired deadlines and deactivations are returned to the coordinator, with no silent loss of commands.
- `DeadlineQueue` and `RuntimeInstant`: civil dates separated from elapsed time, bounded replacements and a single drain after sleep/wake. No timer or process of their own.
- `AddonHealthStore`: bounded version history, quarantine, retry delays, single-use tickets and invalidation of old sessions. No sampling or native termination is attributed to this pure component.
- [New C0 tests](2026-09-10-addon-direct-v1.md): isolated message check through the audit token, positive after exec, including a response already in the queue; launchd group cleanup insufficient for managed processes that change group/session. The new record `launcher-admission-direct-v1` remains negative; the limitation already accepted is not extended.

The reviews corrected the recomputation of the civil deadline of an already admitted command and two problems in the new harnesses: possible confusion between guardrail and actual termination, and loss of the report during cleanup errors. The version-health review also corrected an alias of the version number that could split the quarantine histories; the three targeted reviews concluded with no open findings. The new pure components must still be connected to the production runtime and to the aggregate resource control. [Lifecycle contract](../../addons/lifecycle.md).

Verification of the continuation: **288 Swift tests passed**, exit 0 (Runtime 89, Presentation 15, engine 156, Contracts 24, tool 4), log `/private/tmp/cascade-direct-v1-final-swift.log`. **36 Python tests passed**, log `/private/tmp/cascade-direct-v1-full-python.log`. The new Swift cases are 40: 26 on scheduler/deadlines/actions and 14 on health/retry. The behavioral REDs of the corrected defects are preserved. The warning about the weak variable in the old PublicationStore tests is pre-existing.

25 exact files integrated, with a content check against the baseline and the changes already present; 267 identical build inputs compared between the local copy and the iCloud checkout. No commit or staging. The overall review of the continuation passed with no P1/P2 findings. App build **succeeded**, exit 0, through the official script `scripts/build-development.sh` from the verified local copy; deep/strict signing verified and the `/Applications/Cascade.app` link updated. The two previous instances, PID66182 and PID73001, were closed through the native APIs without forcing; at the final check a single updated instance is running, PID74458, in the expected path `CascadeAddonDevelopment`. Logs `/private/tmp/cascade-direct-v1-app-build.log` and `/private/tmp/cascade-direct-v1-restart.json`. The results of the first increment above remain historical. This verification concludes the present increment, not the complete feature.

## Services and state continuation

The [services and checkpoint report](2026-09-10-addon-services-storage.md) records the next increment: host broker, permissions, shared interests, requestID protection and bounded persistence with migrations. The counts and relaunches reported above remain historical evidence of their respective revisions.

## Actions continuation

`ActionAuthorizer` and `ActionDispatcher` add authorization on the current content, a check at single-use consumption, transactional composition of the journal/scheduler and combined local accounting. 36 targeted tests passed, 15 new. Recovery of the outcome after removal of the publication was corrected and reassessed: the history remains accessible to the authorized context without creating further work or renewing the deadlines. Two minor observations on style and pre-existing warnings remain noted; the actor coordinator, the global quota and the native transport are not included in this test. [Contract](../../addons/actions.md).

## Coordinator continuation: 12 September

`AddonRuntime` now composes the pure components with canonical authority, a shared governor,
coordinated admissions and returns, durable interests and completions independent
per session. The [current verification](2026-09-12-addon-runtime-composition.md) records
104 targeted tests, 436 full serial tests and an approved review with no findings requested.
The code is in the isolated copy; integration into the app and qualification of the processes
remain separate. The earlier counts and relaunches above are historical evidence.

## Remaining work

C1 requires an admitted launcher and real identity/channel. C2 now requires connecting the approved coordinator to real delivery and to the app; C3 connecting the broker to real transport, caches and sources; C4 native metrics and connecting health decisions to verified termination; C5 keyed SDK storage, assets and restoration of publications. C6–C10 cover Clock, timers, SwiftUI scenes, notices and media on the public path. C11–C13 cover distribution, remaining tools, parity, platforms and final measurements. The macOS 14 minimum, other publishers and remote scenes are not qualified by the available beta machine.

The [plan](../plans/2026-09-10-addon-runtime-completion.md) remains the source of the remaining work. The product decision on delegated work is resolved. No native addon is admitted until termination, identity and the other controls of the updated profile are proven.

## Verified delivery of 12 September

C2b2 coordinator and C0o diagnostics approved and integrated: 43 files, 332 identical build
inputs. 436 serial Swift tests passed; 54 historical tests and 26 prototype tests passed.
The bootstrap with inherited sandbox completed 4 cases and 8 observed normal exits,
with separate data and continuity of the same owner. Signed build succeeded from the identical
local copy, Applications link updated and relaunch verified from PID8956
to 47210. The Xcode launch on the original project was waiting on file coordination;
that process was interrupted, without modifying iCloud or Xcode.

The feature remains open: keyed storage, transport and death of managed processes,
real integration into the app, migration of our widgets and final qualification.
[Runtime and delivery](2026-09-12-addon-runtime-composition.md),
[bootstrap evidence](2026-09-12-addon-owner-bootstrap.md).

## Keyed storage backend: 12 September

C5b implemented and reviewed: values independent of the checkpoint, isolation per
publisher/addon, quotas shared with the other consumers, atomic writes, separate
cache and recovery after close/errors. The first review found an error in the
recovery of folder synchronization; the fix has a behavioral reproduction
over nine scenarios and a targeted re-review. 38 targeted tests and 474 library
tests in serial mode passed on the final version. The initial result of
471 tests remains historical. SDK transport and the rest of C5 still open.
[Verification and delivery status](2026-09-12-addon-keyed-storage.md).

## Worker death diagnostics: C0d offline

The new observer and the finite D0–D3 protocol are approved at the offline level:
35 new tests, 54 historical and 26 owner tests passed. The F01 fix keeps stdout and
adverse observations when the proc registration is rejected. G01 is a distinct operational
requirement: the driver terminates with exit 78 before setup and compilation.
The native test remains suspended because of the boundary of the parent lost before PT_TRACE_ME;
no platform outcome is inferred from the simulated tests. C0 and the feature
remain open; the independent work completed the C5c1 raster backing described below.
[Current report](2026-09-12-addon-managed-death.md).

## C5c1: raster backing approved, 12 September 2026

Implemented: immutable CoreGraphics memory, raster quota within the overall budget,
protected reservations and release limited to the last actual reference. The independent
review approved conformance and quality with no findings. 37 targeted tests and 498 full
serial tests passed on the frozen source; no new warnings in the final log.
AssetState/SDK, decoders and authorizations, renderer, cache and restoration remain.
No native/tracing test added and the C0 gate is still HOLD. The user asked
to stop after delivering this task; no C5c2 started.
[Contract](../../addons/assets.md) and [verification](2026-09-12-addon-raster-backing.md).
