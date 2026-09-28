# XPC intermediary for addons: isolated prototype

The fixture measures two independent chains:

```text
XPCBrokerProbe.app
 ├─ BrokerA.xpc → WorkerA.xpc (included in the BrokerA bundle)
 └─ BrokerB.xpc → WorkerB.xpc (included in the BrokerB bundle)
```

The app simulates Cascade. Broker and worker are XPC Application processes with App Sandbox,
Hardened Runtime and an Apple Development signature. It does not run real addons and is not linked
to Cascade. The broker remains trusted and available while the worker holds the callback
in `pause()`. The stop asks the broker to exit; the runner measures whether macOS also terminates
the worker, without sending it signals.

Four cases: stop A, self-SIGKILL A, ordinary app exit, self-SIGKILL app. In the first two
the runner requests a new ping of the same chain B after the measured window.
In the other two both workers hold the callback and all four XPC processes
must exit. Each case uses new incarnations. The window is two seconds;
broker/worker have a twelve-second SIGALRM guard from main, excluded from the PASS results.

The root authenticates the broker, which authenticates and relays the worker's response.
It is a chain of trust between fixed fixtures, not proof of the identity of arbitrary addons.
The runner registers the kernel events after the first message, confirms UUID/PID/deadline
with a second one, and separates measurement from cleanup. It reuses `Output` from the earlier
XPCLifetime test without changing it.

## Reproduction

Requires macOS and Xcode-beta with the signing identity present in `XPCLifetime/run_probe.py`.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/XPCBroker -p 'test_*.py'
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --build-only nested
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --run /path/printed
```

The runner verifies the hashes of sources and binaries before launch. Exit 0: all PASS;
1: valid negative result; 2: incomplete evidence. The `siblings` packaging variant
is prepared as an alternative to nested discovery, but it has been neither run nor qualified.
Do not rerun the same products folder if you want to keep the previous logs.

`SignalCheck.c` is the separate reproducer of the race between `raise(SIGKILL)` and `_exit`
on a dispatch queue: it compares `immediate-exit` and `wait-signal`, with a two-second guard.

[Report and results](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker.md):
four PASS after the correction of the crash simulation. No launcher admission,
no proof before main or on external packages.

## Blocked control callback

The [follow-up test](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker-blocked.md)
adds `hold-both`, which holds both the worker's callback and the broker's.

```sh
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --build-only nested
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --run-blocked /path/first/build
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --build-only nested
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --run-control /path/second/build
```

The first cycle records two valid FAILs (stop and cancel) and one PASS (app death), so it
returns 1. The second cycle authenticates a second channel to the same broker incarnation
before the stop: PASS. It does not prove recovery from the whole process being blocked.

## All command channels blocked

`--run-frozen PRODUCTS` runs stop on the second channel, normal root exit and root crash
after `hold-all`. The first fails, the others pass in the recorded tests.
It is not a suspension of the whole process: listener/responses/signals remain active.
The first case's cleanup also observes a delay of about five seconds for A;
do not use the host-normal PASS as a latency promise for every sequence.
[Results and limits](../../../docs/superpowers/verification/2026-09-24-addon-xpc-frontier.md).
