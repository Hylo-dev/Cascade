# CLAUDE.md

Instructions for Claude when working on this project.

## Context

**Cascade** is a **standalone macOS app**: a **high-performance Dynamic Notch**. It renders a Dynamic-Island-style overlay anchored to the top-center of the *active* display. Collapsed, it hugs the MacBook's hardware notch; on hover or trigger it **morphs** — with a spring animation at the display's native refresh (120 Hz on ProMotion) — into an expanded surface that hosts modular widgets. It follows the active display across monitors and **persists across every Space / desktop**.

Cascade is an always-resident overlay, not a window the user opens. Where a hardware notch exists it draws the notch chrome flush against it; where it does not (external displays) it **draws nothing but keeps the interactive zone alive** at top-center, so the gestures still work.

It is an *app*, but it is built around two clean internal seams: a **reusable notch engine** (window, positioning, geometry, morph) and a **plugin layer**. The plugin layer is a data contract, not a view protocol: a plugin declares itself in a manifest and publishes declarative documents, and Cascade is the kernel that validates, keeps and draws them. First-party plugins run outside Cascade, in the bundled **PluginHost** XPC service, so a plugin that crashes or hangs costs a PluginHost restart, never the notch. Treat both seams as if they were libraries: clean contracts, no leaking internals. The decisions behind the plugin layer are in the [plugin engine spec](docs/superpowers/specs/2026-09-29-plugin-engine-design.md); the developer pages are in [`docs/plugins/`](docs/plugins/README.md).

**Hard constraint that shapes every decision: Cascade must not devour RAM, CPU or battery, and must never hang.** It sits on screen all day; a single wasteful timer, an over-eager re-render or a blocked main thread is felt immediately. When two designs are both correct, pick the one that allocates less, copies less, wakes the CPU less and stays off the hot path.

The whole codebase is **protocol-oriented (POP) first** — see `CODE_STYLE.md` for the full conventions.

## The mental model (the hardware notch & the active display)

To place an overlay where the hardware notch is, you need to know how macOS describes screens:

- **Hardware notch** — only the built-in display of recent MacBooks has one. Detect it with `NSScreen.safeAreaInsets.top > 0`, and measure the cut-out from `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` (the usable strips beside the notch). The gap between those two strips is the notch width.
- **Active display** — the screen Cascade should follow. It is the screen under the mouse, or the one owning the frontmost window. On a multi-monitor setup this changes as the user moves around.
- **Top-center anchoring** — the panel's X origin is `screen.frame.midX - notchWidth / 2`; its Y sits flush with the top of the screen. AppKit's coordinate space is bottom-left origin — mind the flip when computing the top edge.
- **Chrome vs. interactive zone** — these are *decoupled*. The interactive zone (the hit-tested band at top-center) always exists, on every active display. The drawn chrome (the black notch shape) is rendered *only* where a hardware notch is present.

## State model — `NotchState` as an `OptionSet`

The notch is not a linear enum of modes; its sides open **independently**, like a Dynamic Island. We model it as an `OptionSet` so the state is the *union* of which sides are expanded:

```swift
/// NotchState describes which sides of the notch are currently expanded.
///
/// It is an OptionSet, not a plain enum, because the leading and trailing
/// sides open independently: a widget can claim the left while the right
/// stays shut. `.closed` is the empty set, so "is anything open?" is one
/// `isEmpty` check; `.open` composes both side bits.
@frozen
struct NotchState: OptionSet {
    let rawValue: UInt8

    static let leading  = NotchState(rawValue: 1 << 0) // Left side expanded.
    static let trailing = NotchState(rawValue: 1 << 1) // Right side expanded.

    static let closed: NotchState = []                 // Resting, hugging the notch.
    static let open  : NotchState = [.leading, .trailing]
}
```

The renderer reads the set to decide how far each side morphs. Plugins never see it: visibility is decided per surface, and opening or closing the notch wakes no plugin (see *Plugin contract*).

## Geometry → screen mapping (the math core)

The morph is one interpolation between two geometries, driven by a normalized progress `t ∈ [0, 1]` per side.

- **Resting size** — the collapsed notch matches the hardware cut-out (or a default band on displays without one).
- **Expanded size** — the target dimensions for `.leading` / `.trailing` / `.open`.
- **Interpolation** — `value = rest + (expanded - rest) * easedSpring(t)`.
- **Corner radii** — the top corners stay tight to the screen edge; the bottom corners round out as the notch grows.

## Stack & responsibilities

### Low level (AppKit / Core Animation / Core Graphics)

- **`NSPanel`** (nonactivating, borderless) — the overlay window. `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, a window level above the menu bar, never key or main so it never steals focus. This is what makes it persist across Spaces.
- **Active-display resolver** — resolves the active screen (mouse / frontmost window) and detects the hardware notch via `safeAreaInsets`. Behind a protocol so it is stubbable. **Coalesced:** it repositions the panel only when the *resolved target screen changes*, never on every mouse delta.
- **Notch shape layer (`CAShapeLayer`)** — the morphing outline. Its `path` is rebuilt from a fixed set of control points and the GPU rasterizes it. We update `path`; we never override `draw(_:)`.
- **Morph engine (`CADisplayLink` + spring)** — a tiny per-frame spring integrator drives the morph at the screen's native refresh. It updates layer geometry only and **allocates nothing per frame**.
- **Event monitoring** — `NSEvent` monitors (mouse moved, throttled; enter / exit on the interactive zone) plus `NSWorkspace` activation notifications. Behind a protocol; throttled *before* it reaches the state machine.

### High level (SwiftUI)

- **Plugin content** is drawn by the kernel, never supplied as views. `PluginNodeStore` keeps one `@Observable` `PluginNodeModel` per node of a publication, and the nominal, recursive `PluginNodeView` and `PluginDocumentView` draw them inside the notch's fixed `NSHostingView`s. A new publication touches only the models of the nodes its diff names.
- **System surfaces** (the file shelf) and Music, until its own sub-project moves it to a plugin, are native SwiftUI hosted the same way.
- **State** lives in `@Observable` holders on the main actor (Observation framework): the `NotchState`, the active screen, the resolved geometry. Observation's fine-grained tracking means a side opening only invalidates the views that actually read that side.

### Plugin layer (the modular surface)

- A plugin conforms to **`PluginProvider`** (`CascadePluginSDK`): one synchronous `handle(_:context:)` that answers a `PluginEvent` with a `PluginOutput` of publications. It knows *nothing* about Cascade's internals and, of Cascade's modules, imports only `CascadePluginSDK` and `CascadeContracts`.
- Every plugin is declared by a **manifest v2** (`PluginManifest`): its features, the surfaces each one fills (widget, activity, notice), the catalog sources that wake it, the tier-2 components it shows, its permissions and its actions. The first-party plugins are listed in `FirstPartyPlugins` (`CascadePlugins`), their manifests bundled beside them as JSON: Battery and Clock (widgets), and the Bluetooth, Charging and Volume alerts (notices).
- `NotchWidget`, `NotchLiveActivity`, `NotchTransientNotice` and `NotchContextualPage` are CascadeKit's internal host seams, not the plugin contract. Only kernel adapters (`PluginWidget`, `PluginNotice`) and system surfaces implement them.
- Still pending: Music as a plugin with its media and spectrum services (the services and Music sub-project), slot pages and arbitration (the layout sub-project), external plugins, and the storage, assets and services pipelines.
- The contract is **severe about resources**: see *Plugin contract* below and the Plugin SDK section of `CODE_STYLE.md`.

### Layout & memory (the fast path)

- `@frozen`, compact and alignment-friendly structs for geometry (`NotchGeometry`, control points).
- `InlineArray` for the fixed-size control-point buffers — stack-allocated, no heap. *Availability-gated*, see *Performance & platform rules*.
- `UnsafePointer` / `UnsafeMutablePointer` when building the `CGPath` inside the morph loop, behind a safe API and documented.

## Thread architecture: strictly separated contexts

Mixing these causes hangs, dropped frames or battery drain. They are non-negotiable:

1. **Compositor / WindowServer (system-owned, *sacred*).** We hand it layer changes inside a `CATransaction`; we **never** stall the commit with heavy work. This is Cascade's analog of an audio render thread: owned by the system, never blocked by us.
2. **Main thread / main actor (interactive, 120 Hz).** Owns the `NSPanel`, positioning, event monitoring, the `CADisplayLink` morph callback and the SwiftUI content. It must stay responsive: **no disk IO, no heavy compute, no blocking** here, ever. A hang here freezes the whole overlay. Its only plugin work is applying the kernel's diffs: `PluginSurfaceRelay` queues a hop to main only when none is pending, so a burst of publications costs one hop, and main never waits on a contended lock.
3. **Background worker (utility / background QoS).** `Task.detached` or a dedicated `DispatchQueue`: loading data, decoding images, building geometry / persistence caches. Results cross back to the main actor explicitly.

The plugin engine adds three contexts of its own (spec §3):

4. **Engine queue (kernel).** `PluginEngine`'s serial queue runs validation, normalization and diff, the broker, the supervisor and the scheduler, deciding under one `Mutex` around the value-type `PluginKernel`. Callers hop onto it and never wait on its lock.
5. **XPC.** Receives PluginHost's answers and source states and hands them to the engine queue.
6. **PluginHost, one thread per plugin.** `PluginRunner` gives each plugin its own serial queue, so `handle()` runs on one thread at a time and that thread's CPU time is the plugin's CPU time.

Plugin code never runs on Cascade's main thread, nor in Cascade at all except through `InProcessExecutor`, the test and development double. `handle()` must return within 250 ms, or the kernel's watchdog counts a hang and kills PluginHost; its CPU time is charged to `PluginCPUBudget`, so a plugin that runs too often or too long is held back and then quarantined instead of being felt by the notch.

## Execution pipeline (the data flow)

```
[Active display changes / mouse moves / app activates]
         │ (main actor, event monitor, coalesced + throttled)
         ▼
[Active-display resolver]     → resolve active screen + detect hardware notch (safeAreaInsets)
         │
         ▼ (reposition only if the target screen changed)
[NSPanel]                     → move to top-center; draw chrome only if a notch exists
         │
         ▼ (hover / trigger on the interactive zone)
[NotchState (@Observable)]    → closed ↔ leading / trailing / open   (OptionSet)
         │
         ▼ (CADisplayLink, native refresh, allocation-free)
[Morph engine + CAShapeLayer] → interpolate geometry → update layer path / transform
         │
         ▼ (surfaces that become visible)
[Surfaces]                    → draw the kernel's last publications; a stale one asks for one refresh
```

A plugin's content takes its own path, which never starts from the notch opening:

```
[A source changes / a wake comes due / the user touches a control]
         │ (engine queue: coalesce to the latest state, budgets, scheduler, watchdog armed)
         ▼ XPC
[PluginHost, plugin thread]   → handle(event) → PluginOutput + the thread's CPU time
         │ XPC
         ▼ (engine queue)
[Kernel]                      → limits and schema → grants → node table and hashes → diff
         │
         ▼
[PluginPublicationStore]      → the source of truth; outlives the plugin and PluginHost
         │
         ▼ (one coalesced hop to main)
[PluginNodeStore]             → update only the changed nodes → SwiftUI redraws only their views
```

## Plugin contract (resources are sacred)

A plugin is a guest in an always-on overlay, so the contract is deliberately strict. The detailed rules live in the [plugin pages](docs/plugins/README.md) and the Plugin SDK section of `CODE_STYLE.md`; the principles:

- **Data, never views.** A plugin emits `PluginDocument`s written with the SDK's SwiftUI-mirror builder, and the kernel validates and draws them. A document holds at most 64 KiB, 256 nodes, depth 12 and 16 modifiers per node, and an output at most 48 publications. A document that breaks a limit is rejected whole, and the previous one stays on screen.
- **Never block.** `handle()` is synchronous on the plugin's own thread in PluginHost and returns within 250 ms. Anything slower is a hang, not a slow plugin.
- **Event-driven, no polling.** A plugin wakes only for a `refresh`, the latest state of a source its manifest declares, the `wake` it asked for in its last output (never sooner than a second away), or a user action. Sources come from the host catalog: always-armed listeners that cost nothing while they wait, leased while the plugin is enabled and needs them, even before anything is on screen. Events coalesce to the latest state per source, never a backlog. A plugin that needs a cadence asks for a wake.
- **Nothing on open or close.** Work, presentation and visibility are separate lives (spec §5). PluginHost stays alive and idle while nothing changes; publications live in the kernel and stay on screen across a PluginHost restart; visibility is decided per surface, so the compact activity, once activities are routed, stays visible while the notch is closed. The kernel never tells a plugin that the notch opened or closed: when a surface becomes visible with content older than its `staleAfter`, the plugin gets one `refresh`.
- **The kernel draws time.** Clocks, timers and time-driven progress (`Clock()`, `Today()`, `Text(_:style:)`, `Text(timerInterval:)`, `ProgressView(timerInterval:)`) are drawn and kept current by the kernel and cost the plugin nothing while they tick.
- **Budgets.** Publications: a burst of eight, then one every 250 ms (33 ms for notices); the excess is held and coalesced, not dropped. CPU: a 100 ms burst refilled at 5 ms per second. Memory: PluginHost is measured as a whole and restarted past 96 MiB, blaming no plugin.
- **Failures stay contained.** A throw retries after 1, 5 and 30 s, and the fourth incident in five minutes quarantines. A hang kills PluginHost and leaves the plugin disabled until the user re-enables it or Cascade restarts; a second hang quarantines it. PluginHost is given up on after three idle crashes or memory kills, in any mix, within five minutes. Settings (Widget page, Plugins section) show each plugin's state with Re-enable, and PluginHost's with Restart.
- **Declared means required, undeclared is denied.** Every manifest declares everything, first-party included. Parity means no private code path: only the default approver differs between bundled and external plugins.

## Code style (see CODE_STYLE.md for the full rules)

- **Protocol-oriented first.** Every subsystem is a protocol: the resolver, the event monitor, the morph engine, the renderer, and the engine seams `PluginProvider`, `PluginExecutor`, `PluginTransport`, `PluginHealthPolicy`, `PluginEventSource` and `PluginPublicationSink`. Callers depend on the contract and concretes are injected via `init`, so the engine depends on `PluginExecutor`, not on PluginHost, and runs its tests on an in-process double.
- **Comments: Antirez style, in English.** Narrative `///` doc comments about the *why*, the trade-offs and the gotchas; document the unsafe contract in the fast path. Never `/* … */`, never commented-out code.
- **Names: always explicit, never cryptic.** Column alignment everywhere; multi-argument calls and declarations break with the opening paren on its own line.
- **Immutable value models.** Presentation state stays in the `@Observable` UI layer, not in the data models.
- **One modifier per line** in SwiftUI; property wrappers on their own line.

## Performance & platform rules (important)

- **Do not devour RAM, CPU or battery, and never hang.** This is why the app must be careful: it is always on screen. Prefer the design that allocates less and wakes the CPU less.
- **Deployment floor is macOS 15 (Sequoia).** State holders use **`@Observable`** (Observation framework), and shared state that crosses threads can use `Mutex` and `Atomic` from Synchronization. `async`/`await`, `actor`, `TaskGroup`, `@MainActor` are all fine outside the plugin engine, which avoids actors by design. Before proposing an API, check it exists on macOS 15 and flag it if not.
- **Plugin engine concurrency (spec §3).** One `Mutex` per state owner, no actors in `CascadePluginEngine`, `CascadePluginHost`, `CascadePluginSDK` or `CascadePlugins`. Never call out while holding a lock (no callback, XPC send or plugin code): decide, copy, release, then call. Block only on threads the engine owns, never on the main thread or the Swift concurrency pool. One `DispatchSourceTimer` covers the kernel's watchdogs, retries, held events and wakes, and is disarmed when nothing is due: no `Task.sleep`, no per-object timers. The app and CascadeKit default to MainActor isolation, so their code that the engine calls off main is explicitly `nonisolated`: a MainActor-isolated callback that runs off main traps.
- **`InlineArray` is Swift 6.2 stdlib.** Its runtime ships with the newest OS, so on a macOS 15 floor it must be gated behind `@available(macOS 26, *)` with a fixed-capacity fallback (a small tuple or a `reserveCapacity`'d `ContiguousArray`). Keep its use inside the fast path and behind the gate.
- **The compositor is sacred.** Never stall the `CATransaction` commit; never do per-frame heavy work or allocation in the `CADisplayLink` callback.
- **The fast path is a small, audited blast radius.** `@frozen`, contiguous storage and `UnsafePointer` are allowed there *on purpose*, wrapped behind safe APIs and documented. Everywhere else the normal safety rules hold.
- **Renderer:** update `CAShapeLayer.path`, not `draw(_:)`. The morph runs on its own layer; opening a side must not recompute unrelated layers. Target 120 Hz or better.
- **Plugins pay rent.** Hold every plugin to the plugin contract above; reject a plugin design that polls, blocks, re-renders without cause or needs something its manifest does not declare. Native system surfaces follow the same resource rules.
- Prefer the system frameworks (AppKit, Core Animation, Core Graphics) before reaching for a dependency; justify any dependency you do add.

## How to respond

- **Always respond in Italian**, even though the repository docs and code comments are in English.
- Be concise and direct.
- When proposing a solution, state your assumptions and flag the trade-offs — especially the **memory / CPU / battery / hang** and **threading** trade-offs.
- If a request would block the main thread, stall the compositor, wake the CPU needlessly or bloat memory, say so **before** writing code.
- Do not introduce external dependencies without justifying them and preferring the native frameworks.
