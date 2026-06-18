# CODE_STYLE.md

Code style conventions for **Cascade**. Goal: **protocol-oriented, explicit, type-safe** code that reads well, with a clear seam between the *style* rules (which never bend) and the *performance* rules (which let us reach for the unsafe, low-level tools where the always-on overlay demands it).

Cascade is a **standalone macOS app**: a high-performance Dynamic Notch built on **AppKit + Core Animation** for the window, geometry and morph, **SwiftUI** for widget content, and a strict **widget plugin protocol** for modularity. The deployment floor is **macOS 14**. There is an app shell here (unlike a pure library), but the notch engine and the widget layer are designed as if they were libraries — clean contracts, no leaking internals.

## Principles

1. **Protocol-oriented first — and harder than usual.** Depend on abstractions (protocols), never on concrete implementations. Every service / resolver / monitor / engine / renderer / widget has its protocol so callers know only the contract and the app stays testable and mockable. This is the backbone of the whole project: the app depends on `NotchWidget`, not on any concrete widget, and on `ActiveDisplayResolving`, not on a specific screen scraper.
2. **Immutable value models, by default.** Anything that describes state (notch geometry, screen snapshot, widget descriptor) is a value `struct` with `let` properties. The `NotchState` is an `@frozen OptionSet`. Mutable, framework-coupled state belongs to the UI layer (`@Observable`), not to the model.
3. **Performance is a first-class constraint.** Cascade must not devour RAM, CPU or battery, and must never hang — it is always on screen. In the hot geometry / morph / rendering path we deliberately use `@frozen`, compact and aligned structs, contiguous storage, `InlineArray` and `UnsafePointer` for cache-friendly, allocation-free access. This is the **one** place where we trade safety for speed — explicitly, behind a clean API, never leaking the unsafety to callers. See **Performance-critical code**.
4. **No unsafe unwraps in ordinary code.** `!` (force unwrap) and `try!` are forbidden outside the audited performance path. Use `guard let` / `if let`, `??`, or explicit error handling.
5. **Explicit over clever.** Readability comes before one-line tricks — even in the fast path, comment the trick.
6. **Resources are part of the contract.** A widget or a subsystem that wakes the CPU on a timer, blocks the main thread or re-renders without a real input change is a *bug*, not a style nit. The type system and the protocols are shaped to make the cheap path the default one. See **Widget plugin protocol** and **Performance-critical code**.

## File header

Every file opens with the standard Xcode banner: the file name and the product name. The `Created by` line is optional — keep it if it is there, drop it if it is not; don't churn it.

```swift
//
//  NotchShapeLayer.swift
//  Cascade
//
```

## Naming

- **Never use cryptic names. The more explanatory, the better.** A slightly longer name that says what it is always beats a short one that needs a comment.
- Prefer `activeScreen` over `scr`, `notchWidth` over `nw`, `morphProgress` over `mp`. No abbreviations unless they are universal (`url`, `id`, `dpi`, `rgb`).
- Types: `UpperCamelCase`. Members: `lowerCamelCase`.
- Protocols: role name (`ActiveDisplayResolving`, `EventMonitoring`, `NotchRendering`, `WidgetHosting`) or capability suffix (`HardwareNotchDetecting`).
- Concrete implementations: a qualifier that states their nature (`SafeAreaNotchDetector`, `MouseEventMonitor`, `SpringMorphEngine`, `CAShapeLayerNotchRenderer`).
- Booleans read as questions (`isOpen`, `hasHardwareNotch`, `canExpand`, `isSuspended`).

## Comments — Antirez style, in English

Comments are written **in English**, in the style of Salvatore Sanfilippo (antirez): generous, narrative, and focused on the **why**, not the what. A comment that just restates the code is noise; a comment that explains intent, trade-offs and gotchas is gold. This matters doubly in the geometry / morph / rendering code, where the *why* (a control-point layout, a spring constant, a coordinate flip, a memory-layout choice) is rarely obvious from the code alone.

- **Doc comments use `///`, never `/* … */`.** Triple-slash is the standard for every type, function and property worth documenting.
- Put a `///` doc comment above every non-trivial type and function describing what it does, why it exists, and any non-obvious behavior or edge case.
- **Open the doc comment with the symbol's own name as the subject** ("NotchState describes…", "SpringMorphEngine drives…", "WidgetContext hands a widget…") so it reads as a definition.
- Use full English sentences. Explain reasoning, assumptions, and the things that would surprise the next reader.
- In the performance path, **always document the unsafe contract**: who owns the buffer, what the pointer's lifetime is, why the bounds are safe.
- Keep comments in sync with the code. Never leave commented-out code in the repo.

```swift
/// NotchGeometry holds the resolved dimensions of one morph frame.
///
/// The morph is a pure interpolation between a resting geometry (hugging the
/// hardware notch) and an expanded one, so this struct carries no behavior —
/// only the numbers the shape layer turns into a `CGPath`. It is `@frozen`
/// because its layout is stable and the morph loop reads it on every frame;
/// freezing lets the compiler lay it out at compile time and keeps the read
/// cache-friendly.
@frozen
struct NotchGeometry: Equatable {
    // ...
}
```

## Alignment — line things up in columns

**Align in columns wherever possible.** Vertical alignment makes related lines scan as a table and surfaces inconsistencies immediately.

- The colon stays attached to the name (Swift convention), but pad **before** the colon to align the types.
- Align `=` in groups of related assignments.
- Align enum raw values and `OptionSet` members.
- Align trailing comments.
- **This applies to call sites too, not only declarations:** align the argument labels of a multi-line call or initializer.
- **Multi-argument calls and declarations break across lines, paren-on-its-own.** When a function or initializer — at a call site *or* in its declaration — has more than one argument, the **opening parenthesis ends its line**, every argument goes on **its own indented line** (labels aligned in columns), and the **closing parenthesis sits alone** on the final line. Never crowd the first argument onto the call line and hang the rest off it.

```swift
@frozen
struct NotchState: OptionSet {
    let rawValue: UInt8

    static let leading  = NotchState(rawValue: 1 << 0) // Left side expanded.
    static let trailing = NotchState(rawValue: 1 << 1) // Right side expanded.

    static let closed: NotchState = []
    static let open  : NotchState = [.leading, .trailing]
}

enum NotchRegion: String {
    case leading  = "leading"
    case trailing = "trailing"
    case expanded = "expanded"
}

let restingWidth   = 200.0
let expandedWidth  = 640.0
let cornerRadius    = 14.0

// Call sites align their labels the same way — open paren alone, one argument per
// line, close paren alone:
let engine = NotchEngine(
    resolver    : resolver,
    morphEngine : morphEngine,
    renderer    : renderer
)

// Not this — first argument crowded onto the call line, the rest hanging off it:
let engine = NotchEngine(resolver    : resolver,
                         morphEngine : morphEngine,
                         renderer    : renderer)
```

When alignment would fight the compiler or hurt readability (very long lines, generics), readability wins — but reach for columns by default.

## Models

- Value `struct`, immutable (`let`). `Equatable` (and `Hashable` / `Identifiable` where it makes sense) is the norm.
- `NotchState` is an `@frozen OptionSet` (see CLAUDE.md): the sides open independently, so the state is the union of which sides are expanded — not a linear enum.
- **Framework-agnostic at the data level**: a model that only describes data imports nothing from SwiftUI or Combine. Colors that need to be stored are packed ARGB `UInt32`, not `Color`.
- No presentation state (hover, focus, animation progress) in pure data models: that belongs to the UI / state layer.
- The geometry control-point buffers are **not** `Codable` models — they are performance-critical storage (see **Performance-critical code**). Keep the two concepts apart: descriptive models are immutable value types; geometry buffers are compact, contiguous storage.

## Services / Resolvers / Monitors / Engines / Renderers (protocol-oriented)

```swift
/// ActiveDisplayResolving resolves which screen Cascade should follow and
/// whether that screen has a hardware notch. It is a protocol so the engine
/// can be tested against a fake multi-display layout, with no real screens.
protocol ActiveDisplayResolving {

    /// Resolve the screen the overlay should live on right now (mouse /
    /// frontmost window) together with its hardware-notch metrics.
    func resolveActiveDisplay() -> ActiveDisplay
}

final class SafeAreaNotchDetector: ActiveDisplayResolving {
    // Reads NSScreen.safeAreaInsets / auxiliaryTop*Area to detect and measure
    // the cut-out. No polling — driven by the event monitor and screen-change
    // notifications.
}
```

- The protocol is the contract; callers only know the protocol.
- Dependencies are injected through `init`.
- Anything that touches AppKit windows, Core Animation, system events or screen geometry sits behind a protocol so it can be stubbed in tests without a real display or event stream.

## State holders (UI-facing)

This app targets **macOS 14**, so it uses the modern **Observation** framework — not the legacy `ObservableObject`.

- **Use `@Observable`** for state holders the SwiftUI layer reads. Its fine-grained tracking means a view re-renders only when a property it actually reads changes — which is exactly the re-render discipline the project demands.
- State holders that own UI-visible domain state are `final class`, `@MainActor`.
- State that a background context produces (decoded image, loaded data) must be published to the UI **on the main actor** — never let a view observe a value being written from a background queue.
- **Property wrappers go on their own line**, above the declaration — never inline:

```swift
@Observable
@MainActor
final class NotchController {

    private(set) var state        : NotchState     = .closed
    private(set) var activeDisplay : ActiveDisplay?
}

// In a view, prefer plain ownership or @Bindable over re-wrapping:
@State
private var controller = NotchController()
```

## Widget plugin protocol (the strict contract)

The widget layer is the modular heart of Cascade, and the protocol is deliberately severe because a widget is a guest in an **always-on** overlay. The protocol is shaped so the cheap, event-driven path is the only natural one.

```swift
/// NotchWidget is the contract every widget conforms to.
///
/// A widget knows nothing about Cascade's internals: it is registered, placed
/// in a region, and driven entirely through this protocol and the typed
/// `WidgetContext` it is handed. Because the overlay is always on screen, the
/// protocol is strict about resources — a widget that blocks, polls or
/// re-renders without cause is a bug, not a preference.
@MainActor
protocol NotchWidget: AnyObject {

    /// Stable identity used by the registry; never changes at runtime.
    static var identifier: WidgetIdentifier { get }

    /// Where the widget wants to live. The host honors it against `NotchState`.
    var preferredRegion: NotchRegion { get }

    /// Build the SwiftUI content. Called rarely — on activation and on a
    /// declared input change — never on a timer. Must return within a frame.
    func makeContentView() -> AnyView

    /// Activated when the region becomes visible. Acquire resources here and
    /// subscribe to the event sources exposed by the context.
    func activate(in context: WidgetContext)

    /// Suspended when the notch closes or the region hides. Release images,
    /// cancel subscriptions, free buffers. After `suspend()` the widget must
    /// consume zero CPU and only minimal resident RAM.
    func suspend()
}
```

The rules every widget — and the host that loads it — must honor:

- **The main thread is non-negotiable.** `makeContentView()` and `activate(in:)` run on the main actor and must return within a frame budget. Anything heavier (network, decode, parse) runs on a background QoS handed out by the `WidgetContext` and publishes its result back on the main actor.
- **Event-driven only — no polling.** Widgets subscribe to data through the context. `Timer` / `DispatchSourceTimer` polling loops are forbidden; if a widget needs periodic data, it asks the context for a coalesced, host-managed tick that stops when the notch closes.
- **Re-render only on real change.** A widget asks the host for new content (`context.setNeedsContent()`) only when one of its declared inputs changed. `@Observable` provides the granularity; never invalidate on every frame or every tick.
- **Lifecycle equals resources.** `activate(in:)` acquires; `suspend()` releases. A suspended widget is *measurably* idle: no retained images, no live subscriptions, no CPU. The host suspends every widget whose region is not currently in `NotchState`.
- **Isolated and modular.** A widget reaches the outside world only through the typed `WidgetContext`. No singletons, no `NSApp` spelunking, no reaching into the engine. This is what lets a widget be added or removed without touching the notch engine.
- **Frugal by contract.** Compact state, lazy assets, large resources released on `suspend()`. The host may measure a widget and cap or evict one that misbehaves.

## Extensions

- **Only create an extension when it earns its place.** If the code can live directly in the type's own file, put it there. A private helper used only inside `Foo` belongs in `Foo.swift`, not in a separate extension.
- When an extension is justified (cross-cutting additions to types you don't own — Foundation, AppKit, Core Graphics — or helpers shared by several files), give it its own file.
- One file per extended type and capability, named `Type+Capability.swift`. The `+` makes it obvious what the file adds: `CGPath+Notch.swift`, `NSScreen+HardwareNotch.swift`.
- Do not pile unrelated helpers into one giant `NSScreen+Extensions.swift`: split by capability.

## Concurrency — three strictly separated contexts

The app's smoothness depends on keeping three classes of work apart. Mixing them causes hangs, dropped frames or battery drain.

1. **Compositor / WindowServer (system-owned, real-time).** We feed it layer changes inside a `CATransaction`. **Never** stall the commit with disk reads, allocation, locks or heavy compute — anything that blocks shows up as a dropped frame.
2. **Main thread / main actor (interactive, 120 Hz).** SwiftUI, AppKit, the `NSPanel`, event monitoring, the `CADisplayLink` morph callback. Handles user input, positioning and the morph only. Use `@MainActor` for anything UI-visible. A hang here freezes the overlay.
3. **Background worker (utility / background QoS).** `Task.detached` or a dedicated `DispatchQueue`: widget data loading, image decode, geometry / persistence caches.

Rules:

- `async`/`await` for asynchronous work; no completion handlers in new code.
- Heavy work (decode, IO, parse) stays off the main actor and never stalls the compositor.
- Cross the actor boundary explicitly when handing a finished result back to the UI; do not let observation reach into background-mutated state.
- Widgets obey all three rules — the `WidgetContext` is the only sanctioned way for a widget to do background work.

## Performance-critical code (the fast path)

This is the part that justifies the careful style. Treat it as a small, audited blast radius where the normal "no unsafe" rule is relaxed *on purpose* and *visibly*.

- **`@frozen` on hot structs** the compiler benefits from laying out at compile time (`NotchGeometry`, `NotchState`, control points). It enables cache hits and a stable layout; only freeze what is genuinely stable across the app's evolution.
- **Compact, aligned, contiguous storage.** Prefer parallel arrays / `ContiguousArray` / raw buffers over arrays-of-structs when the morph loop or the renderer walks them with unit stride. Keep structs small and field order chosen for alignment.
- **`InlineArray` for fixed-size control-point buffers.** The notch outline has a known, fixed number of control points, so an `InlineArray` keeps them on the stack with no heap allocation and no ARC. It is **Swift 6.2 stdlib**, and its runtime ships with the newest OS — on the macOS 14 floor it must be gated:

```swift
/// Build the morph control points. On macOS 26+ we use a stack-resident
/// InlineArray (zero heap, zero ARC); below that we fall back to a
/// reserve-capacity ContiguousArray, which still avoids re-growth.
@available(macOS 26, *)
@inline(__always)
func controlPoints(for geometry: NotchGeometry) -> InlineArray<8, CGPoint> {
    // ...
}
```

- **`UnsafePointer` / `UnsafeMutablePointer`** for building the `CGPath` in the morph loop, where bounds checks and ARC retain/release would dominate. Every use must:
  - be wrapped behind a safe API so callers never see a raw pointer,
  - document the buffer's owner and lifetime in a `///` comment,
  - guarantee the bounds before entering the unsafe region.
- **Do not allocate in the `CADisplayLink` callback**, and avoid per-frame allocation in the morph loop generally. The spring integrator is pure value math on the stack.
- **Renderer:** update the `path` of a `CAShapeLayer` instead of overriding `draw(_:)`, so the GPU does the rasterization. The morph runs on its own layer; opening one side must never trigger a recompute of unrelated layers. Target 120 Hz or better.
- **Widgets pay rent in the budget too.** A widget's main-actor entry points are frame-bounded; anything slower is a contract violation (see **Widget plugin protocol**).
- When you optimize, **say what you traded and why** in a comment. An unexplained `UnsafeMutablePointer` is a future bug.

## Error handling

- Errors are modeled with dedicated, descriptive types (`enum … : Error`).
- `throws` for propagatable failures; `Result` only where the API requires it.
- Never swallow an error silently: handle it or propagate it. Log through a single logging seam (`os.Logger`).

## File organization and access control

- One main type per file; file name = type name. The file opens with the header banner (see **File header**).
- `private` / `fileprivate` for everything that is not part of the public contract.
- The **widget SDK surface** (`NotchWidget`, `WidgetContext`, `NotchRegion`, identifiers) is the deliberately-public seam — mark it `public` on purpose and keep it small and stable, so widget authors depend on a clean contract.
- `private(set)` for read-only exposed state.
- Use extensions to separate protocol conformances (`extension Foo: SomeProtocol { … }`) — kept in the type's own file unless the Extensions rule above applies.
- `// MARK: -` to separate sections of a long file.

## Formatting

- 4-space indentation.
- Lines roughly <= 100–120 characters.
- One declaration per line; spaces around operators.
- Property wrappers on their own line (see **State holders**).
- No commented-out code left in the repo.
- **One modifier per line.** Don't chain view / builder modifiers on a single line — give each `.modifier(…)` its own line. `Image(...).font(...).foregroundStyle(...)` becomes three lines.
- **Favor vertical breathing room over dense packing.** Separate sibling views and distinct logical groups with a blank line, and break a call's arguments onto their own lines (see **Alignment**) instead of packing them across. When in doubt, give it *more* room. The code should breathe, not cram.

```swift
VStack(spacing: 8) {

    Image(systemName: "bell.badge")
        .font(.headline)
        .foregroundStyle(.secondary)

    Text("No active widgets.")
        .foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```
