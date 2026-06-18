# CLAUDE.md

Instructions for Claude when working on this project.

## Context

**Cascade** is a **standalone macOS app**: a **high-performance Dynamic Notch**. It renders a Dynamic-Island-style overlay anchored to the top-center of the *active* display. Collapsed, it hugs the MacBook's hardware notch; on hover or trigger it **morphs** — with a spring animation at the display's native refresh (120 Hz on ProMotion) — into an expanded surface that hosts modular widgets. It follows the active display across monitors and **persists across every Space / desktop**.

Cascade is an always-resident overlay, not a window the user opens. Where a hardware notch exists it draws the notch chrome flush against it; where it does not (external displays) it **draws nothing but keeps the interactive zone alive** at top-center, so the gestures still work.

It is an *app*, but it is built around two clean internal seams: a **reusable notch engine** (window, positioning, geometry, morph) and a **widget plugin layer** (a strict protocol contract that lets widgets live without being welded to the app). Treat both seams as if they were libraries — clean contracts, no leaking internals.

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

The renderer reads the set to decide how far each side morphs; the widget layer reads it to decide which regions are live.

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

- **Widget content** is rendered with SwiftUI, hosted inside the expanded notch via `NSHostingView`.
- **State** lives in `@Observable` holders on the main actor (Observation framework, macOS 14): the `NotchState`, the active screen, the resolved geometry. Observation's fine-grained tracking means a side opening only invalidates the views that actually read that side.

### Widget plugin layer (the modular surface)

- Widgets conform to a **`NotchWidget` protocol** and know *nothing* about Cascade's internals. They are registered, placed in a region (leading / trailing / expanded) and driven entirely through the protocol.
- The contract is **severe about resources** — see *Widget plugin contract* below and the dedicated section in `CODE_STYLE.md`.

### Layout & memory (the fast path)

- `@frozen`, compact and alignment-friendly structs for geometry (`NotchGeometry`, control points).
- `InlineArray` for the fixed-size control-point buffers — stack-allocated, no heap. *Availability-gated*, see *Performance & platform rules*.
- `UnsafePointer` / `UnsafeMutablePointer` when building the `CGPath` inside the morph loop, behind a safe API and documented.

## Thread architecture — three strictly separated contexts

Mixing these causes hangs, dropped frames or battery drain. They are non-negotiable:

1. **Compositor / WindowServer (system-owned, *sacred*).** We hand it layer changes inside a `CATransaction`; we **never** stall the commit with heavy work. This is Cascade's analog of an audio render thread: owned by the system, never blocked by us.
2. **Main thread / main actor (interactive, 120 Hz).** Owns the `NSPanel`, positioning, event monitoring, the `CADisplayLink` morph callback and the SwiftUI content. It must stay responsive — **no disk IO, no heavy compute, no blocking** here, ever. A hang here freezes the whole overlay.
3. **Background worker (utility / background QoS).** `Task.detached` or a dedicated `DispatchQueue`: loading widget data, decoding images, building geometry / persistence caches. Results cross back to the main actor explicitly.

Widgets obey the same rules: a widget that blocks the main thread is a bug in the widget, and the host resource budget exists to make that impossible to do silently.

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
         ▼ (only for the sides that are open)
[Widgets via NSHostingView]   → reactive SwiftUI, driven through the NotchWidget protocol
```

## Widget plugin contract (resources are sacred)

A widget is a guest in an always-on overlay, so the protocol is deliberately strict. The detailed rules and the protocol shape live in `CODE_STYLE.md`; the principles:

- **Never block the main thread.** Widget entry points called on the main actor must return within a frame budget. Anything slower runs on a background QoS and publishes its result back.
- **Re-render only on real change.** No continuous invalidation, no "redraw every tick". A widget declares its inputs and asks for new content only when one of them changes.
- **No polling, no idle timers.** Widgets are *event-driven*. A widget that wakes the CPU while the notch is closed is broken by definition.
- **Lifecycle = resources.** Widgets are activated when their region becomes visible and **suspended when the notch closes**, releasing images and buffers. A suspended widget consumes zero CPU and minimal RAM.
- **Frugal by contract.** Compact state, no retained megabytes. The host can measure and cap a misbehaving widget.
- **Isolated & modular.** A widget talks to the host only through the protocol's typed context — it never reaches into app internals — so it can be added or removed without touching the engine.

## Code style (see CODE_STYLE.md for the full rules)

- **Protocol-oriented first.** Every subsystem — resolver, event monitor, morph engine, renderer, widget — is a protocol; callers depend on the contract and concretes are injected via `init`. This is the backbone of the widget plugin system.
- **Comments: Antirez style, in English.** Narrative `///` doc comments about the *why*, the trade-offs and the gotchas; document the unsafe contract in the fast path. Never `/* … */`, never commented-out code.
- **Names: always explicit, never cryptic.** Column alignment everywhere; multi-argument calls and declarations break with the opening paren on its own line.
- **Immutable value models.** Presentation state stays in the `@Observable` UI layer, not in the data models.
- **One modifier per line** in SwiftUI; property wrappers on their own line.

## Performance & platform rules (important)

- **Do not devour RAM, CPU or battery, and never hang.** This is why the app must be careful: it is always on screen. Prefer the design that allocates less and wakes the CPU less.
- **Deployment floor is macOS 14 (Sonoma).** State holders use **`@Observable`** (Observation framework). `async`/`await`, `actor`, `TaskGroup`, `@MainActor` are all fine. Before proposing an API, check it exists on macOS 14 and flag it if not.
- **`InlineArray` is Swift 6.2 stdlib.** Its runtime ships with the newest OS, so on a macOS 14 floor it must be gated behind `@available(macOS 26, *)` with a fixed-capacity fallback (a small tuple or a `reserveCapacity`'d `ContiguousArray`). Keep its use inside the fast path and behind the gate.
- **The compositor is sacred.** Never stall the `CATransaction` commit; never do per-frame heavy work or allocation in the `CADisplayLink` callback.
- **The fast path is a small, audited blast radius.** `@frozen`, contiguous storage and `UnsafePointer` are allowed there *on purpose*, wrapped behind safe APIs and documented. Everywhere else the normal safety rules hold.
- **Renderer:** update `CAShapeLayer.path`, not `draw(_:)`. The morph runs on its own layer; opening a side must not recompute unrelated layers. Target 120 Hz or better.
- **Widgets pay rent.** Hold every widget to the resource contract above; reject a widget design that polls, blocks or re-renders without cause.
- Prefer the system frameworks (AppKit, Core Animation, Core Graphics) before reaching for a dependency; justify any dependency you do add.

## How to respond

- **Always respond in Italian**, even though the repository docs and code comments are in English.
- Be concise and direct.
- When proposing a solution, state your assumptions and flag the trade-offs — especially the **memory / CPU / battery / hang** and **threading** trade-offs.
- If a request would block the main thread, stall the compositor, wake the CPU needlessly or bloat memory, say so **before** writing code.
- Do not introduce external dependencies without justifying them and preferring the native frameworks.
