# XPC broker and external ExtensionFoundation addon: 24 September 2026

**Updated verdict: the broker reaches the monitor, but lacks the consent observed in the app. Composition not qualified.** The main agent's subsequent probe finds the provider from the GUI; from the broker it sees one unapproved candidate and no usable identity. The modern constructor does not reject the `.xpc` target. A public consent path for that context has yet to be found, and launch and lifetime ownership have yet to be proven. The external `.app` container with an `.appex` remains consistent with the specification; this report does not demonstrate the general impossibility of the broker and does not authorize a production launcher.

Delegated documentation investigation: Apple sources, the local public SDK and the repository; this researcher ran no build or fixture and modified no code. The subsequent native probe was run by the main agent and its log was read here, kept distinct from the documentation sources. The first query to the MCP graph returned the Cascade project as not indexed; local reading is the planned fallback.

## Question and composition boundary

The candidate design is:

```text
Cascade.app — XPC → trusted broker included in Cascade
                         │
                         └─ ExtensionFoundation → provider.appex
                                                   inside another installed app
```

The broker contains only trusted infrastructure; the addon code stays in the extension's process. The [specification, sections 4 and 8](../../superpowers/specs/2026-09-09-addon-runtime-design.md) admits the standalone container and excludes loading addon code into the GUI. The separation designed here would respect that boundary **if** discovery and launch from the broker were supported; naming XPC is not enough to obtain them.

The existing evidence covers two different edges:

| Edge | Local evidence | What it does not demonstrate |
| --- | --- | --- |
| Host app → external `.appex` | [P0](../../superpowers/verification/2026-09-09-addon-runtime-P0.md): discovery, authenticated echo and a separate process; host death terminates the provider in the observed runs | Hosting from `.xpc`, identity of another publisher, macOS 14/15/26 |
| App → `.xpc` broker → `.xpc` worker embedded in the broker | [XPCBroker](../../superpowers/verification/2026-09-24-addon-xpc-broker.md): ordinary broker exit terminates the blocked worker; another chain remains available | An `.appex` worker installed outside the app, and lifetime tied to the broker rather than to the root app |

Composing those results does not constitute evidence of the third edge, broker → `.appex`. In particular, transferring to the broker an endpoint created by the GUI does not prove that the system also transfers lifetime ownership.

## Host identity and the extension point declaration

Apple describes the host as an app: the app declares the extension points and the system uses the metadata in its bundle to associate extensions. With the new APIs, `EX_ENABLE_EXTENSION_POINT_GENERATION=YES` produces an `.appext` file; the documentation also admits a file prepared in advance. It does not say that putting the same metadata in an `.xpc` bundle turns that service into a host. [Apple: adding support](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app), [Definition](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/definition).

`AppExtensionPoint.Identifier(host:name:)` binds the extension to the **host's bundle identifier** and to the name of its point. It is not a parameter for freely choosing the process to which the launch is assigned. [Apple: Identifier](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/identifier/init%28host%3Aname%3A%29).

The public SDK examined exposes in `AppExtensionPoint.Error`:

- `hostMustBeApplicationOrAppExtension`;
- `hostMustHaveBundleIdentifier`;
- `hostMustDefineAppExtensionPoint(String)`;
- `invalidAppExtensionPoint` and `unspecifiedAppExtensionPointName`.

Apple's error-code page qualifies the first as an unsupported target and the third as a definition outside an app. **Cautious reading:** these are possible checks on the host context, not proof that every call from `.xpc` triggers them. The name of the first case, on its own, does not authorize every form of nested hosting; nor does it specify how an embedded service resolves the identity of the app that contains it. The subsequent probe below **did not receive these errors** when constructing the existing point and the monitor in the broker. [Apple: point errors](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/error/hostmusthavebundleidentifier); SDK, lines 84–116, reference below.

XPC's `ServiceType=Application` describes the instance policy of the **service**, not a conversion of the bundle into an application. Apple's manual distinguishes that value from `CFBundlePackageType=XPC!` and describes an app namespace for embedded services. It must not be used as evidence that ExtensionFoundation accepts `.xpc` as a host. Source: SDK `xpcservice.plist(5)`, lines 16–61.

In the legacy prototype, [`Probe.appextensionpoint`](../../../Prototypes/AddonPlatform/Host/Probe.appextensionpoint) declares `hylo.Cascade.AddonProbe.provider` and `EXPresentsUserInterface=false`; the [Xcode project](../../../Prototypes/AddonPlatform/AddonPlatform.xcodeproj/project.pbxproj) copies it into `Host.app/Contents/Extensions`. The [provider plist](../../../Prototypes/AddonPlatform/Provider/Info.plist) uses `EXAppExtensionAttributes/EXExtensionPointIdentifier`. `.appextensionpoint` is the manual format concretely present and tested here; `.appext` is the name described by the current documentation. Renaming them or copying them into `.xpc` is not assumed to be an equivalent migration.

P0 also recorded empty discovery with a host of a different bundle/signing identity. This is evidence relevant to the identity context; it does not isolate which check caused the rejection and does not directly prove the broker case.

## Apple source directly relevant to the composition

In [Apple thread 846017](https://developer.apple.com/forums/thread/846017), consulted on 24 September 2026, Quinn of DTS answers the precise case “app → extension → further extensions from third-party developers”: this capability is not enabled; he suggests an enhancement request. The thread also distinguishes PluginKit, which came earlier, from ExtensionKit.

This answer is a primary source on support for the nested case, not a generic statement that all XPC processes are forbidden as callers. It does, however, rule out treating a **broker converted into an `.appex`** as an already supported solution. The apparent contrast with the name `hostMustBeApplicationOrAppExtension` calls for clarification from Apple on the API's scope, not for a permissive interpretation derived from the enum alone.

No Apple answer was found that exactly confirms or denies “a trusted `.xpc` service in the app, operating for the containing app's extension point”. This subcase remains the open question. The searches used ExtensionFoundation, XPC service, host, bundle identifier and `.appextensionpoint`; no third-party articles were used as evidence of support.

## APIs usable with a 14 minimum, and 26 APIs

The following table derives from the availability annotations in the **SDK 27.0**, not from execution on those systems nor from reading a historical 14 SDK.

| Function | Path compatible with a 14 target | New API |
| --- | --- | --- |
| Provider definition | `AppExtension`, `AppExtensionConfiguration.accept(connection:)`, available since macOS 13 | `ConnectionHandler`, macOS 26 |
| Discovery | `AppExtensionIdentity.matching(appExtensionPointIDs:)`, since 13, deprecated in 26 | `AppExtensionPoint.Monitor`, macOS 26 |
| Extension point | Manual metadata already used by the fixture | `AppExtensionPoint`, `Definition`, `Identifier`, `Scope`, macOS 26 |
| Binding on the `AppExtension` conformance | Fixture plist | `extensionPoint` property and the conformance's binding alias, macOS 26.2 |
| Process | `AppExtensionProcess.Configuration` and initializer, since macOS 13 | Same type; no distinct public owner/lifecycle owner selectable in the configuration read |
| Transport | `makeXPCConnection() -> NSXPCConnection`, since macOS 13 | `makeXPCSession()`, macOS 26 |
| End of use | `invalidate()`, since macOS 13 | No distinct public force-stop API in this interface |

`AppExtensionIdentity` is `Identifiable`, `Hashable`, `Sendable`; its public surface as read exposes neither a constructor from a bundle ID nor `Codable`/`NSSecureCoding` conformance. Apple explicitly says to obtain instances from discovery. So a path of “the GUI discovers, serializes the identity and the broker reconstructs it” through these APIs is not documented. Passing an identifying string is not equivalent to passing the system's identity. [Apple: AppExtensionIdentity](https://developer.apple.com/documentation/extensionfoundation/appextensionidentity); SDK, lines 159–180 and 237–258.

For external extensions the new APIs require `Scope(restriction: .none)`; the default limits them to the app's bundle. The system considers only approved and enabled ones; those distributed separately are initially disabled. The documented presentation of the browser happens from the app; it is not equivalent to an API for granting consent to other processes. [Apple: Scope](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/scope), [discovery](https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app), [Monitor](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/monitor).

## Signing, isolation and lifetime do not automatically follow discovery

The `AppExtensionProcess` documentation promises a separate launch, possible reuse of the process and reporting of interruption. It does not specify here the case of an `.xpc` caller, nor a parameter to make a broker the sole owner. [Apple: AppExtensionProcess](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess).

The `invalidate()` documentation describes exit at the last connection. The [local P0](../../superpowers/verification/2026-09-09-addon-runtime-P0.md) keeps a real FAIL with a noncooperative provider after invalidation and release; successful discovery from the broker would not cancel it. [Apple: invalidate](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()).

The provider fixture keeps App Sandbox and Hardened Runtime, but the P0 host is not a sandboxed service. The XPCBroker result, by contrast, concerns sandboxed services from the same team. The intersection **sandboxed broker + external extension + different signer** is therefore not yet verified. Sources: [P0 project](../../../Prototypes/AddonPlatform/AddonPlatform.xcodeproj/project.pbxproj), [provider entitlements](../../../Prototypes/AddonPlatform/Provider/Provider.entitlements), [XPCBroker report](../../superpowers/verification/2026-09-24-addon-xpc-broker.md).

The [P0 protocol](../../../Prototypes/AddonPlatform/Shared/ProbeMessage.swift) and the [provider](../../../Prototypes/AddonPlatform/Provider/ProbeProvider.swift) also verify the GUI's signing identifier (`hylo.Cascade.AddonProbe`). A future broker would have a distinct identity: moving the caller would require an explicit authentication contract, without removing the check or declaring the PID reported by the addon valid. This is work that comes after discovery, not a reason to widen its probe now.

## Subsequent discovery-only probe, run by the main agent

Fixture [`XPCDiscovery/Probe.swift`](../../../Prototypes/AddonPlatform/XPCDiscovery/Probe.swift), [builder](../../../Prototypes/AddonPlatform/XPCDiscovery/run_discovery.py), macOS 27.0 `26A5425a`, SDK 27.0, products `probe-0s0ccy7h`. Source read: [stdout.jsonl](/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeXPCDiscoveryProbe/probe-0s0ccy7h/stdout.jsonl), SHA-256 `3adcd8af672c4e621383816b4b41f13ad9ed9fd3025bd7c3e29da6b08e69ad48`.

| Context | Legacy | Modern monitor | Target error |
| --- | --- | --- | --- |
| App `hylo.Cascade.AddonProbe`, PID 31795 | Provider `hylo.Cascade.AddonProbeContainer.Provider` | Same provider; disabled 0, unapproved 0 | None |
| Broker `hylo.Cascade.AddonProbe.DiscoveryBroker`, PID 31821 | Empty identities | Empty identities; disabled 0, unapproved 1 | None |

App and broker use the same point; the point file is only in the app, not in the `.xpc`. The channel with the broker is verified and correlates nonce/PID. The builder keeps signing and Hardened Runtime on both components and App Sandbox on the service. The source does not create `AppExtensionProcess`.

**Fact:** the broker completes `AppExtensionPoint(identifier:)` and `Monitor`, sees an unapproved count, but obtains no usable identities. **Inference:** the consent observed for the GUI is not sufficient for this broker context. The count does not expose the candidate's identity, so it does not by itself prove that the item is exactly that provider; nor does it demonstrate that later consent would be enough for launch. Apple defines `unapprovedCount` as the number of entries not yet enabled, distinct from `disabledCount`. [Apple: Monitor.State](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/monitor/state-swift.struct).

## Consent: public surface and the next minimal check

The public header `EXAppExtensionBrowserViewController.h` declares only the `NSViewController` subclass, with no specific properties, methods or initializers for choosing a host. The ExtensionKit Swift interface adds none. There are no public `hostBundleIdentifier`, audit token, PID, monitor or extension point parameters with which the GUI could present the browser **on behalf of the broker**. The configuration of `EXHostViewController` concerns a scene of an already identified extension; it is another type, not a browser configuration. [Apple: browser](https://developer.apple.com/documentation/extensionkit/exappextensionbrowserviewcontroller), [EXHostViewController.Configuration](https://developer.apple.com/documentation/extensionkit/exhostviewcontroller/configuration-swift.struct); SDK header, lines 20–41.

`Monitor` exposes add/remove of the point and read-only state: no method for approval or for replacing the host identity. `Scope(.none)` decides whether to admit external packages, not who grants consent. `Identifier(host:name:)` is a binding to the point, not an identity delegation for the caller. These distinctions derive from the SDK signatures and the documentation already cited; adding App Groups or copying a bundle ID is not a documented ExtensionFoundation consent mechanism.

Apple prescribes the system UI for approving, enabling and disabling extensions; it documents both System Settings and the browser presented in the app. The browser displays all of the app's points, uses out-of-process UI and does not notify changes directly: one observes the monitor. This does not mean the view controller can be transferred over XPC while keeping the identity of whoever created it. [Apple: displaying extensions](https://developer.apple.com/documentation/extensionkit/displaying-the-app-extensions-available-to-your-app).

**Browser presented by the broker:** not confirmed by the current sources. The [archived Apple guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html), updated in 2016, classifies XPC services as unable to present UI except for the limited IOSurface case. The guide states up front that these are recommended practices and that other behaviors may exist: it is not proof of impossibility on macOS 27. However, it gives no positive support for using `NSWindow` + browser from the service. Any limited probe by the main agent therefore distinguishes **observed behavior** from **supported configuration**; it must keep identity, sandbox and signing, and stop if the browser is empty/not presentable. No result of such a UI probe was available during this update.

The next check already traceable to a public interface is to **inspect** System Settings → General → Login Items & Extensions and the app's browser, to see whether there is an entry that unambiguously represents the fixture's broker and provider. Apple documents that path, but does not promise an entry for `.xpc` hosts. [Apple Support: extension settings](https://support.apple.com/en-ke/guide/mac-help/-mtusr003/mac). An entry bearing the name of the already approved app is not enough. If the system really exposes the broker context, the next minimal experiment is explicit user consent on the fixture alone, followed by a new authenticated discovery in both contexts, without starting the provider. If the entry is missing, record the limit without `exctl`, database, KVC, private selectors or artificial reuse of the GUI signature.

A positive consent/discovery outcome will still require a distinct probe of authenticated launch, a check of which death terminates the provider, stopping the chain alone while the app stays alive, startup before `main`, isolation between addons, delegated processes, signing by different publishers and a real 14/15/26 matrix. Hosting a remote scene in the GUI afterwards could add another user of the process and change the “single broker client” assumption.

Question ready for Apple, **not sent**: “Can an Application-type XPC service embedded in a macOS app use that containing app's declared ExtensionFoundation extension point to discover and launch extensions installed in other apps? If so, which bundle identity and extension-point metadata location are required, and which process owns the extension's lifetime? Does the answer differ between the legacy macOS 13–15 discovery API and AppExtensionPoint.Monitor on macOS 26+? We need the extension to terminate when the broker exits while the GUI app remains alive, without loading third-party code into the GUI or weakening sandbox/signing.”

## Reproducible SDK source and limits of this delivery

- SDK: `/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`, version `27.0`.
- Interface: `System/Library/Frameworks/ExtensionFoundation.framework/Versions/A/Modules/ExtensionFoundation.swiftmodule/arm64e-apple-macos.swiftinterface`; Apple Swift 6.4, ExtensionFoundation module `289.2`.
- Interface SHA-256: `5ba60922c99cefb52fa9ecc76318cbbb29469df28002961ec9142174586c0c31`.
- Public XPC manual: `usr/share/man/man5/xpcservice.plist.5` in the same SDK.
- Browser: `System/Library/Frameworks/ExtensionKit.framework/Versions/A/Headers/EXAppExtensionBrowserViewController.h`, SHA-256 `14cc045b05385db4b8d75fbb971365718f7ce470cae401698bda1bfa38281ca3`.

No private API or disassembled binary was used; the only new native evidence reported here comes from the main agent's fixture, not from a run by the researcher. No change to C0 admission, the approved spec, entitlements or product code. Any concluding relaunch of Cascade belongs to the main task, not to this delegated research. No message was sent to Apple.
