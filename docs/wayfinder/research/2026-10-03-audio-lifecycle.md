# Audio mixer lifecycle: preserving gain across sleep and route changes

Research date: 3 October 2026. This is source research for the approved Audio tile,
internal notch mixer, per-app volume/mute and one output per app. It does not
reproduce the reported FineTune wake reset, implement an engine, or establish
that Vorssaint is immune to that failure.

## Recommendation

Persist user intent independently from processes and audio objects. Reconcile a
fresh audio environment against that intent; install only a current, validated
pipeline whose first rendered block already uses the requested gain and mute.
Expose an unavailable/degraded state instead of silently treating an absent
engine as a successful 100% setting. Build, read and tear down HAL resources away
from the UI and real-time callback.

The approved no-polling design covers discovery with native notifications and
bounded startup/wake/reconfiguration deadlines. It cannot detect a later silent
stall that produces no notification. Maximum liveness coverage needs a separately
reviewed amendment: one shared watchdog only while controlled IO is expected,
sampling atomic render progress rather than amplitude. No per-app timers, no
periodic app enumeration, and no watchdog while all controlled streams are idle.

## Pinned evidence

The inspected local checkouts report these exact revisions:

- FineTune: [`2285279d36d3f8115c1c2d4aecd904f1bdf96a51`](https://github.com/ronitsingh10/FineTune/tree/2285279d36d3f8115c1c2d4aecd904f1bdf96a51).
- Vorssaint: [`aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958`](https://github.com/vorssaint/vorssaint-utils/tree/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958).

Definitions, callers and source ranges were inspected through the repository
graphs. The pinned GitHub web fetch returned a cache miss; the source observations
below come from the local checkouts at the verified commits. No reference tests
or real-app sleep cycles were run for this note. No upstream implementation,
private API, resource or test has been imported into Cascade.

## What the sources establish

| Concern | FineTune | Vorssaint |
| --- | --- | --- |
| Persistent identity | Runtime state uses PID; the persistence key is bundle ID or `name:<name>`. Loading saved volume updates the PID state. [Identity](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Models/AudioApp.swift#L29-L31), [load](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Models/VolumeState.swift#L52-L59). | Uses bundle ID for row and persistence identity; unidentified rows use a PID session identity and may persist by display name. [Identity](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/MixerRoutingSupport.swift#L365-L373). |
| Gain on creation | `ensureTapExists` applies output state before activation. Activation seeds the current gain before `AudioDeviceStart`. A simple omitted-gain explanation is therefore unsupported for this revision. [Creation](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L1214-L1241), [first callback gain](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L681-L703). | The gain engine receives the requested gain before starting; installation rechecks current app objects/route and applies the latest slider value. [Creation](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L2270-L2352), [installation](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L1018-L1073). |
| Wake | The inspected audio engine connects process/device events and a health task. A graph text search of its Audio tree found workspace sleep/wake observers in the media-key monitor, not an explicit mixer wake path. This is a scoped source observation. [Engine callbacks](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L317-L402), [media-key lifecycle](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Keys/MediaKeyMonitor.swift#L152-L164). | Explicit wake handling clears render observations and failure budgets, re-registers output controls, refreshes and reconciles even when the HAL snapshot is unchanged. [Wake path](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L205-L252). |
| Liveness | A task wakes every 2 seconds, including when no taps exist. It skips muted taps, requires a prior rendered callback and 5 seconds since activation, then counts three misses with a 3-second callback window. Recovery adds a 20-second cooldown. [Monitor/recovery](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L1883-L1981), [eligibility](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L172-L187). | A playing app with unchanged render progress for 1.5 seconds is treated as wedged. Successful progress also requests another check, so delayed reconciliation recurs while playing. [Verdict](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/MixerRoutingSupport.swift#L421-L448), [reconciliation](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L1540-L1663). |
| Stale work | Recreation awaits old resource destruction before looking up the current app and restoring its route. [Recovery](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L1944-L1981), [destruction wait](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L818-L835). | Non-reused per-row build tokens and snapshot generations fence stale installation/publication. [Coordinators](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/MixerRoutingSupport.swift#L38-L161), [publication check](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L1193-L1208). |

Vorssaint limits stalled-engine failures to two per app and identical
objects/output configuration. It stops a wedged engine before rebuilding; after
the second failure that configuration stays untapped. This restores original
audio instead of indefinite silence, but the original path has no per-app
attenuation or mute. That is a deliberate availability tradeoff, not a guarantee
that the audible level never returns to system volume. [Failure budget](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/MixerRoutingSupport.swift#L70-L107),
[wedged path](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L1575-L1606).

FineTune's activation waits up to 2 seconds for aggregate readiness using a
run-loop loop. Its engine is main-actor isolated and invokes activation directly.
Vorssaint builds on a worker and bounds queued destruction concurrency to four,
but its `stop()` calls `AudioDeviceStop` synchronously before queued destruction.
These are threading risks to avoid, not measured hangs in this investigation.
[FineTune actor](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L7-L27),
[readiness](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Extensions/AudioObjectID%2BReadiness.swift#L31-L43),
[activation wait](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L618-L623),
[Vorssaint teardown](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift#L2377-L2505).

## Cascade lifecycle contract to review

1. **Authoritative intent.** Store gain, mute and selected output UID by a stable,
   validated app identity, with a monotonic preference revision. PID, HAL object
   IDs, live devices and pipeline state are transient bindings. PID reuse cannot
   inherit another app's gain. Unidentified processes receive session settings;
   a display-name collision must not create durable cross-app policy. Missing
   output never overwrites the selected output preference.
2. **Serialized reconciliation.** A control worker coalesces native process,
   device, running-output, format, default-output and workspace lifecycle events.
   Every snapshot/build carries environment generation, app identity, process
   binding, output UID and preference revision. Sleep, stop and route changes
   invalidate older work. Installation compares against current intent and
   rejects mismatches. One in-flight build per session prevents slider updates
   from creating a backlog.
3. **Prepared before audible.** Validate alive output, stream format/channel
   layout, finite positive sample rate, available source objects and permission.
   Preallocate callback resources; publish gain/mute before starting IO. Treat
   successful HAL creation/start and first valid render as distinct milestones.
   Startup liveness does not require a previous successful render. A silent or
   muted stream can still execute callbacks: detect callback progress, not sample
   amplitude. No unchecked stereo conversion or guessed format is accepted as
   maximum fidelity.
4. **Bounded recovery.** Use finite monotonic deadlines for known lifecycle
   transitions and a small retry budget keyed by configuration/generation.
   Count construction/start failures as well as stalled renders. Reset the budget
   on actual topology change, explicit retry or demonstrated healthy progress;
   repeated identical notifications must not reopen it indefinitely. Preserve
   a working old pipeline until a replacement is validated where the public API
   permits it; qualification must detect overlap, doubling and unity bursts.
5. **Measured watchdog amendment.** If approved, one host scheduler samples an
   allocation-free atomic callback sequence for all currently expected streams.
   It starts/stops with demand and shares the engine's monotonic clock. A pause,
   sleep, disconnect or stopped source must disarm or reclassify the expectation.
   Event deadlines alone remain the default until this amendment is approved.
6. **Teardown containment.** HAL reads, start, stop and destruction stay off main
   and render threads. Bound outstanding cleanup resources and worker concurrency;
   fence late callbacks and retain their minimal context until safe to release.
   A timeout of the waiting task does not cancel a blocking HAL C call. A hung
   call needs a containment/restart policy; never spawn unlimited replacement
   threads to simulate cancellation or claim that a deadline guarantees progress.

### Degraded audio is a product choice

**Native fallback** releases interception and restores the source's original
path. It favors continuity but can return attenuation to unity, undo mute, or
play on an unintended system output. The UI must retain requested controls and
clearly show they are not currently enforced. It must not silently write 100% to
preferences or claim that the displayed mute is effective.

**Quiet failure** suppresses the controlled source until recovery. It favors
avoiding a sudden loud/privacy-sensitive output, but continuing suppression
requires a still-valid interception mechanism. When the tap is missing or HAL
has failed, a public per-app tap backend cannot promise that the original app
stays muted. Lowering global system volume would affect unrelated apps and is
outside the approved per-app behavior. Recommend quiet recovery while control is
valid, explicit degraded reporting when it is not, and review of native fallback
policy before implementation. Neither policy provides unconditional enforcement
after the controlling process or audio service dies.

## Failure and qualification matrix

The rows below are prospective Cascade tests, not reproduced upstream defects.

| Driven scenario | Failure to catch | Required result/evidence |
| --- | --- | --- |
| Sleep/wake with app at 25%, then with mute | Old HAL snapshot appears identical; original output resumes | Desired state unchanged; first controlled block uses current intent; capture audio through the transition to detect unity bursts. |
| Headphones disappear/reappear during wake | Listener registration is stale; fallback overwrites routing | Rebind listeners regardless of reused object ID; selected UID survives; degraded/applied route is separate. |
| Helper relaunch, PID reuse, two apps with same display name | Wrong app inherits policy | Stable owner resolution plus transient process binding; no durable name-only collision. |
| Slider/mute/route changes during a delayed build | Old build installs obsolete gain or output | Generation/revision rejection; final first callback uses latest request. |
| HAL creation succeeds but IO never starts | Initial dead tap escapes health eligibility | Finite startup deadline and bounded recovery without needing an earlier callback. |
| Source emits silence, pauses or is muted | Amplitude-based watchdog falsely rebuilds | Callback sequence and source running state distinguish silence from lack of expected IO. |
| Bluetooth microphone activates; device format changes | Wrong rate/layout survives; sound is attenuated or distorted | Revalidate actual negotiated format, update/rebuild safely; measure output and transition artifacts. |
| Repeated identical failure and notification storm | Unlimited builds, teardown backlog or idle wakeups | Exhausted configuration budget remains exhausted; bounded live/retiring resources. |
| Audio service interruption; stop during blocked teardown | UI stalls; late callback dereferences freed memory | UI responsive; bounded worker/resource containment; late results rejected. |
| Notch closes while app gain is 25% | Presentation suspension releases audio policy | Audio control ownership persists; meters/UI subscriptions stop; no reset to unity. |
| Invalid permission, missing device, failed interceptor | UI claims mute/gain that is not applied | Requested and applied states diverge visibly; no fabricated enforcement guarantee. |

Before/after measurements must use the same running-app scenarios: idle closed
notch, idle open mixer, one and several playing controlled apps, silence/mute,
and repeated wake/device transitions. Record CPU, CPU wakeups, resident memory,
callback timing versus buffer duration, outstanding resources, recovery duration
and audio discontinuities. Compare deadline-only versus conditional watchdog
energy use before adopting its cadence. At steady idle with no expected controlled
IO there must be zero audio watchdog timers and zero discovery polling. Numeric
active budgets and a device/format coverage matrix must be fixed before claiming
system-like quality; source reading supplies no performance or fidelity numbers.
