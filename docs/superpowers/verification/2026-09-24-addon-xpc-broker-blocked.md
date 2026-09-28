# Intermediary with a blocked callback: 24 September 2026

**The stop on the blocked channel fails; a second channel to the same broker
succeeds in stopping broker and worker, leaving the app and chain B active.**

This continuation of the [intermediary test](2026-09-24-addon-xpc-broker.md)
examines the last limit presented to the user, at the request "test that one too".
The measured scope is the blocked serial control callback, not the whole suspended
process. It adds no evidence before main or on external addon packages.

## Design and results

The fixture keeps the two app → broker → worker chains, nested services, signing,
Hardened Runtime and sandbox. `hold-both` forwards `hold` to the worker and holds the broker's
control callback in `pause()`. Another queue forwards the worker's authenticated
response. The runner confirms the identities after registering the kernel events.
The blocking loop has no cooperative exit; other threads remain available.

| Test | Result within the two seconds | Outcome |
| --- | --- | --- |
| Stop A on the blocked channel | No A exit; app alive and the same chain B responds | FAIL |
| Cancellation of channel A | No A exit; app alive and the same chain B responds | FAIL |
| SIGKILL of the app with A blocked | Both brokers and workers exit with SIGKILL | PASS |
| Stop A through a second channel | Broker A exits 0; worker A exits SIGKILL; app alive and the same chain B responds | PASS |

First three cases: build `nested-5mlrp477`; fourth: build `nested-dixw0aig`. Each case
uses new processes. Environment macOS 27.0 (26A5425a), arm64, SDK 27.0, clang 21.0.0.
One run per case, without qualifying all supported macOS versions.

In the fourth case the runner opens a new connection with the same service
identifier, authenticates the broker's response and compares PID, UUID and deadline with
the incarnation already observed. Only then does it send `exit` on the new channel. The identity
response does not pass through the blocked worker. The broker exits about 0.69 ms after the trigger,
the worker about 1.41 ms after the trigger: times at which the observer received the events,
not guaranteed time bounds of the platform.

## Reliability and limits

The measurement uses kqueue with a receipt, `NOTE_EXIT` and `NOTE_EXITSTATUS`; it requires a second
confirmation of the incarnations, the client's action and a response from the same chain B.
The broker's messages are authenticated; the trusted broker authenticates the worker's.
No service PIDs or groups are signaled. The SIGALRM guards fire twelve
seconds after main; any exit they cause does not count as PASS.

All four services were registered and their final exit is confirmed
in each case. In the two FAILs, closing the app during cleanup also makes A exit;
the later exits remain separate and do not change the negative verdict.
No exit required SIGALRM.

Separating control from the channel that can block is a proven solution for
this specific class of stall. It still requires a queue available to execute
the stop in the trusted broker. It does not prove selective recovery from suspension of the whole
process, exhaustion of all threads or a block shared by the control path as well.
The test uses fixed trusted processes, not arbitrary addons.

The launcher remains not admitted: launch before main, a public path for external
packages and a full guarantee of stopping the broker remain open. Policy, adapter,
Cascade's entitlements and the C0d gate are unchanged.

## Evidence and verification

- [Three scenarios with a blocked callback](evidence/2026-09-24-xpc-broker-blocked/blocked/results.json).
- [Recovery with a second channel](evidence/2026-09-24-xpc-broker-blocked/control/results.json).
- [First cycle manifest](evidence/2026-09-24-xpc-broker-blocked/blocked/build.json) and [second cycle](evidence/2026-09-24-xpc-broker-blocked/control/build.json).
- [First cycle build](evidence/2026-09-24-xpc-broker-blocked/blocked/build.log) and [second cycle](evidence/2026-09-24-xpc-broker-blocked/control/build.log).
- [Fixture and commands](../../../Prototypes/AddonPlatform/XPCBroker/README.md).

Both folders also preserve the sources corresponding to the manifests.
Nine classifier tests and seven tests of the reused earlier verifier pass.
The new tests were observed failing before the implementation. The independent
review found a false negative in the cancellation criterion, now corrected:
a possible SIGKILL/SIGTERM exit of the broker in that case is now accepted.
The same-incarnation check on the second channel was also reviewed
before the run.

No test or build of the product app run: changes limited to the separate prototype.
SHA-256 of the C0d gate unchanged:
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Cascade relaunched ordinarily and verified: previous PID 28002, new PID 29180,
executable of the existing CascadeDevelopment build reached through `/Applications/Cascade.app`.
[Evidence](evidence/2026-09-24-xpc-broker-blocked/cascade-restart.json).
