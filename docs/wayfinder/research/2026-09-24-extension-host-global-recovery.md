# ExtensionFoundation: global recovery and lifetime before main

Documentation research of 24 September 2026. Apple sources and the local public SDK only; no compilation, native execution, termination or permission change.

Later update: the user rules out contacting Apple. The
[research in the public sources](2026-09-24-extension-startup-documentation.md)
examines the contract in more depth without depending on a support request. The later
positive evidence is in the [recovery report](../../superpowers/verification/2026-09-24-addon-global-recovery.md).

## Operational outcome

The [native-addon-global-recovery](../../superpowers/specs/2026-09-10-addon-control-policy.md#emergency-global-recovery-decision-of-24-september-2026) policy allows global restart as a last resort, but keeps verified exit of the incarnation, absence of orphans even before main, and the ban on restarting with the old chain in an unknown state. The sources consulted **are not yet enough to qualify this entire path** for an external addon. They document launch, reuse and release of the process, without specifying the guarantee on host death during startup/dyld. This is not a conclusion of general impossibility.

## Public contract found

| Aspect | Contract and limit |
| --- | --- |
| Creation | `AppExtensionProcess` reuses an existing process or creates one. The instance is returned when the extension has started and is ready for XPC; it is not a handle delivered before startup. [Type](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess), [asynchronous initializer](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/init(configuration:)-38zf). |
| Release | `invalidate()` terminates the process if that object represents the last connection. With multiple connections the process stays alive until the last one closes. The method returns no exit receipt and documents no maximum time. [Method](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()), [guide](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |
| Host death | The guide documents automatic invalidation when the reference is not retained. It does not separately specify normal exit, host crash and a still-pending launch request, nor the start of the cleanup obligation before main. Equating these situations is an inference to be qualified. [Guide](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |
| Reuse | Assuming a new process for each construction is not legitimate. The pages cited do not bound reuse across distinct hosts/clients, nor do they promise exclusivity. A second observer that obtains its own `AppExtensionProcess` can add a connection and alter precisely the “last connection” condition. [Type](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess), [guide](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |

The asynchronous initializer documents that startup runs before it returns and that the process may later be suspended without an XPC connection. It does not document that cancelling the Swift `Task` kills an already created process or completes cleanup. [Initializer](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/init(configuration:)-38zf).

## Observation: three distinct moments

1. **After startup, before the first application message:** `Configuration.onInterruption` exists, configured already in the launch request. The documentation does not require a successful first application message. It is a public notification of the loss of the associated process; it can be correlated locally with one's own request. The property page speaks of unexpected exit, the overview of exit for any reason: do not extend delivery to one's own `invalidate()` without verification. [Property](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/configuration/oninterruption), [overview](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess).
2. **Blocked callback:** `onInterruption` documents no queue, delivery deadline or independence from a blocked queue. The distinct `NSXPCConnection.interruptionHandler` uses the same queue as the other handlers. The web page describes an order after the other callbacks, but the SDK 27 public header specifies that the order is not guaranteed: do not base control on that order. The problem of a blocked queue remains, distinct from process death. Connection invalidation alone is not enough to prove exit. [Foundation](https://developer.apple.com/documentation/foundation/nsxpcconnection/interruptionhandler), [SDK 27 header](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSXPCConnection.h:104>).
3. **From creation until startup:** the public interface examined shows no early incarnation PID/token/handle, no transferable exit observer and no API to wait for that exit from another process. `AppExtensionIdentity` identifies the extension, not one of its executions. `onInterruption: () -> Void` delivers no identity or exit status, and its dead host cannot record that it ran. [SDK 27, public interface, lines 160–178 and 237–258](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ExtensionFoundation.framework/Versions/A/Modules/ExtensionFoundation.swiftmodule/arm64e-apple-macos.swiftinterface:237>).

The third point is the bounded result of the inventory of these APIs; it does not rule out every possible public macOS solution.

## Available evidence and next step

The [P0](../../superpowers/verification/2026-09-09-addon-runtime-P0.md) records exit after normal host close and after SIGKILL of the host with a noncooperative worker, in the fixture on macOS 27 beta. The flow had already reached XPC authentication. It does not prove host death during dyld, a pending initializer, another publisher or other operating systems; the same P0 also records a failed selective stop through invalidation.

**No complete, finite and safe experiment for the pre-main gate was identified with only the interfaces examined.** What is missing before launch is an authentic observer of the incarnation, independent of the host that is meant to die, that does not keep the provider alive. A marker in a C constructor would explore the stretch before main after that constructor runs; it would not cover creation → first initializer. A handshake followed by a spin would explore an even later phase. Do not call such probes “coverage from birth”.

The next useful step forward requires an Apple contract or a verifiable public API that clarifies: cleanup on host death even with a pending launch; the boundaries of reuse across clients; observation of the exit of the specific incarnation without a connection that holds it. These are the prerequisites for then defining a finite probe; no request was sent to Apple. Meanwhile, external packaging and qualification after startup can proceed, keeping the overall gate not passed, without authorizing restart with an unknown chain.
