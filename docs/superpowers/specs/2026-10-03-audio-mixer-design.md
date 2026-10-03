# Native audio mixer widget

Date: 3 October 2026. Branch: `cava/audio`, based on `988812a`.
Status: architecture approved in chat; this written specification and its new
quality thresholds require review before an implementation plan is written.

## Intent and scope

The user wants an audio mixer integrated into Cascade, visually informed by the
supplied Vorssaint recording and functionally informed by FineTune. The selected
scope is master volume/mute, per-app volume/mute and a single output route per app,
plus output, system-sound output and microphone controls in the options view.

The user approved an Audio tile opening an internal notch mixer through a shared
addon options route, a native Core Audio worker with no polling, and control
sessions that remain effective with the notch closed. The subsequent quality
request makes sleep/wake retention and transparent signal processing central
acceptance requirements.

No equalizer, boost above 100%, headphone correction, simultaneous multi-output,
DDC implementation, AirPlay network engine, global mic hotkey or new audio driver
is included. These exclusions remove entire DSP and clock-management paths.

## Existing contracts and integration

Reuse the plugin publication/action path: `FirstPartyPlugins` manifests,
`PluginSystem`, `PluginSurfaceRouter`, broker grants and revision validation.
`CoreAudioSystemVolume` already observes and changes hardware master volume;
`OutputDeviceAccess` already resolves device UIDs and changes the default output
on a background actor. Reuse their shared operations where applicable rather
than making a second independent controller for the same device state.

The build configuration currently targets macOS 15.0. The style document's older
macOS 14 floor must not be assumed to describe this build; annotate tap availability
at the service boundary and recheck all newer APIs before using them.

The missing common options capability is recorded in `docs/TODO.md` as
`ADDON-NOTCH-OPTIONS`. Complete it as a shared SDK feature; do not call the legacy
contextual-page engine directly from Audio. Audio publishes values and requests
authorized actions; native HAL ownership belongs to a managed service. There is
no Audio-specific route around manifest, permission, admission or broker checks.

Extend only the shared UI primitives required for vertical volume controls,
device selection and a bounded scrolling app strip. Existing buttons, sliders,
stacks and components remain the starting point. This work does not implicitly
complete Caffeinate's separate option UI.

## Presentation

The Audio tile shows an identifiable speaker, current master state and selected
output when its grid span permits. It opens the mixer explicitly; an automatic
audio event must not replace another open page.

The mixer occupies the standard notch footprint. Its header contains Back, the
output selector and an options button. The left column has the master speaker,
vertical fill control and percentage. A divider separates a horizontally
scrolling app strip with one icon, accessible app name, volume control, mute and
route selector per app. Empty state explains that apps appear when producing
audio; recovery, permission and unavailable-device states have distinct copy.

Options replace content inside this page and expose native output, system-sound
output and microphone selection, plus input gain/mute only where the hardware
supports them. Merely listing microphones never opens their input stream, so
opening the mixer does not intentionally switch Bluetooth into a call profile.
Unsupported hardware controls are disabled with their actual capability state.

The shared page lease retains the underlying arrangement, original display and
source publication. Back, Escape, withdrawal, disable, display removal and
termination revoke the lease and restore the underlying page. A second display
may show the same mixer data, but commands carry app/route generation and current
publication revision. A replacement options lease revokes the prior one instead
of stacking unbounded pages.

Use Cascade's native typography, SF Symbols and dark notch surface. Motion is
finite and communicates control changes; respect Reduce Motion/Transparency.
Icons are cached outside realtime code and released with visible-resource leases.

## Separate requested state from applied state

Persistent intent contains stable application identity, gain in [0, 1], mute and
either follow-system or a preferred output UID. It never persists a PID,
AudioObjectID, tap ID or aggregate ID as durable identity.

Runtime bindings contain current process IDs, process-start identity, actual
output UID/format, private tap/aggregate/IOProc ownership and a session generation.
Requested state is authoritative. A device read, lost tap or reconstruction error
must never save a synthetic gain of 1.0 over the user's setting.

The UI distinguishes requested controls from applied, recovering, unavailable
and failed state. It cannot claim an applied volume merely because persistence
contains that percentage. Explicitly identify helper processes using public
identity evidence and cache it; ambiguous mappings stay separate rather than
silently assigning another application's controls.

## Lifecycle and recovery

One serialized lifecycle worker consumes workspace sleep/wake/process events,
HAL process-list and process-running changes, default-device changes, alive,
format, sample-rate and stream changes. Register before taking the baseline;
coalesce events without polling. Reconcile on wake even if the process list looks
unchanged; HAL object identity and render health require separate validation.

Every rebuild creates a new generation. Seed restored gain, mute and route
before I/O can render. Validate device existence and actual PCM format, allocate
and prepare context off the main/realtime threads, then start. Discard obsolete
completions and events. An old callback is harmless only while its context is
still retained; stop/quiescence must precede reclamation.

Recovery attempts are bounded: immediate attempt and event-coalesced one-shot
retries at 100, 300 and 1000 ms, ending in a failed state after 3 seconds of a
continuously available route. These are proposed initial limits, not measurements.
A real topology/configuration change, explicit retry, wake episode or demonstrated
healthy render progress starts a new bounded episode. Repeated identical
notifications do not replenish an exhausted budget. There is no
always-running refresh timer or signal-amplitude watchdog. Digital silence is a
valid signal. First callback readiness and ongoing liveness are separate states.

Events and finite deadlines cannot guarantee detection of a spontaneous stalled
callback with no HAL notification. A proposed amendment, awaiting the user's
choice, adds one shared 1 Hz liveness watchdog only while a controlled session is
expected to render. It reads an atomic callback sequence, never signal energy;
two consecutive checks without progress request bounded recovery. Dormant,
paused, starting and stopped sessions use their own transition state/deadline;
they do not enter steady-state stall recovery. No per-app timers are added,
and the watchdog is removed when no eligible sessions remain. Its measured cost
must fit the same CPU/memory budgets and be reported as at most one additional
scheduled wake per second, with scheduling tolerance.

A supervisor owns deadlines independently of HAL calls. A timed-out waiting task
does not cancel a blocking C call: mark that backend generation failed, stop new
build attempts, and bound live plus retiring contexts to two per app. Keep those
contexts alive until real quiescence; do not free them on timeout or manufacture
progress by adding replacement threads. Further recovery waits for the blocked
operation to finish or for a qualified managed-service restart. Quitting Cascade
must not await such an operation indefinitely on its main thread. Service restart
and process-private object cleanup must pass fault injection before a hard
recovery-duration claim is made; this does not relax the existing addon launcher gate.

When a preferred device disappears, retain its UID and desired gain/mute. Use the
system output as fallback only when the controlled path can be prepared; report
both preferred and actual route. Restore the preferred route when it returns.
Revalidate its format and identity instead of reusing stale numeric IDs.

Closing the notch releases presentation resources, not ongoing attenuation or
routing. Non-unity/muted/rerouted sessions retain explicit service leases while
needed. Unity, unmuted, native-route apps use native bypass after a qualified
handoff. Disabling Audio or quitting Cascade releases all sessions and returns
apps to native audio; stored intent is retained for the next activation.

## Audio integrity and realtime boundary

The signal path is a small C/C++ `AudioDeviceIOProc` with a stable preallocated
context. Swift owns discovery, lifecycle, errors and the SDK boundary. No Swift
ARC, allocation, locks/spins, logging, HAL property reads, dispatch, disk access or
UI publication occurs in the sample callback. Command snapshots are coherent and
use a representation verified lock-free on arm64 and x86_64.

For native PCM, the steady path applies only gain. Preserve Float32/Float64
precision; ramp control changes over a finite 5 ms sample count, advancing once
per frame across all channels. Every new callback starts from restored state.
There is no limiter, compressor, EQ, noise gate or amplitude-dependent fade.
Initialize all writable outputs and validate buffer dimensions against the
prepared format. Invalid format/data cannot be treated as usable PCM.

Use stream-specific format capture when qualified. Validate channel layout and
clock compatibility. Avoid downmixing, integer quantization and conversion in
matching-format routes. Cross-device conversion/drift correction uses native
facilities only where needed and is separately qualified. Never change a shared
device's sample rate or buffer size merely to fit the mixer.

Unity on the untouched native path has no added Cascade DSP; routed unity or
attenuated output is not described as bit-perfect. Bluetooth transport quality
and latency remain physical device properties; the added mixer cost is measured
against the same hardware/profile in bypass.

## Failure policy and platform limit

Preserve the saved setting and prefer bounded quiet recovery while a valid tap is
owned. Compare `muted` with `mutedWhenTapped` in qualification; the former removes
read-dependent native passthrough but can retain silence during recovery. Do not
publish successful attenuation before the managed route is effective. An error
offers an explicit return-to-native action.

An invalidated/nonexistent tap or a crashed owner is outside the callback's
control. Public tap APIs do not establish an absolute no-unattenuated-sample
barrier across those intervals. Qualification must measure uncontrolled gaps;
the UI must not imply otherwise. Do not reduce every application's master volume
to conceal a per-app failure. A stronger all-samples guarantee requires a
separate system-integration design and is outside this driverless scope.

## Proposed release thresholds

These are proposed engineering gates for review, not previously supplied user
budgets and not verified results. Measure before/after on the same driven app,
hardware, route, signal and system-load scenarios; report deltas separately from
the host app's existing baseline.

| Property | Gate |
| --- | --- |
| DSP steady gain | Correctly rounded native scalar multiplication within 1 ULP; no channel swap or nonlinear peak processing |
| Callback ownership | 0 allocations, 0 locks, 0 logging, 0 invalid buffer reads/writes |
| Callback timing | p99.9 below 10% of the hardware buffer interval; no missed render deadlines in the driven test |
| Incremental CPU | Under 1% for one controlled stereo app at 48 kHz; under 3% for ten, notch closed, averaged over 60 s |
| Idle work | 0 periodic mixer timers and 0 render callbacks without eligible controlled sessions; the proposed active-only watchdog is separately counted |
| Incremental private resident memory | At most 16 MiB for one session, 48 MiB for ten; report host and coreaudiod separately |
| Added wired playback latency | At most one measured device-buffer interval plus 2 ms against native bypass |
| Added Bluetooth latency | At most 20 ms against the same profile in native bypass; profile transitions qualify separately |
| Gain after qualified recovery | First controlled buffer uses restored gain/mute; no internally generated unity interval |
| Stable-route recovery | Within 3 seconds of route readiness or a visible failed state from an independent supervisor; no indefinite attempts |

Run offline signal checks at 44.1/48/96/192 kHz, mono/stereo and planar/interleaved
PCM, right-only/left-only, silence, near-silence, impulses, full-scale peaks and
invalid buffers. Compare to a high-precision oracle. Use sanitizer/bounds checks
separately from optimized timing measurements.

Drive the real app through at least 50 sleep/wake cycles, browser helper
replacement, app quit/relaunch, route disconnect/reconnect, sample-rate change,
Bluetooth playback/call-profile transitions, concurrent commands and disable.
Measure gain with known-source loopback/physical capture, not only a saved UI
percentage. Exercise coreaudiod reset in an explicit fault-injection session,
since that interrupts the machine's audio. Expose only compact error/generation,
format and timing counters outside the callback; never save captured audio.

## Delivery order and review boundary

Implement the audio service, signal kernel and recovery checks before the UI.
Then implement the shared options route and Audio provider, verify action leases,
and qualify physical playback/performance. Each claim names its verified hardware
and scenario; incomplete hardware coverage remains explicitly pending.

Supporting investigation:

- `docs/wayfinder/research/2026-10-03-audio-quality.md`.
- `docs/wayfinder/research/2026-10-03-audio-lifecycle.md`.
- Current project `CODE_STYLE.md`, `PRODUCT.md` and `docs/TODO.md`.

The next review covers this specification, especially the numerical thresholds
and the limits of quiet recovery. An implementation plan follows only after that
review; this document is not evidence of an implemented widget.
