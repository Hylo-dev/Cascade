# Interactive notch: haptics, Bluetooth and a Live Activities base

Status: approach confirmed by the user on 4 September 2026, with haptics at the start of the hover. Accessibility and private integrations allowed with capability verification.

## Goal of the first tranche

Make the controls in the notch usable, add a haptic pulse at the start of the hover and present Bluetooth connection events. Introduce the contract and the surfaces for persistent activities, starting with the groundwork for music and media. Keep macOS 14 as the minimum and the existing AppKit/Core Animation engine.

Replacing the native Bluetooth notices is an explicit requirement. Detecting a connection and suppressing the macOS notice are separate capabilities: both require verification, and the first one working does not prove that the second one works.

## Findings in the project

- `NotchEngine` is the public boundary of the `CascadeKit` package; the integration services can stay in the app, with dependencies injected through protocols.
- `NotchController` coordinates hover, display, state and springs. Per-frame changes do not invalidate SwiftUI and the display link stops when the animation settles.
- `NotchPanel.ignoresMouseEvents` is always `true`; `NotchHostView.hitTest` returns the container instead of the hosted controls. The current widgets are therefore not an already working base for interactive buttons.
- `NotchState` describes the open sides. It does not represent the distinction between compact activity, expanded activity, widget page and transient notice.
- `NotchGeometry` ties height and side extension to the same progress: a Live Activity must instead be able to widen the notch while keeping its compact height.
- The widgets follow `activate`/`suspend`. The future event monitor must have a lifetime independent of the page's visibility.
- The app uses the red debug configuration and registers eleven demo clocks. The tranche must replace this demo composition with a verifiable example of the new capabilities.

## Approaches evaluated

1. **Extend the current engine and introduce an activity coordinator: recommended.** It keeps geometry, window and animation; it separates the system services from the presentation. It adds only the contracts needed for the first tranche.
2. **Implement Bluetooth and music as normal widgets.** It is shorter at first, but their lifecycle would end when the page closes and would not cover the persistent compact surfaces.
3. **Port the BoringNotch coordinator.** It offers examples of behavior, but it is coupled to many managers and dependencies. It does not directly solve the Bluetooth override and would also require an explicit choice about copying GPL-3.0 sources.

## Proposed behavior

### Interactions and haptics

- Hover keeps the current opening and the hysteresis against pointer jitter.
- Clicks reach the SwiftUI controls only inside the actually interactive outline. The rest of the band lets clicks through to the menu bar and to other apps.
- The panel stays nonactivating. This tranche does not require handling typing in future search fields.
- A single AppKit `.alignment` pulse is requested on entering hover, before starting the morph. Staying in hover generates no further pulses; music updates and automatic notices do not repeat the vibration.
- Haptics can be turned off. Actual availability depends on hardware and macOS preferences.

### Activities and priority

- A public contract for Live Activities exposes a stable identity, leading/trailing compact content, expanded content and change notifications.
- A separate presentation state decides the visible content; `NotchState` keeps its existing meaning of which sides are open.
- Persistent activities stay registered while a transient notice occupies the notch. At expiry the current activity returns, without recreating its provider.
- A manual selection that is already open is not suddenly replaced by an event: the notice stays a compact presentation or waits within a bounded expiry.
- The first tranche shows a single persistent activity in the foreground. Identity and registration must allow several activities, but visual selection between simultaneous activities does not implicitly enter this release.
- For Bluetooth notices: proposed duration of four seconds, coalescing per device and a bounded queue. No replay of old events on return from the lock screen.

### Bluetooth

- Monitor through `IOBluetoothDevice` connection and disconnection callbacks; initial read of the already connected devices without showing them as new connections.
- Stable device identity to deduplicate callbacks. Fast reconnections must be coalesced without ignoring a real later connection.
- Notice with name, category/icon and state. An unknown battery stays absent; no invented value and no periodic scan with `system_profiler`.
- An explicit lifecycle releases the registrations on stop and rebuilds the state after sleep/wake without a burst of backlogged notices.
- Coverage must distinguish between Classic devices exposed by IOBluetooth and BLE-only peripherals; a universal inventory from the Classic monitor alone is not promised.

### Override of the native notices

- Define a suppression interface separate from the monitor: available, authorization required, unsupported, error.
- First verify the origin and behavior of the notices on the local macOS, which is **27.0 beta**, then on the supported release versions.
- Closing via Accessibility after the banner appears can leave a brief flash of it: it must be called closing, not preventive suppression.
- Prefer a selective and reversible intervention on the relevant notice only. Do not globally disable Notification Center, Focus or the Bluetooth services to simulate the override.
- When a verified replacement is not available, expose the unsupported state; do not declare the requirement completed. The exact technique stays subject to verification on the system and to the choice about private integrations.

### Music groundwork

- Define immutable snapshots for source, title/artist, playback, duration, position with timestamp and command capabilities.
- Separate the music provider from the compact/expanded content: metadata and commands arrive through the contract, with no references to the notch controller.
- Verify the presentation with a deterministic demo provider, active only in demo/test mode and clearly identified.
- The real connection to Apple Music, Spotify and browsers is the next step: the current request is interpreted as groundwork. The contract must allow a Now Playing adapter without changing the renderer.

## Resources and concurrency

- No periodic polling for connections or metadata, no display link active at rest.
- A single cancellable expiry for the notice in the foreground; no per-item timer in the queue.
- UI and coordination on the main actor. IO, image decoding and any blocking operations on dedicated workers.
- Keep only lightweight snapshots; create and release views and images according to the visible presentation.
- Publish only actual changes. Separate music progress from metadata; any progress bar has updates managed by the host and suspended when not visible.
- Idempotent start and stop, task cancellation and no callback able to reactivate a service already stopped.

## Planned verification

- Deterministic tests for presentation transitions, preemption and restore, deduplication, expiries, bounded queue and restart.
- Haptic tests with an injected performer: one pulse on entering hover, none while staying, on automatic update or when turned off.
- Tests of the compact geometry and of the move between compact and expanded without losing the springs' current position.
- Tests of event routing to the controls and outside the outline, including points inside the bounding box but outside the rounded corners.
- Build of CascadeKit and of the app with the local Xcode, keeping the pre-existing change to the signing team intact.
- Manual verification needed for perceived vibration, clicks on the menu bar, real Bluetooth devices, override without duplicates, sleep/wake, lock, Mission Control and multiple displays.
- Measure at rest and during transitions: the mere absence of timers in the code does not prove that an energy budget is met.

## References examined

- [BoringNotch, the fork indicated](https://github.com/leekangmmin/boringNotch/tree/e15691026b577caeb721e4ec1865e5a9975e2db1): `ContentView.swift` uses sensory feedback; `NowPlayingController.swift` receives a stream from MediaRemoteAdapter and sends commands through MediaRemote. Bluetooth still appears in the roadmap, with no Bluetooth service in the sources consulted.
- [Original BoringNotch](https://github.com/TheBoredTeam/boring.notch/tree/99900bf630a3d3e97fae079df2175993318d51f7): similar structure for media; no Bluetooth implementation found in the snapshot consulted.
- [BoringNotch fork license](https://github.com/leekangmmin/boringNotch/blob/e15691026b577caeb721e4ec1865e5a9975e2db1/LICENSE): GPL-3.0. This survey does not incorporate external sources.
- [Apple: IOBluetooth connection callback](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/register(forconnectnotifications:selector:)).
- [Apple: NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager).

## Decision

The user confirmed the first tranche and corrected the haptics to the start of the hover. The research available does not yet prove a universal preventive suppression: the implementation must make the actual limits observable.
