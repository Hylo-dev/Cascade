# Targeted XPC test: 24 September 2026

**Outcome: three positive cases, cancellation with a live client negative. Launcher still blocked.**

Later update: the [test with a dedicated XPC intermediary](2026-09-24-addon-xpc-broker.md)
verified the stop of one chain while leaving the app and a second chain active.
It does not change the cancellation results recorded here, nor does it admit the launcher.
Explicit authorization: "ok, proceed with the targeted XPC test". Experiment separate
from the C0d driver and from the product code; it does not change the decision on orphaned managed processes.

## Native result

One complete run of the signed fixture on macOS 27.0 (26A5425a), arm64,
SDK 27.0, Apple clang 21.0.0. Each scenario uses a new incarnation.

| Scenario | Observation | Outcome |
| --- | --- | --- |
| Cooperative service, live client | Exit with status 0 observed about 0.6 ms after the trigger | PASS |
| Connection cancelled, live client, callback held | No exit observed within the two seconds; client still alive | FAIL |
| Ordinary client exit, callback held | Service exit with SIGKILL observed about 1.6 ms after the trigger | PASS |
| Client terminates with SIGKILL, callback held | Service exit with SIGKILL observed about 1.2 ms after the trigger | PASS |

The times are differences between the trigger and the observer's receipt of the kernel event,
not precise measurements of macOS's internal latency. The FAIL concerns the two-second
window, not indefinite survival. During the cleanup of the cancel case, the client's exit
produced the service's exit with SIGKILL; this later event is
recorded separately and does not turn the case into a PASS. For all four cases
the client and service exits are confirmed. No exit depends on SIGALRM.

## Reliability and limits

Host and service are fixed C fixtures, signed with the Apple Development identity
`4A857D842A5406C2D3071776FDE7B27B3098FE63`, Hardened Runtime; the service has only
the App Sandbox entitlement. The signature checks succeeded. The responses
are authenticated with a signing requirement and `SecCodeCreateWithXPCMessage`.

The runner registers `EVFILT_PROC` with a receipt, `NOTE_EXIT` and `NOTE_EXITSTATUS`;
a second authenticated message confirms PID, incarnation UUID and deadline
after the registration. It also confirms the client's action before classifying.
It sends no signals to the service's PID or to process groups. It keeps its own
direct child for the client's cleanup. The service has an eight-second alarm
from main; an exit caused by that alarm, by an error or by a crash of the fixture
is not accepted as a successful termination.

The test covers exclusively an Application service included in the bundle, after main
and after authentication. It does not prove coverage before main, the execution of external
addons, isolation between publishers, protection of outgoing messages or a production
adapter. A single cycle on this version of macOS does not qualify all supported
versions. The non-cooperative callback belongs to the controlled fixture.

## What changes for the solution

XPC is a concrete lead for tying the service to the lifetime of its client after launch:
even the forced death of the client made the observed service terminate.
`xpc_connection_cancel` alone, however, does not satisfy the required stop while that client is alive.

One possible architecture to evaluate is an intermediate client dedicated to each addon:
terminating that client could stop its service while leaving Cascade open.
It is not an already proven solution: it would also be necessary to guarantee the intermediary's lifetime
from its creation, avoiding moving the same problem onto it, and to qualify
discovery, signing and installation of external addons. The present experiment ends
here; it does not introduce this further layer, nor does it admit the launcher.

## Evidence and checks

- [Raw results](evidence/2026-09-24-xpc-lifetime/results.json), including the separate cleanup.
- [Build manifest](evidence/2026-09-24-xpc-lifetime/build.json), commands and source/binary hashes.
- [Build log](evidence/2026-09-24-xpc-lifetime/build.log), signature, entitlements, system and compiler.
- [Fixture and reproduction](../../../Prototypes/AddonPlatform/XPCLifetime/README.md).

Seven verifier tests pass. Independent review completed before the
test: fixed the false positive on service crash/error, the missing confirmation
of the action and the handling of the expected invalidation. The first native run
(`probe-kf1be9u0`) stopped in the runner because `KQ_EV_RECEIPT` is absent from the
Python module; it produces no verdict. Fixed by using `EV_RECEIPT = 0x0040` from the public header
`sys/event.h`, without changing the criterion. The new build `probe-czbrf_sw` ran
all the cases and the runner returned 1 for the valid negative result of cancel.

The initial build attempts had revealed two fixture errors, fixed before
the test: the `xpc_main` callback and the syntax of the `codesign -R` requirement.
No product suite rerun: this delivery adds only the prototype and
the evidence. The gate `scripts/test-addon-managed-death.sh` remains unchanged,
SHA-256 `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Ordinary relaunch of Cascade completed and verified: previous PID 24641, new
PID 26301, executable of the existing CascadeDevelopment build reached through
`/Applications/Cascade.app`. No app recompilation needed for the
separate prototype. [Relaunch evidence](evidence/2026-09-24-xpc-lifetime/cascade-restart.json).
