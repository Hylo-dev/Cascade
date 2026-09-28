# ExtensionFoundation: documentation of startup and release

Research of 24 September 2026, on Apple documentation, public Apple DTS answers, Apple material and the SDK 27 public interface. No request sent to Apple; no native probe or gate change in this pass.

Later update: the check proposed below was authorized and
[run](../../superpowers/verification/2026-09-24-addon-interruption.md).
Callback and kernel exit agree for voluntary exit and crash; neither of the two
is observed in the six seconds after invalidation or release, even cooperative ones.
The proposal below remains the earlier context, not an activity still to be carried out.

## Useful result

A public Apple answer to the general lifecycle question already exists: in July 2025 Quinn (DTS) distinguishes ExtensionKit/Foundation extensions from transaction-governed XPC services and points to the control the host exercises through `AppExtensionProcess.invalidate()`. There is no need to contact Apple to establish which API to use. The answer does not separately address pending startup, host crash, dyld or early identification of the process. [Apple answer in thread 791728](https://developer.apple.com/forums/thread/791728).

The documentation therefore offers a positive process-management contract. It must not be described as absent or as a promise limited to the first application message alone. Cascade's more specific requirement remains to be qualified: confirming the exit of the precise execution, even when the host disappears before getting the result of the launch request. The absence of a detail in the pages consulted does not demonstrate that macOS leaves orphaned processes.

## Three objects not to confuse

| Object | Public contract | Consequence for the test |
| --- | --- | --- |
| `AppExtensionIdentity` | Identifies an available extension. It does not expose the identity of one of its executions. | The same extension can be run several times; the bundle identifier does not replace a process identity. [Reference](https://developer.apple.com/documentation/extensionfoundation/appextensionidentity). |
| `AppExtensionProcess` | Construction can create or reuse the process. The result arrives after startup, when the process is ready for an XPC connection. | Creating a second object does not promise a new execution. Before the initializer returns, the caller does not yet have this object. [Type](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess), [asynchronous initializer](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/init(configuration:)-38zf). |
| Application XPC connection | After obtaining the process, the host calls `makeXPCConnection()` to communicate. The guide documents retaining the process reference and XPC communication separately. | Closing only the application channel is not equivalent to releasing every managed reference to the process. [Guide, launch and unload](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |

`invalidate()` terminates the process when the object represents the last connection; it then requires releasing the references and ceasing communication. The guide explains that, with multiple connections, the process stays alive until the last one closes. The guide's sentence saying that invalidating does not automatically terminate the process must be read together with this condition, not as an absolute denial of termination. [Method](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()), [guide](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app).

The same guide documents automatic invalidation if the reference to `AppExtensionProcess` is not retained. It does not document an autorelease pool delay, a particular ARC implementation, or destructors running on sudden host death. These would be further assumptions. For an explicit-release probe it is advisable to verify all owners of the reference, including closure captures and still-pending operations; a simple `process = nil` does not by itself demonstrate that every copy is gone. The latter is a consequence of the ownership model, not a behavior observed here in the framework. [Guide](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app).

## Startup, cancellation and notifications

The asynchronous initializer copies the necessary data from the configuration and keeps no reference to it. It documents creation or reuse of the process, execution of startup and possible later suspension until an XPC connection is opened. It describes neither a configurable timeout nor `Task` cancellation semantics. The `async throws` suffix alone does not constitute a promise to cancel the remote creation. [Asynchronous initializer](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/init(configuration:)-38zf).

`Configuration.onInterruption` is supplied already with the process request. The property describes it as notification of unexpected exit; the type's overview speaks more generally of exit for any reason. It does not require a first application message, but the pages do not specify an order relative to failed startup completion, a delivery queue, a maximum time, or delivery after voluntary invalidation. The `() -> Void` signature returns no PID, audit token or exit status. It is therefore not correct to state that the notification exists only after the handshake; it is equally incorrect to use it as a receipt transferable to another process after host death. [Property](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/configuration/oninterruption), [configuration](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/configuration), [overview](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess).

An AppKit document recommends replacing directly launched processes with XPC services or extensions contained in the app: that way the system tracks the relationship and automatically terminates those processes on quit. It is a positive indication of managed ownership. The passage refers explicitly to components **inside the app**; it does not define an exit receipt or the case of the external extension inside another app, and does not separate completed from pending startup. It is not correct to extend it automatically to all these conditions. [Managing ongoing background processes in your Mac, “Managing Exec'ed Processes”](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac).

Correction with respect to the previous research: for the distinct `NSXPCConnection.interruptionHandler`, the web documentation describes delivery after the other handlers; the SDK 27 public header says same queue, **with no ordering guarantee**. So do not assume a universal order or infer from it the queue of `AppExtensionProcess.onInterruption`. The header also distinguishes connection invalidation from process exit: invalidating an anonymous listener can cause the former. [Web page](https://developer.apple.com/documentation/foundation/nsxpcconnection/interruptionhandler), [SDK 27 header](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSXPCConnection.h:104>).

## Availability: the new APIs do not change process control

The availabilities below come from the public interface of the local SDK 27, not from tests on all macOS versions.

| API | Minimum macOS in SDK 27 | Impact on the macOS 14 requirement |
| --- | --- | --- |
| `AppExtensionProcess`, synchronous/asynchronous initializer, `invalidate`, `Configuration.onInterruption`, `makeXPCConnection` | 13.0 | Available; no new public launch or cancellation parameter in this interface. |
| `AppExtensionIdentity.matching` | 13.0; deprecated since 26.0 | Remains the discovery path compatible with 14. |
| `AppExtensionPoint.Monitor` and programmatic extension point definitions | 26.0 | They do not replace discovery on 14 without a fallback. |
| `AppExtensionProcess.makeXPCSession`, `AppExtensionPoint.EnhancedSecurity` | 26.0 | New transport and isolation; they add no process handle before startup. |
| `AppExtensionPoint.Capabilities` | 26.2 | Describes extension capabilities, not exit receipts. |

Source: [ExtensionFoundation.swiftinterface, SDK 27](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ExtensionFoundation.framework/Versions/A/Modules/ExtensionFoundation.swiftmodule/arm64e-apple-macos.swiftinterface:237>), plus the rest of the same file for monitor, attributes and capabilities. The SDK exposes in `Configuration` no PID, audit token or timeout field, and no option to force a new process.

## Additional material verified and limits of transfer

- The UI guide distinguishes connecting to a specific scene through `EXHostViewController` from global connection through `AppExtensionProcess`. Activation of the controller means availability for XPC; deactivation can depend on process exit **or on other reasons for tearing down views**. It is not a reliable alternative observer of process exit. A future probe with UI will also have to account for this owner of the session. [Including extension-based UI](https://developer.apple.com/documentation/extensionkit/including-extension-based-ui-in-your-interface).
- Apple's WWDC22/23 indexes present ExtensionKit/Foundation, and WWDC23 the new Swift XPC. The search of the 2022/23/25/26 sessions found no additional relevant promise of pre-main cleanup: this is the result of the search, not a statement that no such material exists. [WWDC22](https://developer.apple.com/documentation/updates/wwdc2022), [WWDC23](https://developer.apple.com/documentation/updates/wwdc2023).
- The recent Enhanced Security examples still use `AppExtensionProcess` and `onInterruption`; the material on Xcode 26 and the Apple workshop cover sandbox, isolation and result validation, not a new exit-receipt protocol. Migrating to these APIs does not by itself close the point and does not cover macOS 14. [Helper guide](https://developer.apple.com/documentation/xcode/creating-enhanced-security-helper-extensions), [WWDC25 Xcode 26](https://developer.apple.com/videos/play/wwdc2025/247/), [Apple workshop](https://developer.apple.com/videos/play/meet-with-apple/278/).
- A further DTS answer from September 2026 says that an ExtensionFoundation extension cannot in turn define its own extension point to host other third-party extensions. It does not directly concern our `.xpc` broker, but it avoids proposing an `.appex` → `.appex` chain as an already supported alternative. In the same thread DTS distinguishes PlugInKit/NSExtension from the later ExtensionKit: the contracts of other extension families do not transfer automatically. [Apple answer, thread 846017](https://developer.apple.com/forums/thread/846017).

## Next step derivable from the documentation

The documented path remains explicit release of the last session and the `onInterruption` notification, with broker recovery already observed in the project's probes. To go deeper locally it is advisable to separate two checks: (1) truly complete release of process, channels and future UI, compared with the previous invalidation probe; (2) failure/cancellation during a pending initializer and independent observation of the result. The pages consulted do not authorize declaring the second check passed on the basis of the first.

There is a targeted probe still to be done: the current fixtures create the configuration without setting `onInterruption`, leaving the empty default. Configuring it **before the initializer**, correlating the callback with a local launch nonce and comparing its delivery with the kernel observation after the handshake would make it possible to verify this part of the public contract. Afterwards, failure during startup can be studied without calling this first comparison a complete pre-main proof. Local cross-check: [host](../../../Prototypes/AddonPlatform/Host/ProbeHost.swift:73), [broker](../../../Prototypes/AddonPlatform/BrokerRecovery/Probe.swift:28); default in the SDK interface cited above. This note proposes the check and does not declare a result for it.

The native results already acquired remain those of the [global recovery report](../../superpowers/verification/2026-09-24-addon-global-recovery.md), with its scope after identification. This research neither extends nor invalidates them. The gate can stay cautious without turning a request for clarification to Apple into an operational prerequisite: the research and the local checks are paths distinct from an external contact, which the user has ruled out.
