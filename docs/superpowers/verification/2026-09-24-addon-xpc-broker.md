# Dedicated XPC intermediary: 24 September 2026

**The nested XPC chain works in the four measured scenarios. The launcher remains not admitted.**
The user authorized "explore and run tests down this path", referring to a dedicated intermediary
to be terminated in order to stop the addon while Cascade stays open.

## Tested design

A small test app hosts two services, BrokerA and BrokerB. Each broker includes
its own worker in its own `Contents/XPCServices` and is the only client of that worker.
The broker is also an XPC Application service, rather than a process launched directly
with spawn. Nested discovery worked. The five binaries have Apple Development signing
and Hardened Runtime; the four services have only App Sandbox.

The app simulates Cascade without modifying it. A and B have distinct bundle identifiers
fixed at compile time; every scenario creates new processes. The worker holds the callback
in `pause()`, while the broker keeps handling the control commands.

The stop is a request to the trusted broker to execute `_exit(0)`. The forced-death variant
asks the broker to signal itself with SIGKILL. The observer does not signal service
PIDs, does not terminate groups and does not depend on a tracing attach.

## Native outcome

Final build `nested-pu8j8qxj`, macOS 27.0 (26A5425a), arm64, SDK 27.0, clang 21.0.0.
One final complete run, with an observation window of two seconds per case:

| Scenario | Kernel result | Isolation | Outcome |
| --- | --- | --- | --- |
| Stop A | Broker A exits 0; worker A exits SIGKILL, observed about 1.40 ms after the trigger | App alive, the same chain B responds after the window | PASS |
| SIGKILL of broker A | Broker A and worker A exit SIGKILL; worker observed about 1.40 ms after the trigger | App alive, the same chain B responds after the window | PASS |
| Ordinary app exit | Both brokers and both workers exit SIGKILL, observed within about 1.95 ms | App exits 0 | PASS |
| SIGKILL of the app | Both brokers and both workers exit SIGKILL, observed within about 2.31 ms | App exits SIGKILL | PASS |

The times indicate receipt of the kernel event relative to the trigger, not the precise
internal latency nor a timing guarantee from macOS. In the app-death cases both
workers hold the callback. In the A cases, B stays responsive: it is not just a PID
still present, because the ping confirms the same incarnation of broker and worker.

The subsequent cleanup terminates the test client and separately records the exit
of chain B. All known processes exited; the four services were
registered and observed in each case. No PASS depends on the SIGALRM guard.

## How wrong conclusions are avoided

The broker's messages are verified with a code-signing requirement and `SecCodeCreateWithXPCMessage`.
The broker verifies the worker in the same way before reporting its identity: the root
trusts the fixed broker; it does not attribute the worker's direct identity to the forwarded message.
Only synthetic data are exchanged. This does not qualify the authentication or the
protection of outgoing messages of the future addon protocol.

The observer uses `EVFILT_PROC`, a registration receipt, `NOTE_EXIT` and
`NOTE_EXITSTATUS`. After registration, a second response confirms the same
incarnation. The classifier rejects exits that precede the trigger, fall outside the window,
or come from a fixture error, an unexpected crash or the guard. For the broker crash
it requires precisely SIGKILL. It requires both A processes exited and B still
responsive, or all four exited when the app terminates. The cleanup cannot
convert a negative result into a positive one.

Six tests of the new classifier pass; the seven of the reused earlier verifier
pass. Independent review was carried out before the native test and on the later
correction of the crash simulation. The verifier corrections include
tolerating the expected invalidation of A while waiting for the B ping and rejecting
SIGTERM as a surrogate for the specific SIGKILL simulation of the broker.

## First run and the crash-simulation defect

The first run (`nested-0bc3kcmz`) gave three PASS and broker-crash FAIL: the broker
exited with code 84, not with SIGKILL. The worker still exited SIGKILL, but the
verifier did not promote the case. [Original results](evidence/2026-09-24-xpc-broker/initial/results.json)
and [earlier source](evidence/2026-09-24-xpc-broker/initial/Probe.c) are preserved.

The statement `raise(SIGKILL); _exit(84)` on the dispatch thread introduces a race:
the signal request can return before termination and the fallback can preempt it.
An isolated check observed `raise` return 0 before death by SIGKILL
([initial diagnostics](evidence/2026-09-24-xpc-broker/signal-check.json)). The initial hypothesis
that the signal was simply rejected was not confirmed: the assert of that
diagnostic failed. The errno value after a successful call is not a valid error.

A second [reproducer](../../../Prototypes/AddonPlatform/XPCBroker/SignalCheck.c) compares
immediate exit with waiting for the signal: three exits with code 84 versus three SIGKILL
([data](evidence/2026-09-24-xpc-broker/signal-race.json)). Code 84 alone does not distinguish
a failure of `raise` from the subsequent `_exit`; the two checks together motivate
the correction, without attributing to the first one evidence it does not contain.
The fixture now checks the return of `raise` and, on success, waits for the signal
without preempting it with `_exit`. The autonomous guard remains active. The subsequent
signed run confirms an actual SIGKILL in the broker-crash case; all four cases pass.

## What it demonstrates and what remains open

The new result overcomes the local limit of [connection cancellation](2026-09-24-addon-xpc-lifetime.md):
making a trusted XPC intermediary exit terminated its blocked worker while leaving
the app and the other chain active. When the app dies, the intermediaries also exit in the
observed runs. This is a concrete lead to qualify, not a ready launcher.

Still to be demonstrated:

1. Coverage of launch before main and before the first message. Registration and
   guards of this fixture start after main; they do not prove that window.
2. Public support for the nested packaging and for the lifetime relationship on all
   supported macOS versions. Working on one macOS build is not enough.
3. Installation and isolation of external addons signed by other publishers. Here all
   the bundles and the two identifiers are fixed and signed by the same identity.
4. Stop if it is the trusted broker that becomes unresponsive: the tested stop requires
   the broker to read the command. The blocked worker does not prevent it in this fixture.
5. Admission, limits, revocation and transport consistent with the product runtime contract.

The next useful investigation is to qualify the lifecycle of the broker and of the nested
service, including launch, together with the supported path for external packages.
There is no need to repeat the channel cancellation alone, which already proved insufficient.

## Sources and reproducibility

The [Apple XPC guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
describes services managed by launchd and placed in the app bundle. The SDK's public
header/manual `xpcservice.plist(5)` describes the app namespace, included services and
services in frameworks. None of these statements was used as proof that
the whole nested design for external addons is supported.
The [Apple signing rules](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
call for signing from the innermost component outward to the app, and standard locations for code.
The strict/deep verification of the fixture succeeded.

The [Apple implementation of raise](https://github.com/apple-oss-distributions/Libc/blob/main/gen/raise.c)
uses `pthread_kill` with a fallback to `kill(getpid(), sig)` on ENOTSUP. The SDK's public manuals
`raise(3)` and `pthread_kill(2)` document delivery to the thread and the possible ENOTSUP
for threads not created with pthread_create; the diagnosis here also uses the local results.

- [Fixture and commands](../../../Prototypes/AddonPlatform/XPCBroker/README.md).
- [Final results](evidence/2026-09-24-xpc-broker/final/results.json).
- [Manifest: commands, hashes and signing](evidence/2026-09-24-xpc-broker/final/build.json).
- [Final build log](evidence/2026-09-24-xpc-broker/final/build.log).

The siblings variant prepared in the builder was not run, because nested discovery
worked. No product code, Cascade entitlement or adapter
changed. No product suite was rerun for this independent experiment.
C0d gate unchanged: SHA-256 `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Cascade was closed and reopened normally: previous PID 26301, new PID
28002, executable path verified in the existing CascadeDevelopment build
reached through `/Applications/Cascade.app`. No app build was needed for this
separate prototype. [Relaunch evidence](evidence/2026-09-24-xpc-broker/cascade-restart.json).
