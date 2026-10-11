# Audio widget and per-app mixer

Date: 9 October 2026. Branch: `cava/audio-mixer`, from `main` at `c0074fa`.
Status: design approved section by section in the conversation of 8 and 9 October.
Part A (the bar, the detail surface and the global mixer) and Part B (per-app audio
through `AudioHost`) are implemented. §2 and §3 carry amendments of 10 and 11 October,
marked where they apply. The numeric gates are targets to measure, not results; the
manual measurements are listed in `docs/superpowers/verification/2026-10-10-audio-widget-part-b.md`.

This spec replaces the 3 October audio mixer design on `cava/audio`, which was built on
the deleted addon SDK (`CascadeAddonSDK`, `ServiceBroker`). Its research is carried over
to this branch unchanged, and is still the evidence base for the engine:

- [Signal integrity and realtime risks](../../wayfinder/research/2026-10-03-audio-quality.md)
- [Lifecycle: gain across sleep and route changes](../../wayfinder/research/2026-10-03-audio-lifecycle.md)
- [Public and private control candidates](../../wayfinder/research/2026-10-03-audio-private-api-candidates.md)
- [System probe results](../../wayfinder/research/2026-10-03-audio-system-probe-results.md), probe in `Prototypes/AudioSystemProbe`

## Intent

A volume widget for the notch. At rest it is a vertical capsule, shaped like a 1x2 tile, whose
white fill is the global output level and whose icon is the output device: a generic speaker
by default, and the exact device when Cascade recognises it, AirPods drawn in their model and
colour. Scrolling or dragging it changes the global volume; clicking it opens a full mixer
with the global level on the left and, to its right, one column per app that is playing, each
with its own volume, mute and output. Any output selector, global or per app, can switch to
several outputs at once.

Success means: the bar feels like a native control at the display's refresh rate; per-app
settings stay applied through sleep, device changes and restarts, or the UI says plainly that
they are not; and Cascade at rest pays nothing for any of it.

### Decisions taken in conversation

| Topic | Decision |
| --- | --- |
| Scope | UI and backend in one design; delivery in phases (§6) |
| Widget size | `1x2` only |
| Bar gestures | Vertical scroll, vertical drag, click opens the mixer |
| Apps listed | Only apps producing audio; their settings persist by bundle ID |
| Several outputs | Selection only: one volume per app, no per-output trim, no latency alignment |
| Mixer layout | Global capsule on the left, divider, one capsule column per app |
| Output selector | A panel beside the app's column; the column stays visible and adjustable |
| Per-app engine | A dedicated, isolated `AudioHost` XPC service |
| Output switch | Crossfade between old and new pipeline, included in v1 |
| Old branch | `cava/audio` is deleted once this work is done |

### Out of scope

Equaliser, boost above 100 %, limiter or any other non-linear processing, per-output volume
trim, latency alignment between outputs, per-app AirPlay (it needs the private
`AVOutputContext` route and a polling timer, as Vorssaint does), microphone and input
controls, and a virtual HAL driver.

## 1. Architecture

```
            ┌──────────────── Cascade (main actor + kernel) ────────────────┐
 widget 1x2 │ audio.volumeBar ──┐                                           │
 detail     │ audio.mixer      ─┼──► AudioMixerModel (@Observable, main)    │
            │ audio.outputPicker┘          ▲   │ commands, at most one/frame│
            │                              │   ▼                            │
            │  SystemAudioService (kernel, always available)                │
            │    global volume and mute, system output, device list,        │
            │    device identity (Bluetooth → model), global multi-output   │
            └──────────────────────────────┬────────────────────────────────┘
                                           │ XPC: snapshots up, commands down
            ┌──────────────────────────────▼────────────────────────────────┐
            │ AudioHost.xpc (isolated process)                              │
            │    discovery of playing apps (HAL listeners, no polling)      │
            │    per app: process tap + private aggregate + IOProc          │
            │    per-app routing to one or N outputs, crossfade on switch   │
            └───────────────────────────────────────────────────────────────┘

 com.cascade.audio (PluginHost): a manifest and two static documents that hold the
 components; it never sees a volume step.
```

**Why the kernel draws it.** A drag must move the fill at 120 Hz. A round trip through the
plugin (XPC, `handle()`, publication) is capped at one publication every 250 ms and would lag
visibly. Spec §6 of the plugin engine already places anything that handles input or updates
the UI more than about ten times a second in the kernel. So the bar, the mixer and the output
selector are **tier-2 components fed by services**, and the plugin stays thin.

**`com.cascade.audio`.** One feature, `audio`, with surfaces `widget` (`sizes: ["1x2"]`) and
`detail` (§2), components `audio.volumeBar`, `audio.mixer` and `audio.outputPicker`, services
`audio.system` and `audio.apps`, and permission `audio.capture`. On its first `refresh` it
publishes one document per surface, each a single `Component`, and then has no reason to wake.

**`SystemAudioService`** lives in the kernel beside the `volume` source and absorbs what
already exists there: `CoreAudioSystemVolume`, `CoreAudioVolumeMonitor` and
`OutputDeviceAccess`. It owns everything that is system-wide rather than per app: global level
and mute, the system output, the device list, global multi-output, and device identity. Identity
maps a Core Audio device to an icon from its transport type (built-in, USB, HDMI/DisplayPort,
AirPlay, Bluetooth) and, for Bluetooth, matches the device UID's address against the
`bluetooth` source to obtain `model`, `productID` and `colorID`, which the existing
`bluetooth.device` drawing renders. Its HAL work runs on a utility queue, never on main.

**`AudioHost`** is a second bundled XPC service, signed and checked with the same requirement
as PluginHost. It starts with the first lease of `audio.mixer` or when a saved per-app intent
needs applying, and stops when no intent is active and no mixer is visible.

**`AudioMixerModel`** is the main-actor `@Observable` state the components read. A drag
updates the touched column's model immediately; the command to the service is coalesced to at
most one per frame. No timers.

**Volume keys and global multi-output.** A multi-output device has no master volume, so the
hardware keys would do nothing. `VolumeKeyRouter` already intercepts them; while the system
output is Cascade's multi-output device it applies the step to every sub-device.

**Cost at rest:** no polling, `AudioHost` not running, the plugin idle, components suspended
while not visible.

## 2. Surfaces, components and interaction

### The `detail` surface (plugin engine)

A new shared capability, not an Audio-only path. A feature may declare
`"surfaces": { "widget": { ... }, "detail": {} }`. Clicking a widget whose feature has a detail
opens it as a page in the notch's normal expanded size, with a back control at the top left. Back, Escape, a click outside the notch, the notch
closing, the display changing and the plugin being disabled close it and restore the grid.
One detail is open at a time: opening another replaces it. Its document is an ordinary
publication with the usual limits and `staleAfter` rule; opening it does not wake the plugin.

*Amendment of 10 October.* The detail page does not extend the notch: it keeps the notch's
normal size and the mixer is laid out inside it. The 240 pt extended height is not used.

### Components

| Component | Surface | Fed by |
| --- | --- | --- |
| `audio.volumeBar` v1 (new) | widget `1x2` | `SystemAudioService`: level, mute, output icon |
| `audio.mixer` v1 (new) | detail | global from `SystemAudioService`, app columns from `AudioHost` |
| `audio.outputPicker` v1 (already in the catalog) | inside the mixer | devices, selection, "several outputs" toggle |

They take no parameters from the plugin. A missing grant, a denied TCC permission or an
unavailable service draws the component's unavailable state with its reason.

### The bar

A capsule, dark glass above and white fill below. The icon sits low, inside the fill.

| State | Look |
| --- | --- |
| Built-in or unrecognised output | The level speaker: `speaker.fill`, `speaker.wave.1.fill`, `speaker.wave.2.fill` or `speaker.wave.3.fill` |
| Identified Bluetooth device | The AirPods SF Symbol of its model |
| Other Bluetooth device | `headphones` |
| Muted | Grey fill, level kept, `speaker.slash` |
| Scrolling or dragging | Capsule scaled up slightly |
| Global multi-output | Icon of the clock device with a `+N` badge |

*Amendment of 10 and 11 October.* Every icon is an SF Symbol: the `bluetooth.device` drawing
is not used for the audio output. The pill shows the level speaker for the built-in and the
unknown outputs, AirPods symbols for identified Bluetooth devices and headphones for generic
Bluetooth; the device icons of the table above (`laptopcomputer`, `display`, `tv`,
`airplayaudio`) belong to the output picker and the output button, not to the pill. The
percentage is shown only in the mixer, never on the bar. The icon is white over the glass and
light blue (`#00C6EA`) over the white level fill, sized 0.49 of the pill's width and centred
0.51 of the width above its bottom. On the grid the pill is 60 % of the cell width; in the
mixer it takes the full width of its column. Scrolling follows the fingers (up raises the
level) whatever the natural-scrolling setting.

Gestures: vertical scroll (trackpad continuous, wheel in steps of 1/16 like macOS), vertical
drag like a slider, click (no movement beyond 4 pt) opens the mixer. Long press stays with the
grid's rearranging. Volume 0 is not mute; mute is set from the mixer.

### The mixer

Global capsule on the left, wider, with its percentage above and its output button below;
a divider; then one narrower capsule column per playing app: app icon above, capsule, and
under it a mute button and an output button whose icon is the app's current output (`²`-style
count when it plays to several).

*Amendment of 10 and 11 October (layout "A").* The title "Audio · NN %" sits in the left
shoulder of the notch, beside the hardware notch. Under it comes the global capsule, with the
output button and the mute button beside it, then a divider, then the apps area. The output
button shows the icon of the device (built-in: a MacBook, with `laptopcomputer` as fallback;
unknown: `hifispeaker`).
Each column takes the same scroll and drag as the bar. Past
about six apps the strip scrolls horizontally. An app appears when it starts producing audio
and leaves about 3 s after it stops, so a gap between tracks does not make it flicker.

### The output selector

Opened by an output button, it is a panel beside that column: the column stays visible and
adjustable, the other apps slide out of the way. At the top a "Più uscite" toggle switches the
list between single and multiple selection. For an app the first entry is "Segui sistema"; the
global selector has none. Click outside or Escape closes it. Turning "Più uscite" on for the
global selector creates Cascade's multi-output device and makes it the system output (§3);
turning it off sets the system output to the single device left selected and destroys the
multi-output device.

### States the UI always shows

*Applied* (normal), *recovering* (a quiet indicator), *not applied* (dashed column, with
"Torna all'audio nativo"). The UI never shows a volume as applied when it is not.

### Accessibility

Each capsule is an adjustable element (`accessibilityAdjustableAction`) named after the app
or "Volume globale" with its percentage; mute and output are labelled buttons.

## 3. The `AudioHost` engine

**Threads.** One serial control queue for every HAL call (create, start, stop, destroy); the
HAL's own IOProc threads; the XPC queue. State sits behind a `Mutex`; no actors, as in the
plugin engine. Cascade's main thread never calls the HAL for the mixer.

**Discovery, no polling.** Listeners on `kAudioHardwarePropertyProcessObjectList` and on each
process object's `kAudioProcessPropertyIsRunningOutput`. Processes are grouped by their
responsible app (bundle ID plus responsible process), so browser and helper processes land
under their app. PIDs and HAL object IDs are transient bindings and are never persisted; a
reused PID never inherits another app's settings.

**Intents.** `{ gain, isMuted, outputs: [deviceUID] or followSystem, allowsSeveral }` by bundle
ID, with a monotonic revision. Cascade owns and persists them and sends them to `AudioHost`
whenever it starts, so a restart loses nothing. A disconnected device never erases a
preference; the *effective* output (the fallback) is shown separately.

**Per-app pipeline, only when needed.** An app at 100 %, unmuted and following the system gets
no tap at all: native path, zero cost. Otherwise:

1. A process tap with `muteBehavior = .mutedWhenTapped`: a stream-specific tap when there is
   one output (keeps multichannel), a stereo mixdown otherwise.
2. A private aggregate device holding the tap and the outputs, `TapAutoStart` on. With N
   outputs it is *stacked*: the first selected output is the clock and main sub-device, the
   others get drift compensation, and the same audio plays on all of them (FineTune's
   approach).
3. An IOProc whose body is a small C/C++ kernel: no allocation, lock or logging; it reads one
   atomic command, maps the tap's channels onto the device's shape (Vorssaint's
   `MixerRender` lesson: a mono call headset, an 8-channel interface, a device's own input
   buffers ahead of the tap), applies gain with a 5 ms ramp advanced once per frame across
   channels, writes exact zeros when muted, and initialises every output byte. No limiter.
4. Gain and mute are seeded **before** `AudioDeviceStart`, so the first buffer is never at
   unity.

**Crossfade.** Changing an app's outputs builds the new pipeline while the old one plays,
crosses them with an equal-power curve over 50 ms, then destroys the old one. The double
pipeline lives at most 100 ms. If the old output is already gone, the switch is direct.

**Global multi-output** (in `SystemAudioService`, not `AudioHost`). A non-private aggregate,
"Cascade Multi-Output", set as the system output; it must be public because the system cannot
see a private aggregate. Apps that follow the system follow it.

**Recovery.** Wake, a device or format change and a `coreaudiod` restart rebuild regardless,
even when the IDs look unchanged. Every build carries a generation; obsolete ones are
rejected. Retries run immediately, then at 100, 300 and 1000 ms; at 3 s the column turns *not
applied*. After two failures of the same configuration the app returns to native audio, and
the UI says so. One 1 Hz watchdog runs **only while controlled IO is expected** and samples an
atomic render counter, never amplitude, so silence and pauses are not failures.

**Orphans.** `AudioHost` destroys leftover `Cascade-*` aggregates when it starts; when it dies,
Cascade does the same cleanup before restarting it. FineTune documents that taps orphaned by
a `kill -9` silently mute apps, which is the failure this guards against. (Amended: the phase 0
spike found that private taps and aggregates die with their process and leave nothing to sweep,
see the end of this section.)

**Spikes before the plan's engine phases.** The documentation does not settle these, so
phase 0 measures them: whether private aggregates and taps really vanish when their process
dies; whether the public multi-output aggregate survives a Cascade crash and must be cleaned
up; and that TCC attributes `AudioHost`'s capture request to Cascade.

*Amendment of 10 and 11 October: the answers.* They are recorded in
`docs/superpowers/verification/2026-10-09-audio-lifecycle-spike.md` and
`docs/superpowers/verification/2026-10-10-audio-tap-permission-spike.md`.

- *A, yes.* A private aggregate and its process tap die with their creator on `kill -9`, so
  `AudioHost` has no private object to sweep. The *Orphans* paragraph above is amended
  accordingly: the startup sweep applies to the public `cascade.multi-output.*` aggregate only,
  which is Cascade's, not `AudioHost`'s.
- *B, no.* After the kill the tapped app is audible again at once: a crashed `AudioHost` does
  not leave an app muted. The recovery stays as written, because the fault is still felt for
  as long as it takes to restart.
- *C, yes.* The public multi-output aggregate survives its creator's `kill -9` and needs the
  startup sweep of its prefix.
- *Permission.* What a denied "System Audio Recording" permission does to a muting tap (whether
  creation fails, whether the app is silenced or stays audible, and what signal tells denial
  from silence) is **not yet measured**: the probe's runs P1 to P4 wait for a person to toggle
  the permission and listen. Until they are done `captureAllowed` in `AudioHostSnapshot` stays
  unknown (`nil`), which the model treats as allowed, and §4's read-only columns and banner
  are built but never triggered by a measured denial. How helper processes group under their
  app (P4) is settled for Brave by the probe's smoke run: the bundle ID is the helper's, so
  the grouping uses the outermost `.app` of the executable.

## 4. Permissions, failures and budgets

**Permissions.** Taps need the "System Audio Recording" TCC permission, asked once, at the
first real per-app control, never on opening the mixer. Denied, the mixer shows the global
capsule and read-only app columns with a banner to open Settings. Global volume, system
output and global multi-output need no permission.

**`AudioHost` failures**, handled like PluginHost:

- *Crash*: Cascade cleans `Cascade-*` aggregates, restarts it and replays the intents; columns
  show *recovering*.
- *Hang*: every XPC command has a 3 s reply deadline; past it Cascade kills `AudioHost` and
  treats it as a crash. A blocked HAL call cannot be cancelled, so this is the only remedy.
- *Memory*: measured as PluginHost is, restarted past 64 MiB.
- Three crashes, hangs or memory kills in five minutes, in any mix, and Cascade gives up: per-app
  audio returns to native, and Settings → Plugins shows `AudioHost`'s state with Restart.

**Per-app failures** follow §3's bounded recovery, then *not applied* with "Torna all'audio
nativo". Cascade never lowers the global volume to hide a per-app failure.

**Gates** (to measure before and after on the same hardware and scenario):

| Property | Gate |
| --- | --- |
| Rest (no active intent, notch closed) | `AudioHost` not running; 0 timers; 0 callbacks |
| Incremental CPU | < 1 % for one stereo app at 48 kHz; < 3 % for ten |
| Incremental private memory | ≤ 16 MiB for one app; ≤ 48 MiB for ten |
| Callback | 0 allocations and locks; p99.9 < 10 % of the buffer interval |
| Added latency | Wired ≤ one device buffer + 2 ms; Bluetooth ≤ 20 ms against bypass |
| Recovery | Within 3 s, or a visible *not applied* |
| Crossfade | No measurable gap or doubling; double pipeline ≤ 100 ms |

## 5. Testing

TDD on the pure parts; the HAL sits behind a protocol with a fake for tests.

- **Reconciliation** as a value-type reducer: intents, environment and generation in, actions
  out. Covers wake, reused PIDs, helper processes and obsolete builds without the HAL.
- **Identity and intents**: responsible-app grouping, preferences surviving a missing device.
- **Gestures**: scroll steps, drag threshold, click versus drag, command coalescing.
- **Engine**: manifest validation of `detail`, the new components in the catalog, detail
  open/close/replace rules.
- **Realtime kernel**: an offline harness against a high-precision oracle at 44.1, 48, 96 and
  192 kHz; mono and stereo; planar and interleaved; right-only, near-silence, full-scale
  peaks, NaN and invalid buffers; ramp and crossfade.
- **Supervision**: `AudioHost` crash, hang, memory kill and give-up, over a fake transport.
- **Physical qualification**, recorded in `docs/superpowers/verification/`: 50 sleep/wake
  cycles, AirPods disconnect and reconnect while playing, `kill -9` of `AudioHost` and of
  Cascade, and before/after CPU, memory and latency against the gates.

## 6. Delivery order

Each phase ends with its tests green and a commit.

0. **Spikes**: process-death behaviour of private aggregates and taps, persistence of the
   public multi-output aggregate, TCC attribution for `AudioHost.xpc`. Their results may
   change phases 3 and 4. The answers on process death and persistence are recorded (§3);
   the denied-permission behaviour is still pending.
1. **Engine**: the `detail` surface and the infrastructure for service-fed tier-2 components.
2. **The bar**: `SystemAudioService`, `audio.volumeBar`, `com.cascade.audio` with its widget.
   Shippable on its own.
3. **Global-only mixer**: `audio.mixer` and `audio.outputPicker` for the global output,
   global multi-output, volume keys.
4. **`AudioHost` skeleton**: XPC target, discovery, identity, intents, supervision, orphans.
5. **Realtime kernel** and its harness.
6. **Per-app pipeline**: gain and mute, then one output, then N outputs, then crossfade.
7. **Recovery**: wake, devices, formats, watchdog.
8. **Qualification and documentation**: `docs/plugins` (manifest, content, services) and the
   pending list in `CLAUDE.md`.
