# Audio lifecycle spike: what a killed process leaves behind

Probe: `Prototypes/AudioLifecycleProbe/` (throwaway, not linked into Cascade).
Part B's plan reads the three answers below.

## Environment

- macOS: 27.0 (build 26A5425a), `sw_vers`
- Hardware: `Mac14,2` (`sysctl hw.model`)
- Default output device: Bellsprouts (Bluetooth, 2 channels, 48000 Hz)
- Toolchain: Xcode-beta, `swiftc -O`

## C. Does a public aggregate survive its creator's SIGKILL?

Measured, no listening needed. `create-public` made
`cascade.multi-output.probe-802A673A-79DA-4FA0-BD82-1A3F7A042FC3`, the process
was `kill -9`ed, and a fresh `inspect` ran 2 s later:

```json
{"leftovers":{"cascade.multi-output.probe-802A673A-79DA-4FA0-BD82-1A3F7A042FC3":{"present":true}},"uids":{"cascade.multi-output.probe-802A673A-79DA-4FA0-BD82-1A3F7A042FC3":{"inDevices":true,"inTapList":false}}}
```

Observed: yes, the public aggregate is still in `kAudioHardwarePropertyDevices`
after its creator was SIGKILLed. It stays until someone destroys it:
`inspect --destroy` returned `destroyStatus: 0`, and a following `inspect`
reported `inDevices: false`. So a public aggregate leaks across a Cascade crash
and needs a startup sweep of the `cascade.multi-output.*` prefix.

## A. Does a private aggregate holding a process tap disappear after SIGKILL?

pending: run by the human partner with `Prototypes/AudioLifecycleProbe/run-probe.sh`

## B. Does the tapped app stay muted (`mutedWhenTapped`) after that kill?

pending: run by the human partner with `Prototypes/AudioLifecycleProbe/run-probe.sh`

## How to run A and B

```bash
Prototypes/AudioLifecycleProbe/run-probe.sh
```

Run it from a terminal that has the System Audio Recording permission, with
someone listening. It prints a block to paste under A, B and C. Only the
`create-private` path needs that permission and the listener; this session did
not run it, so the permission result for `create-private` is not yet known (the
only run was against pid 1, which fails earlier with
`{"error":"no process object for pid 1","osStatus":0}`).

## Leftovers

After the run, `inspect` with no arguments reported
`{"leftovers":{},"uids":{}}`: no `cascade.multi-output.probe-*` or
`Cascade-probe-*` device remains.
