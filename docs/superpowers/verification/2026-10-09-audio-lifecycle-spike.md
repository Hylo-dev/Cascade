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

Confirmed by the human's second full run (the conclusive A/B run below): public
aggregate present after SIGKILL, `destroyStatus: 0` on cleanup.

```json
{"leftovers":{"cascade.multi-output.probe-2A0F0458-6011-4B85-B1B8-A286BC895B9A":{"present":true}},"uids":{"cascade.multi-output.probe-2A0F0458-6011-4B85-B1B8-A286BC895B9A":{"inDevices":true,"inTapList":false}}}
```

## A and B: what a killed process leaves behind of a private tap

Private taps and private aggregates are visible only to the process that created
them, so `inspect` from a fresh process reports `inDevices: false, inTapList:
false` whether or not they survived. It cannot answer A. Both A and B are read
from what is heard, in three steps of `run-probe.sh`: (a) baseline, tone audible
natively; (b) tapped, before the kill; (c) after `kill -9`. The IOProc reads the
tap (`mutedWhenTapped` mutes only while a client reads it) and writes silence,
so the reading rule is:

- (b) silent, (c) audible: the tap, its `mutedWhenTapped` and the aggregate died
  with the process.
- (b) silent, (c) silent: the muting tap outlived the process.
- (b) audible: the tap never muted, the run is invalid.

### Run 1: invalid

(a) y, (b) y, (c) y, answered by the human. Invalid for two reasons. First,
`creator output:` was still empty when (b) was asked: the tap's JSON arrived
later, probably while macOS showed the System Audio Recording prompt, so the tap
may not have been active at (b). Second, that version of the IOProc copied the
tap to the output, so "audible at (b)" could not prove the tap was muting. Fixed
by an IOProc that writes zeros and by waiting for the JSON line before (b).

### Run 2: conclusive

Human answers: (a) baseline audible = y, (b) tapped before the kill = n
(silent), (c) after the kill = y, audible after destroy = y. (b) silent proves
the tap was muting; (c) audible means it stopped when its creator died.

```
inspect (private, supporting): {"leftovers":{},"uids":{"Cascade-probe-CAB3527E-EA54-4EDA-B811-0A23370361D4":{"inDevices":false,"inTapList":false},"D0C704AC-75D3-41AC-91B1-5844A45B8005":{"inDevices":false,"inTapList":false}}}
C: {"leftovers":{"cascade.multi-output.probe-2A0F0458-6011-4B85-B1B8-A286BC895B9A":{"present":true}},"uids":{"cascade.multi-output.probe-2A0F0458-6011-4B85-B1B8-A286BC895B9A":{"inDevices":true,"inTapList":false}}}
Cleanup: {"leftovers":{},"uids":{"Cascade-probe-CAB3527E-EA54-4EDA-B811-0A23370361D4":{"inDevices":false,"inTapList":false},"cascade.multi-output.probe-2A0F0458-6011-4B85-B1B8-A286BC895B9A":{"destroyStatus":0,"inDevices":true,"inTapList":false},"D0C704AC-75D3-41AC-91B1-5844A45B8005":{"inDevices":false,"inTapList":false}}}
```

The private-UID `inspect` is supporting only: absent either way.

### A. Does a private aggregate holding a process tap disappear after SIGKILL?

Yes. The private aggregate and its process tap die with their creator on
SIGKILL (the muting stopped, (c) audible). No sweep is needed for private
objects.

### B. Does the tapped app stay muted (`mutedWhenTapped`) after that kill?

No. The tapped app is audible again right after the kill. A crashed Cascade does
not leave an app muted.

## How to run A and B

```bash
Prototypes/AudioLifecycleProbe/run-probe.sh
```

Run it from a terminal that has the System Audio Recording permission, with
someone listening. The script waits up to 30 s for `create-private` to report a
running tap before it asks about (b), so the permission prompt can be answered.
It prints a block to paste under A, B and C: the audibility answers (a), (b),
(c) with a `Reading:` line, plus `inspect` output labelled as supporting and not
conclusive for private objects.

## Leftovers

After the run, `inspect` with no arguments reported
`{"leftovers":{},"uids":{}}`: no `cascade.multi-output.probe-*` or
`Cascade-probe-*` device remains.
