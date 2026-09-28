# Launcher and authenticated transport: continuation of 24 September 2026

**Verdict: item 1 still blocked, no production launcher enabled.** The request to proceed resumes the technical work; it keeps the decision not to accept orphaned managed processes. This report records new checks of the APIs and of the wiring into the runtime. It is neither an approved specification of a new launcher nor a native probe.

**Later update:** the user then authorized a [separate native XPC probe](../../superpowers/verification/2026-09-24-addon-xpc-lifetime.md), now concluded. Client exit terminates the blocked service in the observed runs; cancelling the connection while the client is alive does not terminate it within the two seconds measured. The text below keeps the context of the earlier research. The launcher remains not qualified.

## Two distinct problems

1. Owning the process lifetime from creation, even if the supervisor dies before `main` or before the tracing attach; stopping noncooperative work and observing the exit of the exact process.
2. Authenticating the sender of messages and binding messages to the incarnation, the version and the grants admitted by the runtime, with effective limits and revocation.

A positive result on the second problem does not settle the first. The [decision in force](../../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) must not be reopened to repeat an exception request already refused.

## New results and their limits

### Suspended spawn

The [separate examination of spawn, exec and fork](2026-09-24-spawn-managed-lifetime.md) compares the public SDK and XNU sources pinned to a revision. `POSIX_SPAWN_START_SUSPENDED` does not constitute an exit constraint on parent death. `SETEXEC` does not add that constraint, and a model based on inheritance of tracing through fork is not qualified. No probe is introduced that intentionally leaves a process suspended, relying on the parent alone to clean it up.

### Client-bound XPC service: a lead distinct from SMAppService

Apple's [XPC overview](https://developer.apple.com/documentation/xpc) describes the application XPC service as tied to the client's lifetime, with the service exiting on client death. This is a positive indication distinct from the persistence of LaunchAgent/LaunchDaemon registered through ServiceManagement. The earlier negative result on `launchd`/SMAppService does not prove that every XPC service has the same limit.

What remains to be established is coverage of launch before the first message, explicit stop while Cascade stays open, and authoritative observation of exit. Connection cancellation is asynchronous and does not interrupt a handler already running: it is not a process termination API. Local source: `xpc/connection.h`, lines 585–612, in the Xcode-beta macOS SDK; [Apple API](https://developer.apple.com/documentation/xpc/xpc_connection_cancel(_:)).

The SDK's public `xpcservice.plist(5)` manual describes discovery of services embedded in the app and in the frameworks it uses. It is not a specification for registering an arbitrary `.xpc` installed after Cascade was signed. This survey did not identify a documented path that combines packages from external publishers, no addon code in the graphical process, per-owner isolation and managed lifetime. A fixed service embedded in Cascade would not by itself demonstrate parity with external addons. Source: SDK `usr/share/man/man5/xpcservice.plist.5`, lines 16–39; [Apple bundle structure](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).

The XPC lead remains **not qualified**, not demonstrated impossible. It is not turned into a production adapter on the basis of the general description of lifetime alone.

### ExtensionFoundation does not offer an already demonstrated fix

The public `AppExtensionProcess` interface in the SDK examined exposes `invalidate`, creation of connections/sessions and interruption callbacks, without a distinct public forced-stop operation. The [invalidate documentation](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()) describes termination at the last connection. The [earlier local fixture](../../superpowers/verification/2026-09-09-addon-runtime-P0.md), however, keeps the real failure with a noncooperative worker even after invalidation of both channels and release of the references. That result is not reclassified as PASS, and the same probe is not repeated without a new verifiable hypothesis.

### XPC authentication: checking received messages

The SDK exposes `xpc_connection_set_peer_code_signing_requirement` since macOS 12, so without raising Cascade's compiled minimum. The requirement is checked on **received** messages. It does not guarantee that an outgoing message is not delivered to an unauthorized peer. [Apple's DTS interpretation](https://developer.apple.com/forums/thread/837286) confirms this distinction; `xpc/connection.h`, lines 772–803, documents its behavior. The [DTS authentication guide](https://developer.apple.com/forums/thread/681053) recommends the public code-signing requirement APIs and, for C XPC messages, `SecCodeCreateWithXPCMessage`.

Consequence for C1: do not send grants, private data or commands with side effects as the first message on the assumption that the peer check also protects sending. The bootstrap must have non-sensitive content; before admission, a complete strategy is needed that binds the authorized destination also against replacement, exec and endpoint transfer. A simple authenticated initial greeting does not prove that later sends keep the same destination. This report neither chooses nor invents a new cryptographic protocol to fill the gap.

## Actual wiring into the code

The MCP graph does not contain the Cascade project; the filesystem fallback was used.

- [`AddonRuntimeTransport.swift`](../../../CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift) still explicitly declares the absence of a production conformer of `AddonRuntimeAdapter`.
- The current adapter has a synchronous, bounded handoff, ingress with exclusive ownership, receipt and physical release. Storage, assets, invocations and subscriptions share the capacity. The old `send(event) async -> output` draft is not enough to represent the current contract.
- [`Package.swift`](../../../CascadeKit/Package.swift) contains no native transport target. [`CascadeServices.start`](../../../Cascade/CascadeServices.swift) still registers `ClockWidget` directly.
- The [C1 plan](../../superpowers/plans/2026-09-10-addon-runtime-completion.md) requires C0 to be admitted for the real adapter. Adding a simulated conformer or another launcher lacking lifetime control does not satisfy this prerequisite.

## Concrete condition for resuming implementation

What is needed is a documented public mechanism or a new demonstrable architecture that combines:

1. lifetime ownership from process creation, without a late attach;
2. stop of the exact process while the host lives, with proof of its exit;
3. preservation of sandbox, signing and per-owner identity;
4. support for external packages without loading their code into the graphical process;
5. authenticated admission and bounded capacity compatible with the current adapter.

The first proposal that satisfies these points must be turned into a finite, reviewable signed experiment, then measured. Repeating parsers, simulators, EOF probes or the invalidation that already failed would not resolve the prerequisite.

### Technical question ready for Apple DTS: not sent

> We are building a macOS 14+ host for separately signed native addon packages. Addon code must remain outside the GUI process, with App Sandbox and Hardened Runtime preserved. We require managed-process cleanup after host or supervisor death, including startup before main, plus explicit termination of an unresponsive addon while the host remains alive. We distinguish IPC invalidation and a signal request from observed process exit. Direct-child spawn leaves a pre-attachment lifetime gap; the current local ExtensionFoundation fixture does not stop a noncooperative worker after all connections are invalidated, although host death does stop it. Does Apple provide a supported lifecycle owner and identity-bound termination mechanism for this combination? If Application-type embedded XPC services are the intended solution, what supported packaging/discovery path admits separately installed third-party addon code without changing the signed host bundle or loading that code into the GUI process? Please distinguish the documented client-lifetime contract from startup coverage, on-demand stop, exit observation, and publisher isolation. We seek a supported mechanism or a precise compatibility boundary, not a private SPI or a debugging entitlement workaround.

## Verification of this delivery

Documentation work and reading of sources/APIs; no build or native addon probe was run, and no new test result is claimed. The last recorded product suite remains that of 23 September, not rerun here. No change to product code, entitlements, dependencies or admission records. The C0d driver keeps the unconditional exit 78 and SHA-256 `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`. The ordinary relaunch of Cascade is a separate check of the existing app and does not qualify the launcher.
