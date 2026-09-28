# Native direct-control v1: launcher remains blocked

10 September 2026. The accepted `autonomousOSDelegation` limitation remains accepted. It does not explain or excuse the managed-worker cleanup failure below. No production launcher, publisher, or additional OS is enabled. The historical `launcher-admission` evidence and decision are unchanged.

## Finite hypotheses and public APIs

1. **launchd-owned helper, unchanged worker process group.** Before implementing, the installed `launchd.plist(5)` manual was checked: `AbandonProcessGroup=false` means launchd kills remaining processes in the job's process group on job death. [Apple's launchd guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) directs readers to that manual. Expected red-to-green: supervisor SIGKILL must stop a sandboxed noncooperative child. The positive case succeeds, but public `setsid()` and `setpgid(0,0)` let the managed child leave the group. No unsupported sandbox profile is used to forbid those operations.
2. **helper joins the child's group before untrusted exec.** Trusted code creates the child group, signals readiness over a pipe, moves the helper into that group, then releases an exec gate. Expected evidence: launchd follows the helper's current group. It does not in this probe: the child outlives helper death. This is a separate refinement of the same containment mechanism, not a repeated old launch.
3. **authenticated message identity across exec.** Public `mach_msg` audit trailers (`MACH_RCV_TRAILER_AUDIT`), [`kSecGuestAttributeAudit`](https://developer.apple.com/documentation/security/ksecguestattributeaudit), `SecCodeCopyGuestWithAttributes`, and `SecCodeCheckValidity` distinguish a queued old message from an exec replacement at the same PID. This scoped component proof passes, including actual session revocation before either rejected message can be accepted.

The suggested fresh-session arrangement cannot simply fix hypothesis 2: `setsid(2)` makes the helper a session leader, and `setpgid(2)` explicitly returns EPERM when asked to move a session leader. The final helper actually ran in session 1; no isolated fresh session is claimed. No additional process topology was tried.

A dual-held pre-exec task control right was examined only for feasibility. Apple's [published XNU exec implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_exec.c) switches from `old_task` to `new_task` and terminates the old task after exec (`proc_exec_switch_task`, then `task_terminate_internal(old_task)`, current source lines 5289–5291). A stable PID is therefore not evidence of a stable task control right. This source is implementation evidence, not a public lifecycle guarantee or a native test on this kernel. No task-for-pid/get-task-allow entitlement, private API, or task-right variant was introduced; that possible route is unqualified.

The local SDK documents `xpc_connection_set_peer_code_signing_requirement` from macOS 12 and says received messages are checked against the requirement. That is relevant to a future supported XPC transport, but no production XPC session is qualified here. [Apple's Mach IPC guidance](https://developer.apple.com/documentation/xcode/conforming-to-mach-ipc-security-restrictions) recommends higher-level IPC and documents enhanced restrictions. This raw Mach fixture is diagnostic, not a production transport recommendation.

## Signed native observations

Only macOS 27 beta **26A5425a**, arm64, SDK 27, Apple Development team **A6A5HQL6K4** was executed. Deployment target 14 is a compilation setting, not macOS 14 runtime qualification. Other OSes, Intel and other publishers remain unverified.

Final group artifacts: `/private/tmp/cascade-direct-v1-group.i18dNl`.
Final raw group logs: `/private/tmp/cascade-direct-v1-logs.6gf1vec1/results.json`.

| Case | Helper / worker PID | Verified sandbox | Worker exit observed after helper crash marker | Cleanup case |
| --- | --- | --- | --- | --- |
| Unchanged group | 67713 / 67714 | Yes | 0.00726 s | Pass |
| Worker calls setsid | 67717 / 67718 | Yes | 2.68176 s | Fail |
| Worker calls setpgid | 67726 / 67728 | Yes | 2.52489 s | Fail |
| Helper joins child's group before exec | 67739 / 67740 | Yes | 2.50294 s | Fail |

All four cases independently observed **both helper and worker NOTE_EXIT events with kqueue**. Printed kill intent alone cannot pass. Registration/observation errors remain unknown, not exits. In the last case helper `setpgid(0, child)` returned 0, and both helper and worker reported group 67740; launchd cleanup still did not stop that group promptly. The other two escape calls returned success. Workers exited near the three-second diagnostic alarm, which is expressly not containment. These fixtures idle in `pause()` and allocate no stress buffer; no CPU spinning is needed to prove survival.

The worker has a real signed App Sandbox profile, not assumed ancestry inheritance. Each final group case denied a known-existing foreign file open and a connection to the harness's own listening loopback socket with EPERM. The harness positively opened the same file (without reading contents) and connected to that socket. Pre-exec soft/hard RLIMIT_NPROC is zero and raising it fails with EPERM. No arbitrary user application was opened. Signalling targets only the helper itself; the harness never signals a worker by PID/name. Each external case has one five-second budget, one second reserved for cleanup, and a three-second diagnostic alarm armed before untrusted exec. Every temporary launchd label was successfully booted out. This is an observation harness, not authenticated production process management.

Final audit artifacts: `/private/tmp/cascade-direct-v1-audit.LBkQil`.
Final raw audit logs: `/private/tmp/cascade-direct-v1-audit-logs.8pgjjnbt/results.json`.

The signed original sent a handshake, then a queued message and executed the separately signed replacement. The listener deliberately delayed validating that queued message by 350 ms. Identity is derived from the **kernel trailer**; PID, path and message payload are not authentication inputs. Full audit-token equality is used for the active session, plus fresh code validity checks per received message. The requirement pins Apple signature anchor, the original signing identifier, and the current team.

| Message | Audit PID/version | Security result | Accepted / session active |
| --- | --- | --- | --- |
| Original handshake | 67964 / 360627 | 0 | true / true |
| Queued old message, checked after exec | 67964 / 360627 | -67065, errSecCSNoSuchCode | false / false |
| Replacement replay | 67964 / 360631 | -67050, errSecCSReqFailed | false / false |

The replacement received rejection and exited 0. Both original and replacement denied the foreign file with EPERM. The original fixture's sandbox adds only the uniquely generated diagnostic service to the documented [global Mach service lookup exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html); the replacement has exactly app-sandbox plus inherit. This added fixture-only exception is explicit and does not silently become a production addon permission. The audit test is an isolated identity component, not a pre-exec quota/managed-lifecycle test. Mutual peer authentication, same-identifier replacement/reconnect admission, and integrated runtime session lifecycle still need qualification.

## Reproduction and evidence discipline

```sh
/bin/zsh scripts/test-addon-direct-v1-group.sh
/bin/zsh scripts/test-addon-direct-v1-audit.sh
python3 -m unittest discover -s Prototypes/AddonPlatform/Tests -p '*EvidenceTests.py'
python3 Prototypes/AddonPlatform/DirectV1/evidence.py --compose \
  /private/tmp/cascade-direct-v1-logs.6gf1vec1/results.json \
  /private/tmp/cascade-direct-v1-audit-logs.8pgjjnbt/results.json \
  Prototypes/AddonPlatform/DirectV1/Results/launcher-admission-direct-v1.json
```

Both final native characterization commands exit 0 after recording the observed results; they do **not** mean launcher admission. The composition/validation command writes the separate direct-v1 record and exits **1**. It requires exact scenario, policy and accepted limitation, strict boolean checks and no unverified cases. The isolated audit proof is stored under observations and never promotes an unintegrated launcher check. All eight admission checks remain false for the new unqualified arrangement. The original direct-child's previously measured metrics/stops are not relabelled as evidence for the new arrangement.

TDD regressions were observed red before implementation: missing direct-v1 validator, kill-intent without helper exit incorrectly passing, missing audit evaluator, and component proof being incorrectly usable as integrated admission. The final suite has **23 passing tests** (13 new direct-v1, 10 existing completeness). It rejects false/missing/truthy checks, wrong policy/scenario/limitations, unknown cases, missing observations, alarm-duration exits, missing authentication messages, generic API errors mislabelled as stale identity, active/reused sessions, and isolated identity proof promoted to launcher success.

Earlier diagnostic mistakes remain excluded from qualification: the initial standalone worker lacked signed Info.plist and failed App Sandbox initialization with SIGTRAP; a /tmp read and socket creation did not establish sandbox restrictions; C CLOCK_MONOTONIC was initially compared to Python's different `monotonic()` clock domain; output files inside the signed executable directory produced EIO/empty logs. Final probes add signed Info.plist, actual foreign-file/connect checks, compare C CLOCK_MONOTONIC with Python `clock_gettime(CLOCK_MONOTONIC)`, keep logs in a separate directory, and require kernel exit observations. These are harness corrections, not new containment mechanisms.

## Remaining gate

C0 is **blocked on managed-worker cleanup independent of the supervisor**, not on the already accepted autonomous OS delegation risk. Identity now has a positive bounded component proof. It still needs integration with a launcher whose cleanup works. No qualifying replacement launcher exists, so repeating 20 lifecycles, cost/reuse and metric qualification for this failed arrangement would not resolve the blocker. No production reuse window or new supervisor resource budget is selected. The previous benchmark and delegated-work counterexamples remain in their historical record. The result requires an architectural mechanism with concrete public-API evidence; it does not require the user to reaccept the same limitation.

## Review correction and new group evidence

The distinction between a launchd stop and the emergency timer now also requires the guardrail's minimum deadline, recorded before `alarm()` on the same clock as the measurement. The whole one-second window must precede it; a late crash near the alarm cannot produce a PASS. A timeout during cleanup of the identity proof is preserved in the report and does not prevent the independent attempt to remove the launchd job.

New signed run: `/private/tmp/cascade-direct-v1-review-native.log`, results `/private/tmp/cascade-direct-v1-logs.0992jf1h/results.json`. The original group is cleaned up in 7.94 ms; `setsid`, `setpgid` and moving the supervisor still fail (exit after 2.503/2.549/2.446 s, caused by the guardrail). All job removals are recorded as successful. The updated admission record keeps every integrated check false; the earlier isolated identity proof remains separate.

### Further source review: tracing the child

The public [ptrace(2)](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/ptrace.2.html) manual describes `PT_TRACE_ME`; Apple's [exit source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_exit.c) contains the stopping of traced children when the tracer terminates. This suggests another hypothesis, but does not demonstrate a distributable launcher: the [ptrace path](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/mach_process.c) calls `cs_allow_invalid` for child and parent, and the [corresponding implementation](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_cs.c) can relax signature and memory protections when the policy allows it. It was not established that the path works while preserving all current guarantees after exec. This is only a feasibility review of the source, not a new native test or a general impossibility; no debugging right or signature protection was changed.
