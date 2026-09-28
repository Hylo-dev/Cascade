# Addon broker: ordinary replacement, recovery and isolation

25 September 2026. macOS 27 beta 26A5425a, arm64, SDK 27. Continuation of the
request to make the native part of the addon system usable. No addon code
integrated into the GUI; production launcher still not admitted.

## Practical result

The fixture now has two distinct proven paths: cooperative exit of the
provider alone for normal short work; exit of the broker to recover a
blocked provider. In both the host stays alive and the new provider starts only
after the kernel exit of the previous one. The second path has a much higher
relaunch cost, so it is not suitable to be used at the end of every request.

| Final case | Observation | Outcome |
| --- | --- | --- |
| Blocked provider, broker stop, new chain in the same host | Old broker/provider exited, both UUIDs new, new chain then exited, host responsive | PASS |
| Two simultaneous hosts of the same addon | Distinct brokers and providers; stopping the first chain leaves the second with unchanged identity and an authenticated response | PASS |
| Two successive cooperative providers in the same broker | Two status 0 exits, different provider UUID, same broker reconfirmed alive after the second exit | PASS |
| Regression: broker stop with host alive | Previously blocked provider exits, host responds | PASS |
| Regression: normal host exit | Broker and provider exit before the guards | PASS |
| Regression: host crash | Broker and provider exit before the guards | PASS |

All final cleanups are complete. No PASS derives from a SIGALRM guard.
In the cooperative replacement, the second startup request receives the first authenticated
response after **65.6 ms**. In the full recovery, after **10.148 s**. These are single
observations of the final build, not percentiles, latency bounds or CPU/RAM measurements.

## Relaunch delay and preserved attempts

The first run (`probe-td97j8xd`) shows that the command to recreate
the connection was missing; it ends UNKNOWN, with complete cleanup of the known chain.
The command was added to the fixture, discarding the late errors of the old
connection after the replacement.

The second (`probe-hae_1plo`) waits only two seconds for the new handshake:
the request stays pending and the test ends UNKNOWN. The second chain is neither
authenticated nor registered, so `cleanupComplete=false` remains preserved: it is not
proof that a process was left orphaned and it is not proof of its exit.
The local log shows the removal of the half-active service when the host terminates.

A diagnostic window of 15 seconds, for a single request without resend, then allows
the relaunch. The build `probe-q3h1sesl` completes the first two scenarios; the final build
`probe-b76biql4` repeats them and adds the cooperative path. The delay near
10 seconds is consistent with the relaunch regulation documented for launchd, but the
captured log does not explicitly identify the cause as throttling. The general
documentation must not be assumed to be an SLA of the XPC service on this OS.
[Apple launchd manual](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5),
[XPC service management](https://developer.apple.com/documentation/xpc).

The stop windows remain 8 s with a margin of 0.5 s from the guards: provider
25 s, broker 35 s and root 45 s. `Output.expect` keeps 2 s as the default for all
existing callers; only the first handshake of the subsequent chains uses 15 s.

## Attribution and limits

The signatures remain bound to the fixture certificate and to the exact
identifiers. Root and broker verify nonce, peer PID and expected path. A second
response of the same incarnation follows the kqueue registration with receipt.
The causal exits are copied before the cleanup, which does not change the verdict.

In the cooperative case, `finish-provider` only confirms that the request was sent:
it is the kernel status 0 event that authorizes `release` and the new startup. In the recovery,
the exits of both participants are needed instead. The new provider must have
a different UUID; changing only the connection is not considered a replacement of the process.
No signals are sent to PIDs discovered by name or path: the only possible cleanup
kill concerns the root child kept by the runner.

The case with two hosts is not equivalent to two different addons in the same host, nor to two
different publishers. It does not close the phase before the first handshake, the pending startup,
the isolation of a production pool, the remote scene or the macOS 14/15/26 matrix.
The research on a [trusted container with late loading](../../wayfinder/research/2026-09-25-trusted-addon-container.md)
does not offer an already qualified solution to these points and does not change the format.

**The result is a working lifecycle path in the fixture, not an addon system
that can be activated in Cascade.** The previous policy still requires the absence
of orphans even before main, including the trusted bootstrap. The already rejected
exception is not proposed again; the gate keeps the same hash and returns exit 78.

## Verification and reproduction

25 Python tests passed: 11 BrokerRecovery, 4 Recovery, 3 Interruption and 7 XPCLifetime.
The added tests were observed failing before the implementation. Independent
review of the relaunch/isolation and then of the new cooperative path: no
P1/P2. The six final native observations use the same verified binaries and inputs.
No sources of the main app changed; CascadeKit was not rerun.

- [Commands and fixtures](../../../Prototypes/AddonPlatform/BrokerRecovery/README.md).
- [Results of the three new cases](evidence/2026-09-25-addon-broker-sessions/final/session-results.json).
- [Three native regressions](evidence/2026-09-25-addon-broker-sessions/final/broker-results.json).
- [Final manifest](evidence/2026-09-25-addon-broker-sessions/final/build.json).
- [First attempt](evidence/2026-09-25-addon-broker-sessions/missing-reconnect/session-results.json).
- [Window too short](evidence/2026-09-25-addon-broker-sessions/startup-window-too-short/session-results.json).
- [First positive relaunch/isolation check](evidence/2026-09-25-addon-broker-sessions/restart-and-isolation/session-results.json).

Every archive preserves sources, runners with verified hashes, manifests, logs, events
and cleanup. The final relaunch of Cascade is recorded separately in `restart.json`.
