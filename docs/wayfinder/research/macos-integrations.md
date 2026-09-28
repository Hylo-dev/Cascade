# Integrate Spotlight, notifications and macOS activities: feasibility

Wayfinder research of 4 September 2026. Baseline to assess: project with a macOS 14 deployment, direct distribution and Homebrew. This note documents possibilities and limits, without choosing the product behavior. Apple documentation, the local macOS 27.0 SDK and public sources were read; no personal databases were opened, no events intercepted, no permissions changed and no behaviors tested on the user's UI.

Pinned sources: Sapphire `e718d72feba61538a61ffc14e3abc32a9b4e35b9`; FineTune `2285279d36d3f8115c1c2d4aecd904f1bdf96a51`. The presence of code demonstrates an implemented technique, not its reliability on every version of the system.

## Feasibility matrix

| Capability | Reference OS | APIs and permissions | Evidence and limit |
|---|---|---|---|
| Invoke the real Spotlight | macOS 14 and later | System shortcut; automation possibly with Accessibility | Interactive opening is documented; automatic integration to be tested. |
| Move Spotlight under the notch | Every supported version | Public Accessibility, if `AXPosition` is settable; Accessibility authorization | Possible experiment, not a documented Spotlight contract. |
| Change the material, the shape, or host Spotlight inside Cascade | No verified API | Possible private/undocumented mechanisms | Do not promise control of another process's UI. |
| Search drawn by Cascade | macOS 14; additional capabilities from 15 | AppKit/SwiftUI, `NSMetadataQuery`, Core Spotlight | UI and file search possible; complete functional parity not demonstrated. |
| Own notifications | macOS 14+ | `UNUserNotificationCenter`, Notifications authorization | Public API limited to one's own app/extension. |
| Notifications from non-integrated apps | 14/15/26/27 matrix to be tested | Accessibility or private database/SPI; distinct permissions | Universal coverage not guaranteed; Accessibility is not the same as database access. |
| Bluetooth connections | macOS 14+ | Public IOBluetooth; CoreBluetooth and its authorization when used | Detection available; verify Classic, BLE, wake and profile changes. |
| Battery of every accessory | Depends on device and OS | Public GATT where exposed; otherwise undocumented caches/properties | Optional data; no verified universal source. |
| Global media metadata and commands | 14 and later versions, with differences | Private MediaRemote; adapters for individual apps | Feature achievable in existing projects, but fragile and dependent on the players. |
| Audio/process detection and capture | Taps from macOS 14.2 | Public HAL/Core Audio; audio recording consent for capture | Audio activity does not mean an available title nor an audible signal. |
| Vibration on opening | macOS 10.11+ | `NSHapticFeedbackManager`, hardware and user preferences | Public request; the system can suppress it. |
| iPhone activities in the notch | System menu bar from macOS 26 | System ActivityKit/Continuity | No verified contract for transferring other parties' activities into the Cascade host. |

The sources and conditions of the rows are detailed below. Distribution outside the Store does not turn private APIs or internal stores into supported interfaces and does not remove the system's checks.

## Spotlight: four different capabilities

Apple documents Command-Space as the command to open and close Spotlight. For Cascade, the invocation of the system app and, separately, the simulation of the shortcut have to be verified: shortcuts changed by the user, focus and an already open state can alter the result. The public method `NSWorkspace.showSearchResults(forQueryString:)` instead opens a **Finder** search window: it does not embed the Spotlight panel. [Apple shortcuts](https://support.apple.com/en-gb/guide/mac-help/mh26783/mac), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace/showsearchresults(forquerystring:)).

Accessibility makes it possible to query a process's UI and check whether an attribute is writable. This offers an experimental path for positioning, but Apple does not guarantee here that the Spotlight window exposes a settable position. `AXUIElementIsAttributeSettable`, the outcome of the change and the behavior in subsequent updates have to be checked. The authorized Accessibility client state is required; the API can also return an unsupported attribute or a communication error. [Settable attributes](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable), [Accessibility authorization](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

No public API was found to replace Spotlight's material, modify its SwiftUI/AppKit hierarchy or host it as Cascade content. An alignment of separate windows, if it worked, would not demonstrate these capabilities. This is a case of **no documented contract found**, not a demonstration of absolute impossibility.

An own search can use `NSMetadataQuery` for file and volume metadata and draw the panel freely. Core Spotlight also makes it possible to query content indexed by the app; the documentation introduces semantic search from macOS 15. This is not the same as having all the sources, actions and capabilities of the real Spotlight. The "identical" request still has to be broken down into an observable comparison before estimating a replica. [Metadata search](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html), [Core Spotlight search interface](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app).

## Notifications from other apps

`UNUserNotificationCenter` handles the notifications of one's own app or extension. Its authorization does not offer a stream of the notifications received from all the other applications. [Apple documentation](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter).

An Accessibility observer receives events from the UI elements supported by the observed app. AX events are not automatically the payloads of user notifications; moreover, the global Accessibility object does not support such observations. Reading banners or Notification Center through AX is therefore a candidate to prototype with the Accessibility permission, not a universal listener. Absence of banners, grouping, hidden previews and Focus require distinct cases. [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification), [Notification settings](https://support.apple.com/guide/mac-help/notifications-settings-mh40583/mac).

Sapphire uses another technique: `NotificationManager` opens Notification Center's internal SQLite read-only, periodically queries `record` and decodes a plist with internal keys. The path expected from Sequoia on is `~/Library/Group Containers/group.com.apple.usernoted/db2/db`; historical fallbacks under `DARWIN_USER_DIR` are present. The default polling is five seconds. This demonstrates the attempted access to the stored records, not the real-time interception of every event. Path, schema, retention and payload do not constitute an Apple API. [Sapphire: verified source](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Miscellaneous/NotificationManager.swift#L197).

Sapphire also has Full Disk Access checks, with dynamically loaded TCC SPIs and a fallback. This **does not demonstrate** which permission is necessary and sufficient for that specific store on every macOS. The verification must measure denied/granted access in a test account; no reading of real data took place during this research. Still to be decided, after the measurements: acceptable coverage, duplication of banners, retention and handling of protected previews. [Sapphire: permissions](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/App/PermissionsManager.swift#L137).

## Bluetooth and battery

`IOBluetoothDevice.register(forConnectNotifications:selector:)` registers connection callbacks; disconnection is observed on the device. Sapphire does use this path. For BLE, `retrieveConnectedPeripherals(withServices:)` filters devices by services: it does not return an indiscriminate inventory of all accessories. CoreBluetooth interaction requires its authorization and usage description. [IOBluetooth](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/register(forconnectnotifications:selector:)), [CoreBluetooth](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/BestPracticesForInteractingWithARemotePeripheralDevice/BestPracticesForInteractingWithARemotePeripheralDevice.html), [Apple permissions](https://developer.apple.com/documentation/technologyoverviews/device-sensors).

Sapphire combines reading the GATT Battery Service, the Bluetooth cache, specific properties and `system_profiler` output. The availability of left/right/case battery depends on the source; cached data can be stale. A connection must therefore not be interpreted as a guarantee that the battery is available. Changing the audio output and connecting a device are also different events, to be correlated in the future specification. [Sapphire: battery](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Bluetooth/BluetoothBatteryReader.swift), [Connections](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Bluetooth/BluetoothManager.swift).

## Global media, browsers and activities

`MPNowPlayingInfoCenter` publishes information about the media played by one's own app: it is not documented as a global reader. The new NowPlaying framework presented at WWDC26, available in the SDK from macOS 27 and still documented as beta, likewise serves to publish local sessions or sessions of remote devices. It does not automatically solve reading other parties' sessions. [Media Player](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter), [NowPlaying](https://developer.apple.com/documentation/nowplaying).

Sapphire launches `/usr/bin/perl` with `MediaRemoteAdapter.framework` to receive metadata and send commands. The adapter's author describes this mechanism for support also after macOS 15.4, using a system binary with access to MediaRemote. It is a private path to be verified on every version, not an Apple guarantee. Artwork, title, controls and player identification can be missing; the adapter itself documents null results and optional metadata. [Sapphire: controller](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Music/NativeMediaController.swift#L134), [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter).

Core Audio instead offers public process taps from macOS 14.2, with audio recording consent and `NSAudioCaptureUsageDescription` for capture. The HAL properties distinguish active I/O and active output stream; they do not certify a non-silent signal and do not provide the title or URL of the browser tab. FineTune observes the audio processes and also uses the private `responsibility_get_pid_responsible_for_pid` to trace helpers/XPC back to the responsible app. Browser, tab, audio process and Now Playing session must remain distinct identities. [Apple taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), [Output state](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess/isrunningoutput), [FineTune: monitor](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L88).

Cascade's "live activities" are a product model to be specified. ActivityKit does not provide a universal list: `Activity.activities` concerns the activities of one's own app. Apple documents the arrival of activities **from iPhone** in the Mac menu bar from Tahoe 26 through iPhone Mirroring; this does not authorize a third-party host to transfer them into its own notch. In the local 27.0 SDK, `Activity` and `ActivityAttributes` remain marked unavailable for macOS. [Activity](https://developer.apple.com/documentation/activitykit/activity), [Continuity and Live Activities](https://support.apple.com/en-us/120684).

## Haptic feedback and required experiments

AppKit offers public haptic feedback since 10.11. A pulse synchronized with rendering can be requested on opening. `defaultPerformer` takes the device and the preferences into account; the official comment in the SDK specifies that the system can suppress the request, for example if the finger is not touching the trackpad. A vibration that is always perceptible after a hover therefore cannot be guaranteed. [NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager); local verification: `AppKit.framework/Headers/NSHapticFeedback.h`, lines 15–38, macOS 27.0 SDK.

Before the product decisions, narrowly scoped experiments are needed:

1. Spotlight: opening, AX attributes and positioning on 14/15/26/27, multiple screens, fullscreen, Spaces, repeated opening and custom shortcut. Compare an own UI only after measuring the system one.
2. Notifications: test account and synthetic notifications from different apps; disabled banners, Focus, hidden previews, groups, logout, restart and permission revocation. Measure coverage, latency and duplicates separately for AX and for the store.
3. Media: Safari/Chromium, multiple tabs and concurrent players, pauses, streams without metadata, protected content, output change and revocation of audio consent. Verify 14.0 against 14.2 and later versions.
4. Devices and haptics: Apple/non-Apple headphones, BLE keyboard/mouse, missing or stale battery, sleep/wake, internal/external trackpad and mouse. Record "unavailable" states separately from errors.

These experiments clarify support boundaries; none was run in this documentation research.
