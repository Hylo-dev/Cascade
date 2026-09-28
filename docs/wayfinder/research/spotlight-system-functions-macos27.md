# Spotlight system functions and UI composition on macOS 27

Research date: 9 September 2026. This is the static-system investigation for option 2:
keep Apple's Spotlight search and results, replace only its input field with Cascade's
notch interface. The parallel Accessibility investigation covers control of the running UI.

## Finding

There is a concrete private separation between Spotlight's search field, results view,
and shared search manager in the macOS 27 SDK. The strongest candidates are
`SpotlightUIInternal.IslandSearchFieldView`, `IslandSearchResultsView`,
`IslandSearchManager`, and `IslandControllerHost.registerContainer(_:for:)`.
This makes investigation of Apple's existing UI components more credible than an
assumption that Spotlight is a single inseparable window.

The parallel live probe identified **Siri AI.app (`com.apple.campo`) as the owner of
the visible Spotlight search field** on this machine, rather than the legacy
Spotlight executable. Static inspection confirms that Campo uses these same
Spotlight components. It also has real private remote-view infrastructure through
`CampoRemoteService` and ViewBridge. The distinction is therefore not “remote views
do not exist”; it is whether the particular Spotlight result surface is available
through an interface that a normal third-party process can use.

The Island components themselves are exported **private, in-process** symbols. Their presence does not
provide a supported way to transplant the running Spotlight view, replace its field
from another process, or obtain a remote results surface. None of those behaviors was
demonstrated here. Loading Apple's components into a separate experimental process
would also create a new instance of those components; it would not take ownership of
the system Spotlight session.

Two different paths remain:

1. **Modify the running system process.** Interposition, injection, or changing its
   view hierarchy requires access inside the protected process. The inspected machine
   has SIP enabled and the Spotlight executable is marked `restricted`. This is not a
   normal distributable integration path under the current security configuration.
2. **Instantiate private components in our own process.** The symbols below give a
   specific research target. Whether initialization, service authorization, input,
   results, actions, focus, and lifecycle work for a third-party identity is unverified.
   This path could fail even if the framework itself loads successfully.

No public Spotlight-hosting contract was located in the reviewed SDK and Apple
documentation. This is a bounded research finding, not proof that no private route
can exist.

## Verified local baseline

| Item | Observed value |
| --- | --- |
| OS | macOS 27.0, build `26A5425a` |
| Architecture of Spotlight executable | Mach-O arm64e |
| System Spotlight | `/System/Library/CoreServices/Spotlight.app` |
| Bundle identifier | `com.apple.Spotlight` |
| Bundle version | `236.0.21.401` |
| Spotlight build SDK | `macosx27.0.internal`, build `26A5411a` |
| Selected developer directory | `/Library/Developer/CommandLineTools` |
| Inspected SDK | `/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk` |
| SDK private UI stub version | `236.0.21` |
| Current UI app from parallel AX probe | `/System/Applications/Siri AI.app`, bundle `com.apple.campo` |
| Campo app and remote service version | `73.0.24.405` |
| Campo build SDK | `macosx27.0.internal`, build `26A5421a` |
| SIP | Enabled |
| Spotlight app and executable file flag | `restricted` |

`/System/Library/LaunchAgents/com.apple.Spotlight.plist` conditionally disables its
job when `IntelligenceFlow/Campo` is enabled. Its declaration is verified; the flag's
effective state was not queried. Therefore the legacy Spotlight executable alone
does not establish which process owns the user's current macOS 27 search interface.
The live investigation resolved this for the current session: the visible
`SpotlightSearchField` AX element belongs to `com.apple.campo` (PID 1330 during the
probe). Static inspection below confirms the connection.

Only installed binaries, SDK headers/linker stubs, system launch configuration, and
Apple documentation were read. No private framework was loaded, no search was run,
no personal search index was read, and no service request, injection, debugger attach,
permission change, or UI mutation was performed by this investigation.

## Concrete implementation seams

### The active Campo/Siri host and the real remote-view service

`Siri AI.app/Contents/Info.plist` registers both `siri` and `spotlight` URL schemes,
uses launch label `com.apple.campo`, and requires the `IntelligenceFlow/Campo` and
`IntelligenceFlow/Linwood` feature flags. The launch agent
`/System/Library/LaunchAgents/com.apple.campo.plist` declares Mach service
`com.apple.campo`. The app's `BSServiceDomains` additionally describes
`com.apple.campo`, `com.apple.campo.activation`, and `com.apple.campo.test` services.
None was called here.

The app directly links `CampoUIInternal`, `CampoUIServices`, `CampoServices`,
`AssistantIslandClient`, `SpotlightUIInternal`, `SpotlightUIShared`, and `ViewBridge`.
Its imported functions include:

```text
CampoUIInternal.MacAssistantIslandCoordinator.toggleSpotlight()
CampoUIInternal.MacAssistantIslandCoordinator.invoke(with:reason:chatID:)
CampoUIInternal.MacWindowManager.launchWindow(for:resetPosition:animated:reason:completion:)
SpotlightUIInternal.WindowManager.toggleSpotlight(for: NSScreen)
SpotlightUIInternal.WindowManager.invokeSpotlightAndResetPosition(_:withReason:)
```

The `CampoUIInternal.tbd` export
`MacAssistantIslandSessionModel.searchManager -> SpotlightUIInternal.IslandSearchManager`
provides a concrete type-level bridge between the active Campo host and the separate
field/results components described below. Its `detachedHostIdentifier` returns an
`IslandHostIdentifier`, and `hostingWindowController` uses `MainWindowController`.

The installed
`/System/Library/PrivateFrameworks/CampoUIServices.framework/XPCServices/CampoRemoteService.xpc`
is a real XPC app service (`com.apple.CampoRemoteService`, `RunLoopType =
_NSApplicationMain`, `ServiceType = User`, `JoinExistingSession = true`). Its executable
imports `_NSViewServiceMain` and `NSServiceViewController` from ViewBridge. Defined
Objective-C classes and methods include:

```text
CampoUIPromptEntryServiceViewController
  exportedInterface
  remoteViewControllerInterface
  becomeKeyWithInitialQueryString:
  submitQuery
  invalidate

CampoLightweightUIServiceViewController
  exportedInterface
  remoteViewControllerInterface
  collapse
  expand
  updateAffordancePlacement:offset:

EditWithSiriServiceViewController
TextSuggestionsServiceViewController
```

It imports these specific AppKit interface functions:

```text
_NSRemotePromptEntryViewHostInterface
_NSRemotePromptEntryViewServiceInterface
_NSRemoteLightweightUIHostInterface
_NSRemoteLightweightUIServiceInterface
_NSCampoTextSuggestionsHostInterface
_NSCampoTextSuggestionsServiceInterface
```

They occur in the AppKit `.tbd`, but no declarations for these remote interfaces
were found in its public headers or arm64e Swift interface. `IntelligenceUI.PromptEntryView`
also appears in AppKit's linker exports, without a matching declaration in that Swift
interface. These exports are not evidence of public API status.

Binary strings identify `hostAppAuditToken`, `hostAppClientParameters`,
`sourceWindowIdentifier`, and `connectionIdentifier`; Security imports include
`SecTaskCreateWithAuditToken` and `SecTaskCopySigningIdentifier`. This establishes
identity-related machinery, not its exact use or a proven rejection policy. A static
call trace would be needed to establish where identity is checked and whether it is
used for authorization, context, attribution, or a combination.

**What this changes:** a private remote prompt-entry route is a concrete candidate
for further research. It is not yet established that it serves the Spotlight results
list, exposes the current search manager, or allows replacement of the system field.
The visible Spotlight capsule must not be conflated with a remote Siri editing or
text-suggestions service merely because those services coexist in the same app.

The parallel live probe initially observed a nearly screen-sized AX window
(`0,33,1470,923`) **during animation**. After settling, both CG and AX reported the
visible capsule window at `475,175,520,87`; the field was at `512,204,413,28`.
The screen-sized geometry is therefore a transition-state caveat, not the permanent
size of the host window. Its field reports `AXValue` writable but `AXPosition` and
`AXSize` nonwritable; its window reports position and size writable.

The subsequent AX position write requested `475,19` and returned success, with
readback at `475,33` consistent with a menu-bar clamp. The field moved to `512,62`.
Restoring the window to `475,175` restored the field to `512,204`. Thus moving the
settled native capsule was demonstrated on this configuration; this is still not
extraction or replacement of its view. Setting `SpotlightSearchField` to the
synthetic query `2+2` through CUA also produced the native Calculator result
`2+2 = 4`, demonstrating that its input reacts to an Accessibility value change.
These live measurements come from the
[companion AX report](spotlight-notch-live-probe-macos27.md), which is authoritative
for the UI experiment and its remaining lifecycle/positioning limitations.

### Imports used by Spotlight itself

`otool -L` reports direct dependencies on public AppKit and App Intents, together with
private `SpotlightUIInternal`, `SpotlightUIShared`, `SpotlightUIServices`, `SearchUI`,
`SearchFoundation`, `SpotlightServices`, `Spotlight`, and `CoreParsec`.

`nm -um` identifies imports from `SpotlightUIInternal`, including:

```text
WindowManager.launchWindow(for:resetPosition:animated:trigger:completion:)
WindowManager.dismissWindow(for:animated:reason:)
WindowManager.bootstrap()
WindowManager.windowIsVisible(domain:)
WindowManager.applicationLostFocus(withReason:)
MainWindowController
SPUIConnectionManager
SPUISpotlightKeyCommandManager
DockGestureXPCClient.windowCreated(_:)
```

These are specific dependencies of the system executable. They do not imply callable
IPC methods with the same names. Calling a function in our address space does not
invoke it in another process.

### Separate field/results components in the SDK

Swift demangling of exports from
`System/Library/PrivateFrameworks/SpotlightUIInternal.framework/Versions/A/SpotlightUIInternal.tbd`
under the inspected SDK reveals:

```text
IslandSearchFieldView.init(viewModel: () -> IslandSearchFieldViewModel)
IslandSearchResultsView.init(viewModel: () -> IslandSearchResultsViewModel)
IslandSearchFieldViewModel.init(islandManager: IslandSearchManager)
IslandSearchResultsViewModel.init(islandManager: IslandSearchManager)

IslandSearchManager.currentResults() -> [SFResultSection]?
IslandSearchManager.willStartQuery(SpotlightUIShared.Query)
IslandSearchManager.didReceiveResponse(SpotlightUIShared.QueryResponse)
IslandSearchManager.performCommand(SFCommand)
IslandSearchManager.clearSearch()
IslandSearchManager.desiredSearchHost: IslandHostIdentifier { get set }
IslandSearchManager.desiredResultsHost: IslandHostIdentifier { get set }

IslandControllerHost.registerContainer(_: NSView, for: IslandHostIdentifier)
IslandControllerHost.unregisterContainer(_: NSView, for: IslandHostIdentifier)
IslandControllerHost.isBoundContainer(NSView) -> Bool
IslandControllerHost.init(label: String, factory: () -> A)
```

The two views export SwiftUI `View` conformances. `IslandSearchManager` also exports
command and result-interaction delegates, an `allowResults` property, and a
`performScriptedTyping(profile:text:submitAfter:delayOverride:)` method. The latter
is a research clue about internal input automation, not a documented external
interface and not a method invoked during this study.

**Inference:** the host identifiers and separate view models indicate that Apple can
place its field and results in different internal containers. The signatures take
ordinary `NSView` instances and do not establish cross-process transport. The word
“Island” is Apple's symbol naming; it does not prove hardware-notch support.

No `.h` or `.swiftinterface` files were found in the SDK bundles for
`SpotlightUIInternal`, `SpotlightUIShared`, `SpotlightUIServices`, `SearchUI`, or
`SpotlightServices`. Their `.tbd` files describe linker exports, not sufficient Swift
type declarations, object layouts, initialization contracts, or authorization rules.
Consequently these types are not simply usable via a documented Swift import.

The corresponding runtime framework directories do not contain standalone dylib
files; the system dyld shared cache exists. `xcrun -f dyld_shared_cache_util` reported
that this utility is unavailable. No cache extraction was attempted. SDK exports are
therefore reported as SDK evidence, not as individually resolved runtime addresses.

### Query, result, and service boundaries

`SpotlightUIShared` exports a `QueryController` protocol with `start(query:)`,
`cancel()`, `activate()`, `deactivate()`, `currentQuery`, `lastQueryResponse`, and
`contextProvider`. `SpotlightServices` exports `SPSearchQueryContext`, `SPKQuery`,
`SPKResponse`, and `PRSSearchSession`. `SpotlightUIServices` has separate result
builders for files, calculator, dictionary, contacts, actions, and other categories.

This is evidence of multiple cooperating layers, rather than one public function
that returns everything displayed by system Spotlight. Protocol names and exports
alone do not establish a complete construction sequence or equivalent ranking.

System launch plists declare these concrete service names:

| System configuration | Declared Mach services relevant here |
| --- | --- |
| `LaunchAgents/com.apple.Spotlight.plist` | `com.apple.Spotlight`, `com.apple.private.spotlight.mdwrite`, `com.apple.Spotlight.Preferences` |
| `LaunchAgents/com.apple.corespotlightd.plist` | `com.apple.spotlight.SearchAgent`, `com.apple.spotlight.IndexAgent`, `com.apple.spotlight.IndexDelegateAgent` |
| `LaunchAgents/com.apple.corespotlightservice.plist` | `com.apple.corespotlightservice` |
| `LaunchDaemons/com.apple.metadata.mds.plist` | `com.apple.metadata.mds`, `com.apple.metadata.mds.legacy`, `com.apple.metadata.mds.xpcs` |

These declarations identify services, not public permission to use private protocols.
No XPC request was sent and no server-side client-identity or entitlement requirement
was inferred from the service name. The Campo remote-view service is verified, but
no contract that offers system Spotlight results as an embeddable third-party
surface was verified.

## What public APIs actually provide

| API | Useful capability | Boundary for this request |
| --- | --- | --- |
| `NSMetadataQuery` / `MDQuery` | Query indexed file metadata with predicates and search scopes; receive initial and live results | Data queries, not Spotlight's UI, action system, or full ranking contract |
| `CSSearchQuery` | Structured queries of indexed app content | Does not return an embeddable system Spotlight session |
| `CSUserQuery` | Typed queries and suggestions; semantic-search support from macOS 15 | App supplies its input control and results UI; complete system Spotlight parity is not promised |
| App Intents / indexed entities | Publish an app's actions and content for the system to surface and invoke | Integration into system surfaces, not ownership of Spotlight's field or arbitrary third-party actions |
| `NSWorkspace.showSearchResults(forQueryString:)` | Present a search-results window in Finder | Finder activates; this is not the Command-Space panel |

Apple's metadata guide documents scoped file queries. Its Core Spotlight guidance
uses app-supplied SwiftUI/AppKit search controls with returned results and suggestions.
The documented model concerns indexed app content. This study did not measure the
full set of data accessible to every macOS query configuration, so it does not assert
that every Core Spotlight query is necessarily restricted to one bundle.
[Metadata query guide](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html),
[search UI guidance](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app),
[structured query guidance](https://developer.apple.com/documentation/corespotlight/searching-for-information-in-your-app).

In particular, the local `CoreSpotlight.framework/Versions/A/Headers/CSSearchQuery.h`
lines 21–24 expose a macOS `allowMail` source option whose comment names
`com.apple.corespotlight.search.allow.mail`. This is a concrete access-related clue,
not evidence that Cascade has or can self-grant that entitlement. No Mail search was
performed.

Apple explains how App Intents expose app actions to Spotlight on Mac. That direction
of integration does not provide an API to import Spotlight's entire action picker
or its graphical components into Cascade.
[WWDC25: Develop for Shortcuts and Spotlight with App Intents](https://developer.apple.com/videos/play/wwdc2025/260/).
The `NSWorkspace` method explicitly presents results in Finder.
[NSWorkspace documentation](https://developer.apple.com/documentation/appkit/nsworkspace/showsearchresults(forquerystring:)).

## Security and distribution implications

The runtime protection boundary applies to modification of the target process.
Apple documents that SIP protects applicable processes against attachment and
`task_for_pid` access, and strips dynamic-linker environment variables on their
launch. The local `restricted` flag and enabled SIP are consistent with that boundary;
an injection or debugger-attachment attempt was neither necessary nor performed.
`Siri AI.app`, its executable, and the Campo remote-service executable also have the
`restricted` flag on this installation.
[Apple: Runtime Protections](https://developer.apple.com/library/archive/documentation/Security/Conceptual/System_Integrity_Protection_Guide/RuntimeProtections/RuntimeProtections.html).

Loading an Apple-signed framework into a third-party process is a different case.
Hardened Runtime library validation permits Apple-signed libraries as well as
libraries signed by the executable's own team. A private Apple framework is therefore
not automatically excluded solely because library validation is enabled. Successful
loading still says nothing about private service authorization or valid initialization.
Changing Cascade's runtime exception entitlements would affect Cascade, not grant
permission to patch Spotlight.
[Apple: Disable Library Validation entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation),
[Apple: Allow DYLD environment variables entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.allow-dyld-environment-variables).

`codesign -dvvv` on the legacy Spotlight executable reports `flags=0x0(none)` and a platform
identifier. `codesign -d --entitlements - --xml` warns that the binary contains an
invalid entitlements blob and does not produce a usable entitlement dictionary.
The deprecated `--entitlements :-` spelling produced the same warning, as did the
XML extraction attempts on Siri AI.app and CampoRemoteService.xpc. This is an
inspection limitation: do not interpret it as proof that Spotlight has no effective
entitlements, is unhardened in all respects, or is writable. The exact target-process
entitlements and private service authorization rules remain unresolved.

## Bounded next experiments

1. **Extend the demonstrated Campo integration across lifecycle states.** The current
   UI belongs to `com.apple.campo`; native query updates and moving/restoring the
   settled capsule have been demonstrated. Evaluate animation-phase geometry,
   subsequent layout changes, and the observed menu-bar clamp. Re-identify the
   owner on each supported OS/feature-flag configuration. The
   [companion AX report](spotlight-notch-live-probe-macos27.md) records these live tests.
2. **Deepen the private composition evidence statically.** In a development VM with
   matching OS/SDK, inspect the relevant dyld cache images and Objective-C metadata
   for `SPUIConnectionManager`, `MacAssistantIslandSessionModel`, and the
   `CampoUIPromptEntryServiceViewController` host/service interfaces. Seek a specific request
   protocol, response type, identity requirement, and remote-view endpoint before
   treating IPC hosting as viable. Absence of one symbol is not a rejection criterion.
3. **Test local component reuse only in a disposable harness.** First resolve the
   minimum class/symbol metadata without making a query; then determine whether
   field and results components can be initialized in a normal third-party process
   with standard security settings. Do not inject into the system app. Stop on
   entitlement rejection or initialization dependency rather than weakening security.
   A successful load is only milestone one; a viable prototype must demonstrate
   synthetic query updates, cancellation, result activation, IME, focus, cleanup,
   and bounded idle resources.
4. **Use synthetic data for any query comparison.** An isolated account with a small
   set of known files and donated app entities can compare public metadata/Core
   Spotlight queries with system behavior. This measures coverage; it does not
   replace proof that the private UI can be hosted.

The next product decision should distinguish “retain the running system panel and
control its input externally” from “reuse Apple's private components in our process.”
Only the former keeps the existing system session by construction. The private
symbols make the latter a concrete experiment, not a feature ready to implement.

## Reproducing the static evidence

Read-only commands used for the main evidence:

```sh
sw_vers
xcode-select -p
xcrun --sdk macosx --show-sdk-path
plutil -p /System/Library/CoreServices/Spotlight.app/Contents/Info.plist
otool -L /System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight
nm -um /System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight
csrutil status
ls -ldO /System/Library/CoreServices/Spotlight.app
ls -lO /System/Library/CoreServices/Spotlight.app/Contents/MacOS/Spotlight
codesign -dvvv /System/Library/CoreServices/Spotlight.app
codesign -d --entitlements - --xml /System/Library/CoreServices/Spotlight.app
plutil -p /System/Library/LaunchAgents/com.apple.Spotlight.plist
plutil -p /System/Library/LaunchAgents/com.apple.corespotlightd.plist
plutil -p '/System/Applications/Siri AI.app/Contents/Info.plist'
plutil -p /System/Library/LaunchAgents/com.apple.campo.plist
otool -L '/System/Applications/Siri AI.app/Contents/MacOS/Siri AI'
nm -um '/System/Applications/Siri AI.app/Contents/MacOS/Siri AI'
nm -arch arm64e /System/Library/PrivateFrameworks/CampoUIServices.framework/XPCServices/CampoRemoteService.xpc/Contents/MacOS/CampoRemoteService
xcrun -f dyld_shared_cache_util
```

For Swift signatures, extract the quoted `_$s…` exports from each named `.tbd` using
a text parser and pass those strings on standard input to
`xcrun swift-demangle --compact`. This only demangles linker names. It does not load
the framework or communicate with any Spotlight service.
