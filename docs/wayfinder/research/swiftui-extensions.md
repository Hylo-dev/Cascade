# Load external SwiftUI widgets: mechanisms and limits

Research of 4 September 2026. Context: Cascade distributed outside the App Store, also through Homebrew; independent integrations written in SwiftUI, possibly importable or installable in a folder. This report establishes the alternatives and leaves the choice of format open. Sources: Apple/Swift documentation and the local checkout; no prototype run.

## Result

The desired extensibility is technically plausible. There are two distinct paths for arbitrary SwiftUI UI: loading binary code into Cascade's process, or hosting remote UI with the public ExtensionKit APIs. `import` and conformance to a protocol do not, on their own, make a widget discoverable by another application. The decision depends above all on isolation, installation, macOS compatibility and freedom of the interface.

## Verified starting point

[`NotchWidget`](../../../CascadeKit/Sources/CascadeKit/Core/Widgets/NotchWidget.swift) is already public, `@MainActor`, with identity, kind, footprint, `makeContentView() -> AnyView`, `activate` and `suspend`. [`WidgetHost`](../../../CascadeKit/Sources/CascadeKit/Core/Widgets/WidgetHost.swift) keeps instances in the process and calls the widgets directly. [`CascadeApp`](../../../Cascade/CascadeApp.swift) registers `ClockWidget` manually; there is not yet an external discovery mechanism in these paths.

[`CascadeKit/Package.swift`](../../../CascadeKit/Package.swift) declares macOS 14, Swift tools 6.2 and a library without an explicit linkage type. The [Xcode project](../../../Cascade.xcodeproj/project.pbxproj) uses macOS 14, Hardened Runtime enabled and App Sandbox disabled. These are source settings, not verifications of the signature of a distributed app. Moreover, the host suspends all widgets when the notch is closed: the continuous compact activity will need an explicitly defined lifecycle.

## Matrix of the alternatives

| Alternative | Independent addition | SwiftUI UI | Execution boundary | Deciding question |
| --- | --- | --- | --- | --- |
| Swift package/`import` in the Cascade build | Requires a new build of the host | Complete | Cascade process | Suited to built-in modules; does not satisfy standalone installation on its own. |
| Binary bundle/framework from a folder | Yes, with a loader and a stable contract | Complete, in process | No isolation from the widget | Signing, ABI compatibility, crashes and hangs fall on the host. |
| Container app with an ExtensionKit extension | Yes, through system registration | Remote SwiftUI scenes | Extension process | User enablement; macOS 14/15 path to be tested. |
| External provider with declarative messages/data | Yes, with an IPC protocol | Cascade's SwiftUI rendering | Separable logic | Freedom limited to the components/layouts described by the contract. |

The matrix summarizes the following facts; the fourth alternative is an **architectural proposal**, not a format already present in the repository.

## Import, binaries and type identity

**Facts.** `import` makes a module's symbols available in the source; SwiftPM produces build artifacts and can choose static or dynamic linking. It does not define a runtime search of the installed apps. Setting `.dynamic` is a linkage choice, not a plugin system. [Swift: import](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations/), [SwiftPM: products](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html).

`Bundle.load()` loads executable code into an already running program. Apple documents bundles also outside the app and access to the principal class; reading `principalClass` can already load code. A folder must therefore contain compatible compiled artifacts, resources and metadata, not simply Swift files to be interpreted. An import interface can be built on top of this mechanism. [Bundle.load](https://developer.apple.com/documentation/foundation/bundle/load()), [Loading Bundles](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingCode/Tasks/LoadingBundles.html).

Swift distinguishes ABI stability, module stability and library evolution. For binary libraries updated independently, `BUILD_LIBRARY_FOR_DISTRIBUTION` enables the last two; it does not make every change to the SDK compatible. [Library Evolution](https://www.swift.org/blog/library-evolution/).

**Implication to prototype.** Host and plugin must agree on module/protocol identity, exported symbols, factory and ABI version. A separately embedded copy of CascadeKit must not be assumed equivalent to a single shared SDK; casts, conformances and updates have to be verified. The runtime identifies types through metadata and protocol descriptors, not through a simple equality of names. `AnyView` erases the concrete type of the view, but does not constitute an IPC format. [Swift: Type Metadata](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst).

## Signing and real availability

**Fact.** With Hardened Runtime, library validation normally admits code signed by Apple or with the same Team ID as the executable. For plugins from different developers Apple points to `com.apple.security.cs.disable-library-validation`; disabling it entails additional Gatekeeper checks. Direct distribution and Homebrew do not remove this constraint. [Disable Library Validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

**Consequence.** Signing and authenticity are not isolation: correctly signed code can still contain bugs or unwanted behaviors. Verification of the vendor, consent to activation and sandbox answer different problems. Apple describes signing as an attestation of origin; process separation instead reduces the impact of failures. [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html), [Designing Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html).

## Public remote UI and installation

**Facts.** ExtensionKit documents `PrimitiveAppExtensionScene` to produce UI and `EXHostViewController` to host it, also through `NSViewControllerRepresentable` in SwiftUI. The host treats the content as opaque; it can connect to the scene over XPC. So remote UI does not necessarily mean private APIs. There is no need to presume that SwiftUI views are serializable or to rely on undocumented remote classes. [Including extension-based UI](https://developer.apple.com/documentation/extensionkit/including-extension-based-ui-in-your-interface).

An extension point with `Scope(restriction: .none)` admits extensions external to the host; the default limits them to its bundle. The extension is distributed inside a container app, with the extension point identifier and the host's SDK. It is a model consistent with "one's own app adds the widget"; the documentation does not establish an equivalent to loading a loose `.appex` from any folder. [Scope](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/scope), [Building an app extension](https://developer.apple.com/documentation/extensionfoundation/building-an-app-extension-to-support-a-host-app).

Separately distributed extensions are initially disabled: the device owner enables them through a system interface, also available inside the app with `EXAppExtensionBrowserViewController`. Discovery can update on installation/removal of apps, but "automatic" cannot mean activation without this step. The documentation allows external contributions; signing and activation with two different Team IDs remain a distribution test to be done. [Discovery](https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app), [Extension browser](https://developer.apple.com/documentation/extensionkit/displaying-the-app-extensions-available-to-your-app).

**Availability verified in the local Apple macOS 27.0 SDK:** `EXHostViewController`, `PrimitiveAppExtensionScene` and legacy discovery date back to macOS 13; `AppExtensionPoint`, `Scope` and `Monitor` require macOS 26. Some new binding APIs require 26.2. The declarations are in `ExtensionKit.framework/Headers/EXHostViewController.h` and in the Swift interfaces of ExtensionKit/ExtensionFoundation under `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/`.

Apple confirms that the programmatic generation of the `.appext` file arrives with macOS 26 and that earlier files remain usable. The availability of the classes since 13 **does not by itself prove** complete operation on Sonoma: manual manifest, legacy discovery, signing and registration must be verified on 14/15. [Adding extension support](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app).

## Isolation: what is guaranteed and what is missing

In the current model, a widget that blocks `makeContentView` or `activate` blocks Cascade's MainActor; `suspend` is cooperative, not a limit imposed by the system. Putting only the audio work or the logic in XPC leaves the arbitrary UI in the host process.

ExtensionFoundation runs the extension separately and reports interruptions; ExtensionKit reports deactivations. This contains the crash of the remote process, but does not guarantee that Cascade stays responsive if it waits for synchronous replies, decodes excessive payloads or mishandles the restart. Invalidating a connection does not necessarily terminate the process when other connections exist. [Extension lifecycle](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app), [Synchronous XPC](https://developer.apple.com/documentation/foundation/nsxpcconnection/synchronousremoteobjectproxywitherrorhandler(_:)).

The `EnhancedSecurity` attribute imposes further restrictions and requires dedicated configuration: the corresponding helper **cannot present UI**. It must therefore not be promised at the same time as maximum sandbox and as universal container for remote SwiftUI. [Enhanced Security helpers](https://developer.apple.com/documentation/xcode/creating-enhanced-security-helper-extensions).

## Tests needed before the decision

1. Two apps signed by different developers: discovery, approval, update and removal of the extension; macOS 14/15/26 matrix.
2. Remote scene in the notch panel: resize, transparency, focus, menus, drag/drop, accessibility and multiple instances; measure opening and memory.
3. Crash, hang of the remote main thread and missing IPC reply: verify that hover/closing and the other widgets keep working, with a placeholder and a controlled restore.
4. If the binary folder remains a candidate: old/new SDK, different compilers, supported architectures, library validation, failed loading and update without presuming a safe unload.

Decisions still for humans: priority between folder and integrated app, minimum macOS version, trust in external code, arbitrary UI versus declarative contract. None of these choices is resolved by this report.
