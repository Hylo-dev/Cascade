# Actions and native control: 10 September continuation

Work is in progress. No production launcher has been enabled and the feature is not complete. The earlier [lights/sessions verification](2026-09-10-addon-light-sessions.md) remains historical; the results described here concern the new continuation.

## Authorization and commands

`ActionAuthorizer` checks the verified installation, the assigned feature, the current dependencies, a usable publication/revision and the input actually published. `ActionDispatcher` composes the journal and the scheduler within a single local limit of 8 MiB, including reserved results and metadata. Before delivery it consumes a canonical ticket exactly once and rechecks the current context.

Deactivation, timeout or loss of the connection after sending keep the outcome uncertain and require termination; the slot of a job that is still running is released only once its actual completion is confirmed. When the history expires, the minimal metadata of a job that is still running remain counted. The same requestID cannot be reused until the exact exit of the old job.

The review found, and had corrected, a concrete case: an action could close its own publication and make the already recorded result unrecoverable. Recovery now uses the identity and feature that are still authorized and the exact original request; it does not require a publication that is still present. New actions and delivery, instead, keep the check on the current content. A duplicate request does not renew the history and does not create a new job.

Current targeted verification: 36 tests in 4 suites passed, 15 new relative to the baseline. Log `/private/tmp/c2a-fix1-green.log`; the RED regression `/private/tmp/c2a-fix1-red.log` is preserved. Review of the fix concluded with no new problems. The formatting findings were then corrected and reassessed: 81 targeted tests passed and no residual findings. [Public contract](../../addons/actions.md).

These are host-owned components. The composition into the authoritative actor is now in progress, as described below; the transport and the real processes remain to be connected.

## Single state and quota changes

The content rules and registries have been extracted into `PublicationState`, a synchronous internal value. The public actor `PublicationStore` keeps the existing APIs and delegates to the same implementation. The runtime will thus be able to own content and actions directly, avoiding a check based on a snapshot that went stale during a wait. 45 targeted tests and independent review passed; the subsequent comment and formatting adjustments are complete and reviewed.

`ResourceGovernor` can now atomically change an already existing state reservation. Growth is admitted only for the necessary difference, respecting the shared limit and the owner's limit; shrinking returns space and keeps the ID and the metadata quota. A rejection leaves the counts and the other reservations unchanged. 55 targeted tests, including 8 new ones, and independent review passed. This operation changes the accounting: the runtime must still own and recheck the operation's authority before storing new content.

## Runtime composition: review history

Update of 12 September: the composition completed review with all findings resolved, 104 targeted tests and 436 full serial tests passed. The [updated report](2026-09-12-addon-runtime-composition.md) describes the approved sources and the limits; the following paragraphs preserve the earlier history.

The new `AddonRuntime`, still internal to the library, brings together content, actions, the authorized catalog and the connections to addons. The first implementation uses the same `ResourceGovernor` for its own resources and for the services broker. The following were added: preparation of updates before the commit, correlated completions, starting dependencies in the resolved order and recovering results without new work. An ordinary provider shutdown invalidates the old grants and keeps the interests that are still valid, to be reactivated through a new authorized acquisition.

The first independent review identified 22 findings. The first round of fixes passed 99 targeted tests in 8 suites, including 22 composition tests; the 14 hashes of the sources and of the evidence were verified. The new review confirmed 13 findings resolved, keeps 9 open and adds one: 10 requested fixes therefore remain, 6 P1 and 4 P2. They mainly concern the authority of service results, cleanup even when there is no active admission, the deadlines of individual requests, the capacity and transfer of data space, and the removal of still-authorized assignments from a connection. The second round of fixes was interrupted at the requested threshold of 20% remaining usage; the block is not approved. The targeted cases F01/F07 were reported as passing, but the changes of the interrupted round do not yet have an overall build and verification.

On the first frozen revision, 91 targeted tests in 8 suites passed. The subsequent full suite passed all 192 runtime tests, the 20 presentation tests, the 38 contracts tests and the 4 tool tests. Of the 169 engine tests, one failed: `controlDragKeepsExpandedContentAliveUntilMouseUp` did not observe the closed state within its own limit. Controller and test are unchanged relative to the baseline; the single test then passed in isolation, but the cause of the failure in the full suite is not yet demonstrated. The overall result therefore remains negative, with 423 tests run and one failure. Logs preserved: `/private/tmp/cascade-c2b2-full-package.log` and `/private/tmp/cascade-c2b2-control-drag-focused.log`. The targeted and full counts overlap.

On the frozen fix, a new full suite ran 431 tests: Runtime 200, Presentation 20, Contracts 38 and tool 4 pass; Engine 169 reproduces the same single failure. The 56 controller tests alone also reproduce it in the default run; the same build with `--no-parallel` passes them all, with the drag test finishing in 0.302 seconds. These observations indicate a dependence on concurrent execution, but do not demonstrate the precise mechanism. The overall default result remains negative; the interface sources were not modified. Evidence: `C2b2-fix1-root-package-verification.json` in the stage and logs `/private/tmp/cascade-c2b2-fix1-full-package.log`, `cascade-c2b2-fix1-notch-suite.log`, `cascade-c2b2-fix1-notch-serial.log`.

The initial start of the suite had been prevented by the external sandbox while compiling the SwiftPM manifest; the targeted run outside that sandbox allowed the verification without code changes. The test connections do not constitute authentication of real processes and do not enable a production launcher. Integration into the app, signed build and relaunch remain to be carried out after the required verifications.

## First compatibility test of native control

New signed fixtures use a trusted supervisor without App Sandbox and two test executables with only the App Sandbox entitlement; all have Hardened Runtime. No debug permissions or signing exceptions were added. The roles match the profiles already in use; Cascade's graphical process was not involved in the test.

On the available machine (macOS 27 beta 26A5425a, arm64, SDK 27, Apple Development signing, build target macOS 14), two normal comparison cases and one `PT_TRACE_ME` case produced six observed normal exits. The call returned 0; 18 snapshots kept Valid/Hard/Kill=true and Debugged=false, with consistent identity, signature and profiles. For the sandboxed processes, opening an unrelated file and connecting to the fixture's local listener were denied; the same accesses succeeded for the observer. The hardNproc=0 limit could not be raised.

Unchanged record: `/private/tmp/cascade-tracing-native.eqB11w/report.json`; hash inventory `evidence-sha256.json` in the same directory. The processes terminated normally, confirmed by a wait on the owned child and by kernel exit notifications; no guardrail produced those terminations.

The result concerns initialization. It does not yet demonstrate the worker's exec, inspection of the new identity while stopped, supervisor/host death or the complete integrity of every VM protection. The observations use distinct time domains for the native program and the Python observer: timestamps belonging to the two domains were not subtracted from each other. There is no measurement of termination latency on failure.

The review confirmed the credibility of the actual run and identified five verifier defects concerning partial evidence, progression and cleanup after an error. All five were corrected and reassessed; 25 offline tests pass. The original native record, preserved unchanged, also passes the stricter verifier. Native admission remains negative, and `allVMProtectionsPreserved` remains unknown. A valid signature for macOS 14 is not equivalent to a test run on macOS 14 or with distribution signing.

## Controlled exec and worker identity

A new build of the same fixtures ran two normal comparisons, the control-initialization case and a single Stub→Worker replacement case. The supervisor observed the child's real stop at exec, verified the new Worker identity while stopped through a fresh Security reference, and got success from the single resume call. The public bits and the profile remained consistent with the comparison of the same build.

The subsequent Worker check did not arrive within the original limit: SIGALRM produced a stop, the supervisor requested PT_KILL and observed the actual exit by SIGKILL. All eight created processes have an exit confirmation. The outcome of the case is **unknown**, not a demonstrated platform rejection. Original record `/private/tmp/cascade-tracing-exec-N142j3/report.json`, SHA-256 `fbcee615d9abc433af01b2bdd8ec845a5550459e782a2b91048faa476a899824`.

The checkpoint was written after several CF/Security calls: its absence did not localize the hang. The next test added markers before and after those calls, without lengthening the time limits or changing permissions. The verifier review also had two cases of overreaching conclusions corrected, with incomplete process identity or guard flags. The fixes passed independent review and 40 offline tests; the reassessment of the record keeps the observed worker replacement and the overall unknown result. The native evidence remains preserved and production admission remains disabled.

## Startup localization

A later fixture added markers at the Worker's entry and before/after the first CF/Security calls. 44 offline tests, the build of the three roles and independent review passed. A single new run of the comparisons and of case C preserved identity and public protections, but no Worker marker arrived. After the resume a further SIGTRAP was observed, followed by the controlled stop and the actual exit. This time the alarm did not expire; the difference from the previous test is preserved. All eight processes exited.

The system logs, read only for the fixture's PID and time window, show the start of the Worker's App Sandbox initialization and no explanatory error. The result remains unknown; it demonstrates neither a precise rejection nor an error in the addon's first call. Record `/private/tmp/cascade-tracing-localization-BpyVoV/report.json`, SHA-256 `c7987d2b2ae28d8048b5a2ab268ae539c4ab5d06b205af0d1901429770f105e0`.

## Comparison without tracing and crash report

A single new build repeated the comparisons and the controlled replacement, then ran the same transition without tracing. Profiles, signatures and limits remained unchanged. The controlled case again verified the new identity while stopped, resumed the Worker and observed SIGTRAP before the first marker. The untraced Worker also terminated by SIGTRAP before sending any markers. All ten processes have actual exit confirmations; in the untraced case no guardrails or termination requests intervened. 54 offline tests and independent review passed, with no open findings.

The raw records keep the result unknown: the intention to execute the Worker does not, by itself, authenticate the execution. Separately, the system crash report was correlated with the fixture through PID, parent, timestamps, signature and the UUID of the compiled executable. It localizes the failure of the untraced case in `_libsecinit_appsandbox`, during libSystem initialization, with the indication `SYSCALL_SET_USERLAND_PROFILE`, before the ordinary entry into the program. It does not specify the exact error, nor does it demonstrate that the controlled case has the same stack. The documented constraint on reinitializing the sandbox is consistent with the failure, but remains an inference about the precise cause. [Apple technical discussion](https://developer.apple.com/forums/thread/112800).

Unchanged native record `/private/tmp/cascade-tracing-untraced-13iaN3/report.json`, SHA-256 `9d1d51fecf06d4bf24f9dfe597de5d246a5e73a988b8bd2a497b1d5a8f215d0e`; crash extract `worker-crash-extract.json` in the same directory, SHA-256 `07c162092ab4582bce36dbc8f9141eeb3808ca12fc5ed4158c3d85d011b2cdb1`. This localization guides the fix of the startup configuration. It does not enable a new profile, does not qualify arbitrary addon code and does not yet demonstrate termination on supervisor death. The production launcher remains disabled.

## Integration and final verifications

The full suite of the foundations preceding the C2b2 composition passed: 408 tests (Runtime 177, Presentation 20, engine 169, Contracts 38, tool 4), log `/private/tmp/cascade-production-prerequisites-swift.log`. The targeted tests overlap and must not be added to this total. Not yet carried out for this revision: overall review, integration into the shared checkout, signed build and relaunch. The plan remains open. The user later requested an automatic stop at 20% remaining usage: the periodic check and the saving of the resume point are set up, with no automatic renewal of the limit and no automatic resumption of the work.

## Stop requested by the user

At 23:47:19 UTC on 10 September (01:47:19 on 11 September in Italy) the remaining usage dropped to 20%. The implementer was interrupted; the other agents had already finished and no Swift processes of the task remained. The periodic check was verified as paused, with no reset or automatic resumption. Sources, evidence and the resume point are preserved in the original project's checkpoint. No integration, app build or reopening of the updated version was carried out for this continuation.

## 12 September resumption and bootstrap with inherited sandbox

The new C0o fixture uses two distinct bootstrap identities and two Workers that inherit
the sandbox of their respective bootstrap. The planned test must distinguish continuity of
the same addon's data, denial of access to the other addon's data and controlled
replacement of the executable. It is not yet a production launcher.

The first invocation stopped during preparation: the signature verification command
interpreted the requirement as a file path. Only the Supervisor was built and signed,
without running it; none of the four cases and none of the eight planned processes was
started. The record keeps `unknown`, `complete=false` and `setupExit=1`.
It is an error in the fixture, not negative evidence about the platform.

54 historical tests and 16 tests of the new verifier passed, in addition to the syntax
checks of the script and of the eight C roles/configurations. The independent code review
is in progress. The initial report remains unchanged:
`/private/tmp/cascade-owner-bootstrap-eNbrVB/owner-report.json`, SHA-256
`3284962036f0f934c7cbca2f9e99edb8a7ddb726f03201bb6b9d61bb87ad5fcb`.
A single further preparation/run is planned after review and fix, with
the same limits, without repeating cases already measured or changing the permissions.

Correction of the earlier observation about Swift processes: during the check of
12 September an old `swift-test` and its helper were found, started on 11
September for a RED test. The absence of active sessions declared at the previous
checkpoint did not demonstrate their exit. They were precisely identified, interrupted
and observed exiting through kernel notifications before starting C0o. This cleanup of the
tests does not constitute evidence of addon termination.

The subsequent and only run after the fixes completed O1–O4, with eight observed normal exits. The [bootstrap report](2026-09-12-addon-owner-bootstrap.md) preserves results, provenance and limits; review of the fixes concluded with no open findings.
