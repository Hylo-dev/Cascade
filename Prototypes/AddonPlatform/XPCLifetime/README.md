# Isolated test of an XPC service's lifetime

Fixed fixture, separate from Cascade. It does not load addons and does not enable the launcher.
It measures four cases: cooperative exit, cancellation of the connection with the client alive,
ordinary client exit, and client death via SIGKILL.

The Application service is embedded in the client's bundle, signed with Hardened Runtime
and App Sandbox. The client verifies received messages through a signing requirement and
`SecCodeCreateWithXPCMessage`. The protocol contains only synthetic data.
The noncooperative case holds the callback in `pause()`, without active CPU consumption.

The observer registers `EVFILT_PROC/NOTE_EXIT/NOTE_EXITSTATUS` after a first authenticated
message and confirms the incarnation with a second message. It sends no signals to the
service's PID. The measured window lasts two seconds; an autonomous alarm in the service
limits the experiment to eight seconds from main. This alarm is only a fixture
guard: it proves no guarantee before main or with arbitrary addon code.
An exit during cleanup remains separate from the measured result.

## Local reproduction

Requires macOS, Xcode-beta and the Apple Development identity specified in `run_probe.py`.
Builds are created in a unique folder under DerivedData, without registering a
LaunchAgent or modifying `/Applications/Cascade.app`.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/XPCLifetime -p 'test_*.py'
python3 Prototypes/AddonPlatform/XPCLifetime/run_probe.py --build-only
python3 Prototypes/AddonPlatform/XPCLifetime/run_probe.py --run /path/products/printed
```

Runner codes: 0 all PASS; 1 at least one valid negative result; 2 incomplete/UNKNOWN
observation or unconfirmed cleanup. A FAIL is not proof of a general impossibility
of XPC. All results retain `launcherAdmitted: false`.

The [first measurement](../../../docs/superpowers/verification/2026-09-24-addon-xpc-lifetime.md)
records three PASS and one FAIL: cancellation of the connection did not stop the
service during the observed window; the subsequent client exit stopped it.
