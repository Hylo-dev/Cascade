# Cascade: unified plugin engine

Date: 29 September 2026. Status: design approved section by section in the conversation of 28 and 29 September; implementation plan not written yet. Numeric limits are starting values to calibrate on the Music plugin. No implementation phase is complete.

This spec covers the first of three sub-projects: the **plugin engine**. The other two get their own spec, plan and implementation cycle:

1. Plugin engine (this document): contract, manifest, execution, supervision, DSL, renderer.
2. Notch layout: slot pages like the iPhone home screen, rearranging a widget with a long press when it fits the free slots, arbitration of compact and expanded space, persistence of the arrangement.
3. Services and Music: the media and spectrum services, the tier-2 components, Music migrated to a tier-2 plugin.

Until the layout sub-project lands, the engine publishes into the current `WidgetHost` auto-placement.

It supersedes, for the areas it covers, [the addon runtime design](2026-09-09-addon-runtime-design.md) and [the addon control policy](2026-09-10-addon-control-policy.md). The policy that allowed in-process executors only as test doubles is replaced by §4. External addons keep the launcher qualification requirements of those documents; this spec does not unblock them.

## 1. Why

Today Cascade has two plugin systems that do not meet.

- **In-process layer (what runs).** `NotchWidget`, `NotchLiveActivity`, `NotchTransientNotice` and `NotchContextualPage` return SwiftUI `AnyView` on the main actor. The resource contract is only a convention: nothing measures or caps a widget, and a trap in any of them takes Cascade down. Widget grid, expanded fallback and contextual page are three overlapping "expanded content" concepts. There are three invalidation mechanisms, and the `NotchState` side bits are never produced.
- **Out-of-process addon platform (what is designed).** About 35,000 lines in `CascadeContracts`, `CascadeRuntime`, `CascadePresentation`, `CascadeAddonSDK` and `CascadeAddonTool`, with about 47,000 lines of tests. There is no process launcher, no OS transport, no production `AddonRuntimeAdapter`, and no glue from `AddonRuntime` to `AddonPresentationBridge`. `AddonRuntime` is `internal` and the app never builds it. Only `FileWorkspaceHost` and `ResourceGovernor` run in production, for the file shelf.

The goal is one framework in which a plugin is written once and runs either inside Cascade's own trust boundary or in an isolated process, without changing its code. It must keep enough expressiveness to host Music. The first-party side is built first because it is the notch's first scaffold.

### Success criteria

- A first-party plugin can never crash or hang Cascade.
- The Music plugin reaches today's features with CPU and RAM equal or lower. The existing budget applies: hover below 10% CPU, RAM far below 100 MB.
- A first-party plugin moves to an isolated process with no source change.
- While nothing changes, no plugin code runs and nothing wakes the CPU.

## 2. Decisions

| # | Decision |
|---|---|
| D1 | The contract is data, never `AnyView`. A plugin emits declarative content; only the executor differs. |
| D2 | The DSL is a serializable mirror of SwiftUI vocabulary in three tiers (§8). |
| D3 | Cascade is a microkernel. First-party plugins run in one shared **PluginHost** XPC service bundled in Cascade. The in-process executor is only a test and development double. External plugins will get one process each, through the same `PluginExecutor` protocol. |
| D4 | The host decides the execution mode from package identity and signature. The manifest never declares trust. |
| D5 | Plugins are thin. Heavy or privileged work lives in services, placed by the rule in §6. |
| D6 | Tier-2 components get data directly from kernel services, never through the plugin. |
| D7 | Three surfaces: widget, activity, notice. There are no plugin pages in v1, and the expanded fallback is removed (§7). |
| D8 | Visibility is per surface. Sources are always-armed, event-driven listeners from a host catalog (§5). |
| D9 | Stateful controls carry kernel-owned optimistic state; the publication is the source of truth (§9). |
| D10 | No actors in the engine: a `Mutex` per state owner, dedicated threads, low-level signaling (§3). The deployment floor becomes macOS 15. |
| D11 | The plugin SDK's `handle()` is synchronous on the plugin's dedicated thread. |
| D12 | The kernel is the single dispatcher of every event (§11). |
| D13 | Build approach: a new slim engine that harvests the pure pieces of the existing runtime. `AddonRuntime` is frozen, then deleted (§15). |
| D14 | Naming: "Plugin" in every new module and type. |

## 3. Concurrency

The deployment floor rises from macOS 14 to macOS 15, so the engine can use `Mutex` from Synchronization. This is a project-wide change: `CLAUDE.md`, `CascadeKit/Package.swift` and the Xcode deployment target move together, and the change is called out in the implementation plan.

**Pattern.** Each piece of shared state is a value-type state machine, owned by one object that guards it with one `Mutex`. Because `Mutex<State>` is `Sendable`, owners are `final class …: Sendable` and the compiler keeps checking them. `@unchecked Sendable` needs a written justification next to the field.

**Rules.**

1. Mutual exclusion uses `Mutex`, which inherits the waiter's priority. `DispatchSemaphore` is only a signal between dedicated threads, always with a timeout.
2. Never call out while holding a lock: no callback, XPC send or plugin code. Copy the state, release, then call.
3. Never block the main thread or the Swift concurrency pool. Blocking happens only on threads the engine owns.
4. Timing uses one shared `DispatchSourceTimer` for deadlines and the watchdog. No `Task.sleep`, no per-object timers.
5. Engine types are explicitly `nonisolated`, because the targets default to MainActor isolation. A MainActor-isolated C callback running off main traps.

**Thread map.**

| Context | Work |
|---|---|
| Main thread | Applies one coalesced diff and updates only the observed nodes that changed. It never waits on a contended lock. |
| Engine thread (kernel) | Validation, hash normalization and diff, broker, supervisor, scheduler. |
| XPC thread | Receives PluginHost messages and hands them to the engine thread. |
| PluginHost, one thread per plugin | Runs `handle()`. The thread's CPU time is the plugin's CPU time. |

## 4. Execution and supervision

```
┌──────────────── Cascade (kernel) ─────────────────┐        ┌──── PluginHost (bundled XPC service) ────┐
│ layout, renderer, publications, kernel services,  │ ◄─XPC─►│ every first-party plugin, one thread each │
│ supervisor, scheduler, tier-2 components          │        │ no AppKit or SwiftUI: data only           │
└───────────────────────────────────────────────────┘        └───────────────────────────────────────────┘
```

**Executors (`PluginExecutor`).**

| Executor | Use | Stop means |
|---|---|---|
| `InProcessExecutor` | Tests and development only | Abandon the plugin's thread. At most one leaked thread per plugin; a plugin whose previous thread is still stuck cannot be re-enabled until Cascade restarts. |
| `SharedHostExecutor` | First-party production (PluginHost) | SIGKILL PluginHost, then restart it |
| `IsolatedProcessExecutor` | External plugins, later | Kill that plugin's process |

**Why PluginHost is not blocked like the external launcher.** It lives in Cascade's bundle and carries our signature. It needs no discovery or ExtensionKit approval and involves no other publisher. The [XPC lifetime test of 24 September](../verification/2026-09-24-addon-xpc-lifetime.md) observed the service exiting with SIGKILL about 1 to 2 ms after the client exited normally or was killed, so there are no orphans. The same test showed that cancelling the connection does **not** stop a service whose callback is held; hence the SIGKILL path, which spike S1 verifies.

**Supervisor.** It lives in the kernel, separate from the scheduler: the scheduler decides *when* an event is delivered, the supervisor decides *whether* a plugin is healthy. Its policy is `HealthPolicy`, harvested from `AddonHealthStore`. Per plugin, the states are:

`enabled` → (`idle` ⇄ `handling`) → `retrying` | `disabledAfterHang` | `quarantined`

The failure table is in §13.

## 5. Lifecycle and sources

**Three separate lives.**

1. **Work.** PluginHost stays alive while Cascade runs and is idle when nothing changes. Launching on demand, which costs about 66 ms per wake in the XPC fixtures, is deferred until measured RAM justifies it.
2. **Presentation.** Publications live in the kernel, independent of the plugin. The notch always shows the last valid content, including across a PluginHost restart.
3. **Visibility.** It is decided per surface, not by notch state. The compact activity is visible while the notch is closed and keeps updating. Tier-2 component instances activate while their surface is visible and suspend when it is not. The expanded view and widgets on a page that is not open are not visible.

**Sources.** A plugin is finite handlers plus manifest-declared sources: always-armed listeners that cost no CPU while waiting (notification, socket, kernel event) and wake the plugin when something happens. A source runs while its plugin is enabled and needs it, even before any surface exists; Music must notice playback starting in order to create its activity, like push-to-start for Live Activities. The broker's shared sources (`ServiceSourceStartFrame`: start with the first lease, stop with the last) are the base.

- **v1 sources come only from the host catalog:** `media.nowPlaying`, `bluetooth`, `power`, `volume`, `network`, and generic `net.webSocket` and `net.sse`. Plugins cannot write sources in v1: inside a shared process, a polling source could not be attributed to its plugin. A new first-party need is met by adding a catalog source.
- **No polling.** A plugin that needs a cadence asks the scheduler, which enforces a minimum interval.
- **Coalescing.** A plugin receives the latest state of a source, never a backlog.
- **Budget.** Publications have a sustained rate plus a burst allowance. Excess is coalesced, not dropped. Clocks, timers and time-driven progress are drawn by the kernel and cost nothing.

**Nothing on open and close.** The notch opens on hover, often. The kernel never tells plugins that it opened or closed. When a surface becomes visible and its publication is stale per its `stalePolicy`, the kernel sends a single `refresh`. Otherwise a plugin wakes only for a source event, a scheduled deadline or a user action.

## 6. Service placement

| Place | Rule | v1 members |
|---|---|---|
| Kernel | Touches frames, input or the notch window, or updates the UI more than about 10 times a second | Spectrum capture (CoreAudio tap), spacebar and Spotlight input taps, file shelf, Spotlight |
| PluginHost | Talks to other apps or parses system data at human frequency | Now playing and Music commands (AppleEvents), Bluetooth monitor and metadata, power, volume, network |

Tier-2 components bind **only** to kernel services. Data born in PluginHost reaches the kernel as publication data; artwork, for example, travels through the asset pipeline. Playback position is not a stream: it is a snapshot of elapsed time, rate and timestamp, and the kernel draws the progress.

Input taps stay in the kernel on their dedicated thread because a stalled tap freezes system input. Risky integrations such as AppleEvents live in PluginHost, where a crash costs only a PluginHost restart. If spike S2 shows that TCC does not attribute PluginHost's requests to Cascade, the affected services move into the kernel.

## 7. Surfaces

| Surface | What it is | Notes |
|---|---|---|
| Widget | One slot on a page | The plugin declares supported sizes, for example `2x1` and `2x2`; the user picks size and position (layout sub-project) |
| Activity | Compact leading and trailing, minimal, expanded | Today's Live Activity model, including the 8-hour lifetime cap and host arbitration |
| Notice | Short notice | At most 10 seconds, shown on the focused display |

Full pages remain for system surfaces (the file shelf) and for widget pages. The expanded fallback is removed. Music publishes a self-expiring activity while playing or recently paused, plus an optional Music widget the user can place on page 0. This also removes today's collision in which a paused player hides the widget grid.

## 8. DSL and renderer

**Tiers.**

1. **Tier 1, the portable DSL.** SwiftUI-shaped values, identical in process and out of process.
2. **Tier 2, host-native components.** Named nodes the kernel implements natively and feeds from kernel services. A new component is added to the kernel and versioned.
3. **Tier 3, real SwiftUI.** Only for system surfaces, or later as an ExtensionKit remote scene with a separate lease. It always has a tier-1 fallback. It is not part of the plugin SDK in v1.

**Tier-1 vocabulary v1.** Only the real consumers drive it: Clock, the charging, Bluetooth, volume and unsupported-file notices, and Music. No node exists without a consumer.

| Group | Nodes and modifiers |
|---|---|
| Layout | `VStack`, `HStack`, `ZStack`, `Spacer`; `overlay` and `background` as modifiers |
| Content | `Text`, `Image(systemName:)`, `Image(asset:)`, `Circle`, `Capsule`, `RoundedRectangle` |
| Kernel-drawn time | `Text(date, style: .time)`, `Text(timerInterval:)`, `ProgressView(timerInterval:)` |
| Progress | Linear and circular `ProgressView` |
| Controls | `Button`, `Toggle`, `Slider` |
| Modifiers | `font` (style, weight, `monospacedDigit`), `foregroundStyle` (color, hierarchical, gradient), `frame`, `padding`, `opacity`, `clipShape`, `lineLimit`, `contentTransition` (`numericText`, `symbolEffect`), `transition`, `accessibilityLabel`, `id` |

Excluded from v1: `ForEach` and dynamic lists, grids, gestures. Glass lights stay a document-level feature, as today.

**Tier-2 catalog v1:** `audio.spectrum`, `media.scrubber`, `audio.outputPicker`.

**Example (Music compact content):**

```swift
HStack(spacing: 8) {
    Image(asset: artwork)
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    VStack(alignment: .leading) {
        Text(title)
            .font(.headline)
            .lineLimit(1)
        Text(artist)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
    Toggle(isOn: isPlaying, action: .togglePlayback)
        .contentTransition(.symbolEffect)
}
```

**Identity.** Structural by default (index path plus node kind), explicit with `.id()` for transitions and future lists.

**Limits.** 64 KiB per document, about 256 nodes, depth 12. Music nests deeper than today's limit of 8.

**Normalization and diff (engine thread).**
- A document becomes a flat, contiguous node table with parent and child indices and stable ids.
- Each node carries a Merkle-style hash of its properties and its children's hashes, so an unchanged subtree is skipped in one comparison.
- The wire always carries full snapshots and the kernel diffs them. Patches on the wire wait for a measurement that justifies them. In process, values pass without encoding.

**Renderer (CascadeKit).**
- `NodeStore` keeps one `@Observable` model per node. The main thread receives the list of changed nodes and updates only those models, so Observation invalidates only their views.
- `NodeView` is a nominal recursive view: a `switch` over the node kind, children rendered through `NodeView`. It uses no `AnyView`.

**`NativeComponent` (tier 2).** Each component has an id, a version, typed and validated parameters (source, style) and a native view factory. Activation and suspension follow the surface visibility reported by the host, not `onAppear`, which is unreliable while the fixed `NSHostingView`s swap their root views. One instance survives across publications, keyed by node identity.

**Validation.** A document declares its schema version and the manifest declares component versions. An unknown node, or a component the feature did not declare, rejects the document. For first-party plugins this surfaces at build time.

## 9. Interaction

**Stateful controls** (`Toggle`, `Slider`, pickers) keep their local value in the kernel's node model, separate from the published value.
- On a tap the value changes immediately, animated, and the action is sent.
- The next publication always wins, even when it contradicts the optimistic value.
- With no confirmation within the timeout (starting value 1.5 s), or on a failed action, the value reverts, animated.
- While a slider is dragged, incoming publications do not move the thumb. The value is sent on release.

**Plain `Button`s** are stateless: immediate press feedback, then the action.

**Actions** carry `(nodeID, revision)`. The broker checks the feature grant and that the revision is current, reusing the checks of `ActionAuthorizer`.

## 10. Permissions and manifest v2

**Two permission layers.**
1. **macOS TCC** (Automation, Bluetooth, audio capture) is asked once for Cascade, at the first real use.
2. **Cascade broker grants**, per plugin and per feature:
   - everything is declared in the manifest, first-party included, and undeclared use is denied;
   - declared permissions of bundled plugins signed by us are granted automatically, while external plugins will need explicit user approval of sensitive permissions;
   - grants are rechecked on every call and revocable per plugin from Cascade's settings, with immediate effect: the source stops and the component shows its unavailable state;
   - a sensitive tier-2 component such as `audio.spectrum` activates only when both TCC and the grant allow it.

Parity means no private code path. Only the default approver differs.

**Manifest v2** replaces v1 with no migration, since no external addon exists.

```json
{
  "manifestVersion": 2,
  "id": "com.cascade.music",
  "version": "1.0.0",
  "compatibility": { "macOS": "15.0", "cascadeProtocol": { "major": 2, "minimumMinor": 0 } },
  "execution": { "entryPoint": "MusicPlugin" },
  "sourceApp": "com.apple.Music",
  "features": [
    {
      "id": "now-playing",
      "surfaces": {
        "activity": {},
        "widget": { "sizes": ["2x1", "2x2"] }
      },
      "sources":     ["media.nowPlaying"],
      "services":    ["media.commands"],
      "components":  [{ "id": "audio.spectrum", "version": 1 }, { "id": "media.scrubber", "version": 1 }],
      "permissions": ["automation.music", "audio.capture"],
      "actions":     ["togglePlayback", "next", "previous", "seek", "setVolume"]
    }
  ],
  "resources": { "profile": "eventDriven" }
}
```

- **Per-feature declarations:**
  - `sources` wake the plugin;
  - `services` are calls the plugin makes;
  - `components` are tier-2 nodes the plugin shows.
- **Declared means required.** A missing source, service or component disables the feature.
- **`REQUIRES`** keeps only external conditions: app installed or running, and `anyOf` alternatives.
- **`execution`** keeps only `entryPoint`. Mode and trust come from the signature (D4).
- **Build-time validation.** `cascade-addon validate` (to be renamed with D14) runs on every first-party manifest at build time.

## 11. Data flow

**Event to screen.**

```
source (kernel or PluginHost) emits an event
  ▼ kernel, engine thread
coalesce (latest per source) → scheduler → watchdog armed
  ▼ XPC
PluginHost, plugin thread: handle(event) → PluginOutput + thread CPU time
  ▼ XPC
kernel: limits and schema → grants → node table with hashes → diff against previous revision
  → PublicationStore (source of truth) → watchdog disarmed, CPU budget charged
  ▼ one coalesced hop to main
main: NodeStore updates only the changed nodes → SwiftUI invalidates only those views
```

**Why every event goes through the kernel.** Sources that live in PluginHost still send their events through the kernel. This costs one XPC hop per event, well under a millisecond at human frequency. In exchange, coalescing, budget, scheduling and the watchdog live in one place. The watchdog never has to trust PluginHost to report when `handle()` starts and ends.

**The hop to main.** It is a pending flag, not a display link: a hop is queued only if none is pending, and it applies the latest diff. Idle means nothing runs.

**Tap to plugin.** Optimistic node state → `ActionRequest(nodeID, revision)` → broker → scheduler → PluginHost `handle(.action)` → the confirming publication.

**Tier-2 data.** Kernel service → component instance directly, started while at least one instance is visible and stopped with the last.

**Surfaces.** `PublicationSink` delivers each publication by kind to `WidgetHost` and `LiveActivityHost`, which keep their current arbitration. `AddonPresentationBridge` evolves into this sink.

## 12. Architecture and modules

```
                ┌──────────────── CascadeContracts (pure values) ─────────────────┐
                │ manifest v2 · DSL nodes with identity · publication · events · frames │
                └──────────▲──────────────────────────▲──────────────────────────────┘
                           │                          │
      ┌────────────────────┴───┐        ┌─────────────┴─────────────────────────┐
      │ CascadePluginSDK       │        │ CascadePluginEngine (kernel, no UI)    │
      │ PluginProvider (sync)  │        │ registry · broker · supervisor         │
      │ SwiftUI-mirror builder │        │ scheduler · PublicationStore and diff  │
      │ sync clients           │        │ source catalog · executors             │
      └──────────▲─────────────┘        └─────────────▲─────────────────────────┘
                 │                                    │
      ┌──────────┴─────────────┐        ┌─────────────┴─────────────────────────┐
      │ PluginHost (XPC)       │ ◄─XPC─►│ CascadeKit (UI)                        │
      │ first-party plugins    │        │ NodeStore and NodeView · tier-2 registry │
      └────────────────────────┘        │ surfaces: widget · activity · notice     │
                                        └─────────────▲─────────────────────────┘
                                                      │
                                        App: composition root, kernel services,
                                        source implementations, system surfaces
```

- **`CascadeContracts`** (exists, evolves): values only. `ContentNode` is replaced by the DSL v2 nodes.
- **`CascadePluginSDK`** (evolves `CascadeAddonSDK`): `PluginProvider`, the builder and the sync clients. It knows nothing of the kernel.
- **`CascadePluginEngine`** (new, replaces `AddonRuntime`): kernel logic without UI, testable without AppKit.
- **`CascadeKit`** (exists): renderer, tier-2 registry, surfaces.
- **`PluginHost`** (new XPC target inside the app): imports only the SDK and the contracts, so the kernel boundary is enforced at compile time.
- **`CascadePresentation`** dissolves: the builder moves to the SDK and the renderer to CascadeKit. Its file workspace presentation stays with the file shelf, a system surface.

**Protocols.** Each has at least two real implementations; they are injected through `init`.

| Protocol | Implementations |
|---|---|
| `PluginProvider` | The plugins |
| `PluginExecutor` | In-process double, PluginHost, isolated process (later) |
| `PluginTransport` | XPC, in-memory for tests |
| `HealthPolicy` | Real policy, fixed policies for tests |
| `EventSource` | One per catalog entry, plus fakes |
| `NativeComponent` | `audio.spectrum`, `media.scrubber`, `audio.outputPicker` |
| `PublicationSink` | Real surfaces, test sink |

**SDK entry point:**

```swift
public protocol PluginProvider: Sendable {
    /// Runs on the plugin's dedicated thread. Client calls block this thread
    /// with a timeout; returning past the kernel's deadline counts as a hang.
    func handle(_ event: PluginEvent, context: PluginContext) throws -> PluginOutput
}
```

A plugin cannot issue two client calls in parallel. That is acceptable for thin, event-driven plugins.

## 13. Failures

| Failure | Detected by | Reaction |
|---|---|---|
| `handle()` throws | Message outcome | Retry after 1, 5 and 30 s; quarantine after 3 incidents in 5 minutes |
| Hang (deadline exceeded, starting value 250 ms) | Kernel watchdog, armed at dispatch | SIGKILL PluginHost and restart it for the others. The hung plugin stays `disabledAfterHang` until Cascade restarts or the user re-enables it; a second hang quarantines it |
| PluginHost crash | XPC interruption or invalidation | Attributed to the plugin that was inside `handle()`, which the kernel knows because it dispatched the event. It counts as a crash incident for that plugin (retry, then quarantine). PluginHost restarts with 1, 5 and 30 s backoff |
| Crash with nothing in flight | No outstanding dispatch | Attributed to PluginHost. After 3 in 5 minutes it stops restarting and settings show the error |
| Invalid publication | Validation | Rejected; the previous one stays; counts as a moderate incident |
| CPU budget exhausted | Thread CPU time reported with each output, charged to `AddonCPUBudget` | Heavier coalescing, then quarantine on repetition |
| PluginHost RAM past the stop threshold (`ProviderMemoryEpisode`, 64/96 MiB) | Process metrics | Restart PluginHost, without attribution |
| Kernel service unavailable (for example permission denied) | The service | The component shows its unavailable state |

Across every restart, publications stay on screen under their `stalePolicy`. After a Cascade restart nothing is restored from disk: every plugin receives a `refresh` at start and republishes. Settings show each plugin's state: active, disabled after a hang, quarantined.

**Boundary limits per plugin:**
- the `handle()` deadline;
- 64 KiB and about 256 nodes per publication;
- the publication budget;
- the existing asset cap (8 MiB) and storage caps (10 + 20 MiB).

**Per-process limits:** RAM is measured for PluginHost as a whole. A shared process cannot say which plugin holds memory; a suspect plugin can later be isolated in its own process through `PluginExecutor`.

## 14. Testing

1. **Contracts.** Pure unit tests for manifest v2 validation, DSL limits, identity and hashing.
2. **Engine.** In-process executor, in-memory transport, fake sources, fixed `HealthPolicy`, injected clock. Scenarios: coalescing, publication budget, hang and watchdog, crash attribution, grant revocation, optimistic revert.
3. **Renderer.** A diff updates only the changed nodes, verified by counting invalidations through a test hook.
4. **Integration with the real PluginHost over XPC.** Event round trip, SIGKILL on hang, restart after a crash.
5. **Performance.** Zero wakeups while idle, tap to optimistic state within one frame, PluginHost RAM measured. Checked against the hover and RAM budget in §1.
6. **Build.** Manifest validation for every first-party plugin; a boundary check that PluginHost imports only the SDK and the contracts.
7. **Acceptance.** The Music plugin matches today's features with equal or lower CPU and RAM.

## 15. Build approach and migration

**Harvested from the existing runtime:**

| Piece | Kind today | Serves |
|---|---|---|
| `AddonHealthStore` | Value type | `HealthPolicy` |
| `AddonCPUBudget`, `ProviderMemoryEpisode` | Value types | Limits |
| `DeadlineQueue`, `AddonScheduler` | Value types | Scheduler |
| `ServiceBroker` | Actor, logic unwrapped into a value type behind a `Mutex` | Grants and leases |
| `ResourceGovernor`, `AddonKeyedStorage` | Actors, same treatment | Storage and reservations |
| `BoundedAsset*`, asset decoding | Classes and value types | Assets |
| Contract validation, `cascade-addon` | Pure code | Manifest v2 |

**Rewritten:** `ContentNode` (DSL v2 with identity), `ContentRenderer` (`NodeStore` and `NodeView`), the executors and the transport.

**Frozen, then deleted:** `AddonRuntime` and the parts of `CascadeRuntime` that model per-addon process admission, protocol minors 1.1 to 1.4, per-process metrics binding, and archive restore and remapping. They are deleted once the engine replaces them. Whatever external plugins need later is recovered from git history. `FileWorkspaceHost` stays; it serves the file shelf.

**Order after this spec:**
1. Spikes S1 and S2.
2. Raise the deployment floor.
3. Contracts and manifest v2.
4. Engine with the in-process double.
5. Renderer.
6. PluginHost and transport.
7. Clock as the first plugin (the kernel-drawn clock also fixes today's one-second tick).
8. The notices.
9. Layout sub-project.
10. Services and Music sub-project.

## 16. Spikes before implementation

- **S1.** Stop a hung PluginHost while Cascade is alive with SIGKILL on the PID taken from the authenticated XPC connection. Verify that the PID identifies the right incarnation. Cascade is not sandboxed, so it can signal.
- **S2.** Check that TCC attributes PluginHost's Automation and Bluetooth requests to Cascade as the responsible process, and that the service needs its own Apple Events entitlement. A failure moves the affected services to the kernel (§6).

## 17. Documents to update once this spec is approved

- `CLAUDE.md`: deployment floor macOS 15; the plugin layer is the data contract and PluginHost, not `NotchWidget` with `NSHostingView`; lifecycle per §5.
- `CODE_STYLE.md`: the Addon SDK section and the legacy widget contract; the "SDK planned, not implemented" statement.
- `PRODUCT.md`: parity as defined in §10, and the microkernel exception to the test-double-only executor policy.
- `docs/addons/`: renamed and rewritten for the plugin SDK once the contracts exist.

## 18. Out of scope

- Slot layout, pages, long-press rearranging, arbitration policy (layout sub-project).
- The media and spectrum services, the tier-2 component implementations, the Music migration (services and Music sub-project).
- External plugins: launcher, distribution, installation, per-plugin processes. They stay blocked on the existing launcher qualification.
- Plugin-written sources, plugin pages, tier-3 remote scenes.
