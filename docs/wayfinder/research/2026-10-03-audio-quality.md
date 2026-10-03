# Audio mixer: signal integrity and realtime risks

Research date: 3 October 2026. Branch: `cava/audio`.
Status: source investigation and design requirements; no audio engine has been implemented
or physically qualified in this work.

## Intent and evidence limits

The user selected the mixer shown in the supplied Vorssaint video, with per-app
volume, mute and one output per app. The user reports that FineTune sometimes loses
attenuation after standby, while Vorssaint retains it on their machine. That report
is an acceptance scenario, not a reproduced diagnosis of either application.

Pinned references:

- FineTune: `2285279d36d3f8115c1c2d4aecd904f1bdf96a51`.
- Vorssaint: `aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958`.
- Local Apple SDK: Xcode-beta, CoreAudio `CATapDescription.h` and `AudioHardware.h`.
- Supplied recording: `Screen Recording 2026-10-03 at 2.28.41 PM.mov`, 30.416896 seconds.
  Its sampled frames show master volume, an app area, and inline device/input options;
  they do not show a populated per-app mixer or prove its audio behavior.

No upstream implementation, translations, tests or assets are copied into Cascade.

## Observed source behavior

FineTune seeds the current gain before starting I/O, so a simple claim that every
new tap starts at unity is contradicted by the inspected source.
[Activation, lines 579–703](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L579-L703).

Its peak scan examines the first sample of each interleaved frame. A silence gate
uses that peak to rearm and fade subsequent output. Right-only signals therefore
need targeted qualification. The public report of this symptom is supporting
evidence, not a reproduction here.
[Callback, lines 1491–1579](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L1491-L1579),
[gate, lines 1274–1315](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L1274-L1315),
[issue 429](https://github.com/ronitsingh10/FineTune/issues/429).

FineTune invokes its soft limiter after rendering each output buffer. That limiter
changes finite samples whose magnitude exceeds 0.95. This is deliberate peak
processing, not transparent attenuation.
[Render, lines 1449–1472](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L1449-L1472),
[limiter, lines 15–69](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/SoftLimiter.swift#L15-L69).

Vorssaint's matching-format render path uses a vector scalar multiply; other paths
map or fold channels. This is a useful separation of concerns, not proof that all
Vorssaint configurations preserve the source format.
[MixerRender, lines 83–151](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/MixerRender.swift#L83-L151).

## Platform contracts

A process tap can intercept one process or a group and supply an aggregate device.
Apple distinguishes capture from playback muting: `mutedWhenTapped` suppresses the
original only while another client reads the tap; `muted` suppresses the original
while that tap exists. Neither establishes an application-controlled barrier
before a tap exists or after HAL invalidates it.
[Apple tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps),
[mute behavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior).

The SDK's stream-specific tap initializer promises the selected stream's format.
`kAudioTapPropertyFormat` describes the actual tap data. `tapautostart` can defer an
aggregate start until tapped audio arrives, so start completion alone is not a
proof of live rendering. Observe actual format, start/stop events and callback
generation; do not invent a sample rate or infer readiness from nonzero samples.
[Apple aggregate property](https://developer.apple.com/documentation/coreaudio/kaudioaggregatedevicetapautostartkey),
[tap format](https://developer.apple.com/documentation/coreaudio/kaudiotappropertyformat).

Apple's realtime guidance excludes indeterminate work such as allocation, locks
and filesystem/network access. Cascade should apply this discipline to its HAL
callback without adding a driver or parallel realtime thread.
[Apple realtime callback guidance](https://developer.apple.com/documentation/audiodriverkit/creating-an-audio-device-driver).

## Proposed minimum signal path

Use a small C/C++ HAL callback behind a Swift lifecycle service. Parse formats,
resolve identities, allocate buffers and build channel maps off the realtime thread.
The callback receives a stable context; it reads one coherent, lock-free command
snapshot, applies gain, initializes every writable output byte, and returns.
Verify that the chosen atomic representation is lock-free on both supported CPU
architectures; do not introduce a spin loop or hidden fallback lock.

- At unity gain, unmuted and following the native route, detach processing and
  restore the native path after a qualified handoff. Test for duplication and gaps.
- For steady attenuation, process native Float32 or Float64 PCM without narrowing
  Float64 first. Output must match a correctly rounded scalar multiply. No limiter,
  compressor, silence gate, automatic loudness or normalization is present.
- Changes to volume use a finite sample-count ramp, initially 5 ms, shared by all
  channels and advanced once per frame. A second control change starts at the
  current gain. First activation starts with the restored gain, never unity.
- Mute writes exact zeros after its finite ramp. Subthreshold content and a silent
  left channel never count as device failure or justify suppressing the right.
- Prefer a qualified same-format, same-clock path. When routing requires different
  sample rates or clocks, use platform conversion only where necessary and measure
  its latency and drift. Do not force a shared device's rate or buffer size.
- Channel maps are explicit. Do not silently fold multichannel content to stereo,
  pair the wrong AudioBufferList planes, or advance a ramp independently per plane.
- Unsupported or inconsistent formats stop that controlled route with a visible
  error. Never reinterpret integer PCM as floating point or manufacture 48 kHz.

The callback context remains alive until I/O is stopped and callbacks are proven
quiescent. Generation checks reject old commands and events; they do not make
use-after-free safe. Reclamation has a separate ownership protocol.

## Failure and qualification matrix

| Risk | Required behavior | Evidence to collect |
| --- | --- | --- |
| Sleep/wake or coreaudiod restart | Rebuild ephemeral objects; retain requested gain/mute/route | Captured gain and first post-recovery samples; lifecycle generations |
| Helper process replacement | Reconcile all current audio process IDs with a stable app identity | Browser process replacement and app restart tests |
| PID reuse or duplicate app instances | Never apply an old binding to an unrelated process | Identity and process-start token tests |
| Output disappears or returns | Preserve preferred UID and report actual fallback separately | USB/Bluetooth disconnect while playing |
| 44.1/48/96 kHz or Bluetooth profile change | Revalidate format and clock; bounded reconstruction | Impulse latency, waveform and drift before/after |
| Right-only, near-silence, mono, planar stereo | Preserve valid channels and tiny finite signals | Synthetic PCM corpus and real playback |
| Full-scale peaks | No additional nonlinear processing for gain at most one | Null/error comparison against scalar multiply |
| Missing data, oversized buffer, NaN/Inf | Initialize output, isolate invalid data, count failure without logging in callback | Bounds tests, canaries, sanitizer runs outside timing tests |
| Two sliders/displays update together | Apply newest accepted revision coherently | Concurrent command ordering and stale-event tests |
| Cascade/provider disable or crash | Explicitly end managed control; clean private objects | Process teardown and restart ownership tests |
| Long silence or legitimate pause | No amplitude watchdog or perpetual recovery loop | Pause/resume and continuous digital-silence tests |
| Multiple controlled apps | No self-capture feedback; at most one active owner per app | Two/ten-app tests and duplicate tap detection |

There is no measured CPU, RAM, latency, distortion or recovery result yet.
Bluetooth latency reported in FineTune issue 424 is a user observation, not a
Cascade budget or a verified explanation of conversion behavior.
[Issue 424](https://github.com/ronitsingh10/FineTune/issues/424).

## Required qualification boundary

Promise preservation of requested settings and seeded gain for every callback
owned by Cascade. Do not promise suppression of every uncontrolled hardware sample
through a missing/invalid tap, an application crash or a HAL reset. Measure these
gaps explicitly. A strict all-samples guarantee would require investigating a
different system integration, beyond this driverless widget scope.

Prefer bounded quiet recovery while a valid tap remains owned; avoid publishing
an applied-volume success for a failed or unread route. Keep a visible recovery or
error state and provide an explicit action to return the app to native audio.
