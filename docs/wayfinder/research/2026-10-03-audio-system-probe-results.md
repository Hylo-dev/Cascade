# Audio system probe results

Date: 3 October 2026. Branch: `cava/audio`. Product code was not changed.

The reproducible command is
`python3 Prototypes/AudioSystemProbe/run-probe.py`. The runner builds with
Xcode-beta, treats compiler warnings as errors and bounds native execution to
12 seconds. The preserved JSON is
[`evidence/2026-10-03-audio-system-probe.json`](evidence/2026-10-03-audio-system-probe.json).

## Runtime observations

The first sandboxed run returned `noErr` with default output and own process
objects both `kAudioObjectUnknown` (0). It performed no stream/control experiment.
This is incomplete HAL visibility, not evidence that the machine has no audio
device. The subsequent authorized run outside the execution sandbox exercised
the real output. The initial real runs observed 21 AudioQueue callback returns
across playback and disposal. The checked final run separates those phases:

| Observation | Result |
| --- | --- |
| OS / architecture | macOS 27.0, build 26A5425a / arm64 |
| Queue creation, preparation, start, disposal | `noErr` (0) each |
| Callback counter | Lock-free on this host; 21 total, 18 active, 3 returned during retirement |
| Active re-enqueue / retirement status | 0 / 0 |
| Own HAL process | Identified; output-running UInt32 = 1 |
| `appm` on physical output | Present, writable, UInt32, initial value 0 |
| Own-process mute write/readback | 0 → 1 → 0; each setter returned 0 |
| Exact initial mute restoration | Setter returned 0; final value equals initial 0 |
| `appm` on own Process object, global scope | Absent |
| System-object `pmut` | Present, writable UInt32 = 1; read only |
| MediaExperience framework load | Succeeded |
| Private symbol addresses | All 18 tested names resolved |
| Private functions invoked / setters targeting another process | 0 / 0 |

The JSON object IDs are ephemeral, process-local observations, not device routing
identities. They differed between runs. No device UID or app identity is inferred
from them. The underlying public property is explicitly caller-scoped in the
inspected SDK; an absent property on one scope is not an exhaustive search of
unknown properties. See the [candidate investigation](2026-10-03-audio-private-api-candidates.md).

## Reproduced teardown defect and durable rule

A stricter callback-status assertion reproduced this probe defect twice:

```text
callbackEnqueueStatus: -66632
AssertionError: Queue callback could not return its buffer
```

`-66632` is `kAudioQueueErr_EnqueueDuringReset`. The initial callback re-enqueued
every returned buffer, including the pending buffers returned during Dispose.
The SDK explicitly forbids enqueuing during Reset, Stop or Dispose. This was a
probe lifecycle defect, not evidence of a playback defect in FineTune or Cascade.
[AudioQueue error contract, line 156](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AudioToolbox.framework/Versions/A/Headers/AudioQueue.h:156>).

Retirement is now published before synchronous disposal. Retiring callbacks
return without enqueuing; a previously active callback's late queue result is
recorded separately if retirement raced it. Context remains alive until Dispose
returns. The final check passed with 18 active returns, 3 retirement returns and
zero queue errors. The SDK states callbacks end after Dispose returns when it is
called outside a callback/listener, as here.
[Disposal lifetime contract, line 1022](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AudioToolbox.framework/Versions/A/Headers/AudioQueue.h:1022>).

Rule: publish retirement before teardown, distinguish active health from expected
shutdown activity, and reclaim context only at the API's actual quiescence point.
The original approach produced false recovery failures and invalid re-enqueue
attempts; the replacement adds one lock-free phase flag and no timers/allocations
in the callback. This does not establish the distinct AudioDeviceIOProc lifetime
contract; that backend must qualify its own stop/destroy boundary.

## What the experiment does not establish

All queued sample bytes were zero. Readback therefore proves control plumbing
only, not acoustic mute, gain accuracy, phase, latency or independent enforcement.
The probe does not register a property-change listener; asynchronous notification
delivery remains a separate qualification step even though immediate readback
matched in this run. It did not change another application's audio, capture any
audio, request input permission, alter hardware master volume or reset coreaudiod.

No private signature was guessed or called. `FigRoutingContext`,
`FigVolumeController` and `MXSession` symbol visibility supplies no evidence of
cross-process permission/effect, stable ABI or sleep/wake retention. The verified
`AudioDeviceDuck` declaration has no PID and could affect shared device audio;
it was inventoried but not invoked. There is no newly qualified per-app backend.

The real test used the beta OS/SDK installed here. macOS 15, x86_64, device/profile
variants and 50 sleep/wake cycles remain untested. Queue callbacks and zero PCM
are not product IOProc performance measurements. No CPU/RAM/latency budget has
been claimed as passed.

## Addon integration prerequisite

`AddonProvider`, `AddonContext.services` and `ServiceBroker` are the existing
integration contracts. Audio will use those contracts, manifest requirements,
explicit permissions and resource accounting. The native activation test still
returns **78** with:

```text
C0d native execution is on HOLD: the pre-trace parent-selection safety gate is unresolved.
```

Private API research does not resolve that launcher issue. Service/kernel,
provider and presentation tests can proceed independently; production external
activation requires its separate qualification. No in-host Audio fallback is
authorized by this work.
