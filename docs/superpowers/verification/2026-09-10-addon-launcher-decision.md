# C0 launcher decision — blocked

Decision: **blocked**. No production launcher, manifest capability, publisher or OS is enabled.

## Decisione successiva dell'utente

L'utente ha accettato il rischio del lavoro autonomamente delegato a macOS: [confine approvato](../specs/2026-09-10-addon-control-policy.md). Non serve un'altra decisione su quel punto. Il verdetto negativo qui conservato riguarda il profilo rigoroso originario. Il nuovo profilo richiede ancora qualificazione: sopravvivenza al crash del supervisore e identità dopo exec rimangono problemi da risolvere. Nessun launcher è stato abilitato da questa modifica documentale.

## Public API review before variants (10 September 2026)

- `setrlimit(RLIMIT_NPROC)` before `exec`, `waitid(WNOWAIT)`/`wait4` and `proc_pid_rusage` remain the direct-child control primitive, compiled with deployment target 14.0. No public general deny-delegation entitlement was established. The readable, signed nested-app Launch Services counterexample must remain red.
- [Apple App Sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html) describes child inheritance using exactly app-sandbox and inherit keys. It does not promise containment of Launch Services work. The diagnostic replacement executable initially received its own App Sandbox entitlement and terminated with SIGTRAP before emitting replacement-ready. **Before changing its signature:** test the documented inherited-child profile on the replacement binary. Expected evidence change: `execReplacementObserved` becomes true; the retained pipe still does not qualify authenticated session invalidation. This is a fixture correction, not a containment proposal.
- [AppExtensionProcess.invalidate](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()) and [Apple's hosting guide](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app) describe invalidation of a connection and lifetime across connections. No newly found public API/version addresses the reproduced noncooperative-spin stop failure; no new ExtensionKit variant is justified.
- [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication) applies to tracked applications. The authenticated headless peer has no handle on this OS; no forceTerminate call occurs.
- [Endpoint Security entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.endpoint-security.client) requires Apple approval; it is not an entitlement available to ordinary addon admission. No privilege or approval was assumed and no Endpoint Security variant was run.

Only macOS 27 beta 26A5425a, arm64, Xcode beta SDK 27 and the existing Apple Development team A6A5HQL6K4 are available. macOS 14/15/26, Intel and another publisher remain unverified. Compilation for 14 does not qualify execution on 14.

## Scope of the evidence

The direct worker receives only App Sandbox, hardened runtime and pre-exec soft/hard process quota zero. It cannot raise the quota; direct spawn, foreign sentinel read, loopback connect and signalling its supervisor are denied. The exact newly built harmless nested app remains readable and launchable through Launch Services, with parent PID 1. Unrestricted positive controls exercise the same target and resources. These autonomous addon launches are not user-authorized source-app openings. No app belonging to the user is a target.

The supervisor signals only its retained, unreaped child; the host signals only itself or waits for its direct supervisor. The harness signals its own subprocess handle. Its ExtensionKit diagnostic cleanup checks the authenticated fixture's executable and start time, and is explicitly not atomic PID-reuse-safe production signalling.

The new supervisor-crash case intentionally kills the trusted supervisor. An addon-side three-second alarm is a diagnostic guardrail only; it is not crash recovery. Every external direct case has a five-second deadline, the allocation remains 16 MiB, and each echo worker is idle between requests. No authenticated direct-child XPC session exists, so post-exec session invalidation is not qualified.

## Original product decision request — now resolved

Maintaining the approved guarantee requires a demonstrated public pre-execution restriction or ownership/stop control over all delegated work. The current candidates do not provide that evidence. An alternative that admits native addons with only direct-worker CPU/footprint control would explicitly give up containment and accounting for autonomous Launch Services/services work, including possible survival after addon stop. **That specific guarantee change has now been explicitly accepted; the linked policy defines its scope. Other controls still require qualification before enabling.** Restricting a manifest, refusing only this nested bundle, or labelling a publisher trusted does not establish the original guarantee. Remote SwiftUI scenes and cross-publisher admission remain independently unqualified.

## Fresh bounded observations

Final signed diagnostic run: `/private/tmp/cascade-C0-direct-qualified-evidence.log`.
`/bin/zsh scripts/test-addon-direct-child.sh` exited **1**, as required by the failed
containment assertions. `codesign --verify --deep --strict` passed. All original
positive controls succeeded. Original explicit/normal/crash cases again failed only
`delegatedLaunchDenied`; their harmless launched PIDs 61915/61932/61941 had parent 1.
Signal-to-reap was respectively 0.75/0.72/0.67 ms; elapsed whole cases were
694.26/363.91/360.34 ms, including fixture launch and deliberately bounded spin.
Twenty additional start/stop sequences all killed and reaped the owned worker;
signal-to-reap min/median/max was 0.66/0.71/0.82 ms. Each still failed containment.

Supervisor death: supervisor injected SIGKILL, host reaped status 9. External `ps`
observed PID 61948 with parent 1 and the exact signed DirectWorker executable after
the supervisor exited. The case remained open for 3027.46 ms until the diagnostic
alarm; **`supervisorDeathStopsWorker = false`**. No runtime crash recovery exists.
This is a reproduced failure, distinct from an unexecuted test.

Executable change: the inherited signed replacement emitted on the original pipe
at worker PID 61957. Explicit SIGKILL/reap still worked (2.22 ms), but the diagnostic
channel survived the exec. **`sessionInvalidatedAfterExec = false`**. Authentication
and session invalidation after exec remain unimplemented/unqualified. The initial
own-sandbox replacement SIGTRAP is preserved in `/private/tmp/cascade-C0-direct-final.log`;
it was not counted as successful replacement or evidence of session invalidation.

| 20 echo requests | Immediate close, 20 workers | Reuse, one worker |
| --- | ---: | ---: |
| Total elapsed incl. nominal 20 ms gaps | 770.29 ms | 433.29 ms |
| p95 IPC reply only (excludes startup) | 0.017 ms | 0.088 ms |
| Worker CPU from wait4 | 0.083377 s | 0.004184 s |
| Sampled supervisor CPU | 0.042062 s | 0.003386 s |
| Sampled host + supervisor CPU | 0.091535 s | 0.005433 s |
| Peak simultaneous host + supervisor footprint | 2,376,448 B | 2,376,448 B |

The nominal 20 ms reuse interval is an observed prototype polling choice. Immediate
mode has 19 external 20 ms gaps. Total includes teardown/startup; IPC latency does
not. CPU conversion uses `mach_timebase_info`, worker CPU has independent `wait4`
measurements, host/supervisor readings end before final teardown, and this table is
one-machine diagnostic evidence, not a full energy or lifetime-cost qualification.
Reuse reduced CPU and elapsed time but had higher measured IPC p95; no production
reuse policy is selected while admission is blocked. Supervisor footprint in the
original cases was 1,180,032 B; its active lifetime is one worker lifetime.

ExtensionKit: fresh Release lifecycle still fails explicit invalidation; normal
host exit and crash observed provider exit. The application-stop repetition had
host/provider 61628/61630, `applicationHandlePresent=false`,
`forceTerminateInvoked=false`, no exit while host remained open. It is an absent
headless application handle, not a rejected forceTerminate invocation. Raw logs:
`/private/tmp/cascade-C0-lifecycle-final.log` and
`/private/tmp/cascade-C0-application-stop.log` (both commands exit 1).

Admission JSON has managedStop/hostExitCleanup/hostCrashCleanup/cpuReadable/
footprintReadable true for the measured direct-child cases; identitySafe and
delegatedWorkControlled false. Unverified entries additionally name other OSes,
cross-publisher admission, authenticated post-exec session invalidation and crash
cleanup independent of addon cooperation. The completeness CLI exits 1.

Final evidence-producer rerun without rebuilding, `/private/tmp/cascade-C0-final-harness.log`,
also exited 1. It independently checked the replacement executable path at PID
62520 and the live orphan path/parent at PID 62497. Admission booleans were unchanged;
all 20 repeated owned stops and 40 echo replies were observed. Final timing was
772.19/434.46 ms immediate/reuse, IPC p95 0.018/0.119 ms, sampled host+supervisor CPU
0.091691/0.005560 s. These repeat measurements do not change the blocked decision.
A final read-only exact-path process check found no remaining fixture workers or
providers. Ten completeness CLI tests pass; the real admission record still fails.

## C0 review correction: evidence producer, not new platform qualification

The scoped correction separates diagnostic pipe survival from authenticated
invalidation: missing/truncated replacement output or fixture failure cannot turn
`sessionInvalidatedAfterExec` or `identitySafe` true. The former stays false because
this prototype has no affirmative authenticated invalidation mechanism.

ExtensionKit process observation now records return code/stderr and distinguishes
present, absent and error. `ps` queries the target and the harness's own PID as a
positive observation control; absence requires successful output containing that
control. Denied/failed/timed-out observations are unverified failures, not exits.
One absolute five-second deadline covers handshake, observation and cleanup; one
second is reserved for cleanup, every blocking timeout uses the remaining phase
budget, and authenticated provider cleanup precedes bounded output collection.
`communicate` timeout is recorded without skipping cleanup. Path/start-time checks
remain diagnostic and non-atomic. Deterministic clock/subprocess regressions verify
the producer behavior; no new native run or physical timing claim is made here.

The controller's additional primary SDK review is confirmed in the local SDK 27
`usr/include/sandbox.h` lines 24–55: `sandbox_init` is deprecated as **No longer
supported** since macOS 10.8; flags must be `SANDBOX_NAMED`, all other flags reserved.
The current header does not provide `kSBXProfilePureComputation`. Old web examples
are not evidence of a supported custom SBPL/profile restriction. No private flag,
old SDK assumption or new sandbox variant is introduced. The finite investigation
and blocked launcher decision are unchanged.
