# Sapphire and FineTune: glass, audio and verified limits

Research of 4 September 2026 for the decision **Assess glass and audio from the Sapphire and FineTune sources**. It is a static reading: no downloaded app was run, no compatibility was measured. Snapshots: [Sapphire, commit e718d72f][s-commit] and [FineTune, commit 2285279d][f-commit]. The behaviors described as facts are implemented in the sources; the proposals for Cascade are explicitly inferences to be validated.

## Sapphire's glass

**Fact.** In the notch, `notchBackground` enables the glass path only with `#available(macOS 26.0, *)` and `appearance.usesLiquidGlass`. It composes `LiquidGlassShapeFill` on the active outline, with behind-window blending and a dark appearance, plus a fill configurable by color/gradient and opacity. On earlier systems it uses an optional `NSVisualEffectView` with HUD material, fill and clipping to the outline. So the result on macOS 14 is not the same glass renderer used on 26. [Notch implementation][s-background]

**Fact.** The SwiftUI/AppKit wrapper dynamically constructs `NSGlassEffectView` through `NSClassFromString`. If the class is missing it falls back to `NSVisualEffectView`. For the glass, besides public properties such as style, tint and radius, it invokes internal selectors: `_variant`, `_interactionState`, `_adaptiveAppearance`, `_contentLensing`, `_scrimState`, `_subduedState`. The intensity selects materials/variants and parameters. The code configures the transparent window, applies a `CAShapeLayer` mask, recursively searches for layers named `CABackdropLayer`, sets `windowServerAware=true` and `scale=1`, and uses KVO to maintain them. It is not just a semi-transparent SwiftUI surface. [Complete wrapper][s-glass]

**Inference for Cascade.** The visual direction is reusable as a reference, but copying the internal mechanism introduces a dependency on undocumented details. The prototype must compare the public `NSGlassEffectView` API on macOS 26 with an AppKit material on macOS 14, with its own outline, tint and edges. The Apple header of the local SDK confirms availability 26 for `NSGlassEffectView`; its public interface does not expose the internal variants used by Sapphire. Identity with the Siri effect shown in the attachment is not verified. [Apple API][apple-glass]

## Other relevant ideas, without new requirements

Sapphire implements activity categories such as music, timer, file shelf, Bluetooth, audio switch, notifications, battery and file progress, with a numeric priority order. This is an example of arbitration between events, not an open protocol: the enumeration contains cases known at compile time. Cascade's extension model remains a separate decision. [LiveActivityManager][s-activities]

The Bluetooth monitor registers `IOBluetoothDevice` connections and disconnections. The notification system instead reads Notification Center's SQLite database, with a modern path and legacy paths, parsing of internal plists and a default polling of five seconds. It is evidence of a concrete technique for other apps' notifications, not proof of a universal public API or of immediate and complete delivery; access, schema and behavior on the supported versions have to be verified separately. [Bluetooth][s-bluetooth], [NotificationManager][s-notifications]

For Now Playing, Sapphire launches a process that uses a Perl script and a bundled `MediaRemoteAdapter.framework`; it reads updates and sends transport commands through the adapter. FineTune's PCM capture does not by itself provide title, artwork or play/pause control: the two integrations have to be planned separately. [NativeMediaController][s-media]

## FineTune: what makes the mixer possible

**Fact.** `AudioProcessMonitor` observes `kAudioHardwarePropertyProcessObjectList`, aggregates the audio processes into applications and keeps listeners and periodic refreshes. To attribute helpers/XPC it also uses `responsibility_get_pid_responsible_for_pid`, a private API resolved with `dlsym`, then falls back to walking up the process tree. This is relevant for Safari/WebKit and Chromium browsers: identifying the app is not the same as identifying every tab or every track. [Process monitor][f-process]

**Fact.** For an app, `ProcessTapController` creates a private `CATapDescription` on its `AudioObjectID` values, with `.mutedWhenTapped`: the original output is suppressed while the tap is active and the audio is played through the controlled path. It tries a tap on a device's stream to preserve channels, then falls back to a stereo mixdown. It creates a private aggregate device that contains tap and output; the callback reads the buffers, applies level/mute and writes the output. This path does not install an additional audio driver; it uses HAL objects created at runtime. [Creation and start][f-tap]

**Fact.** Multiple output is implemented in the same aggregate: first device as the clock, drift compensation on the others and stacked mode when the signal has to be replicated. Aggregates chosen by the user are flattened into their subdevices; there are specific rules for tap compensation with Bluetooth and virtual sources. The code does not justify a promise of identical latency or perfect synchronization between any pair of devices. [Aggregate plan][f-aggregate]

**Inference.** The per-app volume, routing and simultaneous outputs requested by the user are technically plausible without including EQ in the first version, but they constitute a persistent audio engine. They must not be tied to the lifecycle of the SwiftUI page or to the presence of the open notch. The cost is not just sliders: formats, sample rates, clocks, browser helpers, Bluetooth calls and reconnections require verification on real hardware.

## Permissions and versions

Apple documents Core Audio taps from macOS **14.2** in the official sample: `NSAudioCaptureUsageDescription` is required; starting recording on the aggregate with the tap triggers the system audio consent. The tap can capture groups of processes and mute their output. This confirms the primitive, not the whole FineTune app. [Apple sample][apple-taps]

**Repository facts.** FineTune declares 15.0 in the README, but the project in the snapshot sets **15.4**. The app targets have the sandbox disabled, the hardened runtime enabled and the `ENABLE_TCC_SPI` flag active. `AudioRecordingPermission` uses the private TCC framework for preflight and request; without that flag it assumes the authorized state, which does not demonstrate a consent that is actually present. [Build configuration][f-project], [Consent handling][f-permission]

There are usage descriptions for system audio, microphone and Bluetooth, and audio-input/Bluetooth/network-client entitlements. The controller tries to disable the microphone streams of duplex devices to avoid unnecessary requests; a failure can let the prompt appear. Permissions should therefore be presented per actual capability, without promising that per-app audio always, or never, requires the microphone. [Info.plist][f-info], [Entitlements][f-entitlements], [Input streams][f-input]

## Callbacks, UI and reliability

**Fact, with a documentation correction.** The controller is `@MainActor`; the processing is `nonisolated`, with `nonisolated(unsafe)` shared state. A comment claims that the callback runs on the HAL thread, ignoring the queue passed in. Apple instead specifies that `AudioDeviceCreateIOProcIDWithBlock` dispatches **synchronously on the supplied queue**, or invokes the block directly if the queue is null. FineTune passes a dedicated queue, not the main one: the comment must not be turned into a Cascade specification. [Controller][f-thread], [Apple contract][apple-ioproc]

**Inference.** The code is useful as a study, but it does not certify concurrency safety: `nonisolated(unsafe)` removes checks, it does not replace synchronization and management of data lifetime. What is needed: separation between UI state and callback, preallocated data, controlled updates, no waiting on UI/I/O in the path that produces audio, and underrun measurements. Meter updates must be able to slow down when the widget is invisible without interrupting the routing.

FineTune distinguishes asynchronous teardown and awaited teardown; the latter precedes re-creation. The order is device stop, destruction of IOProc, aggregate and tap. For an output change it attempts a crossfade with two paths and has a destructive re-creation; it has recovery of inactive taps, cooldown and re-creation on a Bluetooth sample rate change. At launch it cleans up orphaned aggregates: the source flags the risk that a crash leaves application audio muted. [Resources][f-resources], [Switch and invalidation][f-switch], [Recovery][f-recovery], [Orphans][f-orphans]

## Decisions that these facts make necessary

1. **macOS minimum:** Cascade currently sets 14.0. An engine based on taps requires at least a 14.2 gate; directly reusing the current FineTune is not a verified port for Sonoma. Assess a higher minimum or reduced capabilities on earlier systems. [Local Cascade project](../../../Cascade.xcodeproj/project.pbxproj)
2. **Audio fallback:** if consent, tap or device fail, proposal to be validated: restore the macOS path and disable the affected routing, keeping the preferences. Do not declare as working a slider that does not control the audio.
3. **Audio prototype:** verify browsers/helpers, apps with their own routing, two outputs with different clocks, Bluetooth during a call, USB duplex, hotplug, sleep/wake, crash and restart; measure latency, drops and consumption without EQ.
4. **Glass prototype:** compare macOS 14 and 26, displays with/without a notch, scaling and accessibility. The approved appearance and the acceptance of internal APIs are separate human decisions.

These are verification proposals, not decisions already approved. No builds, audio tests, profiling or permission tests were run.

## Declared licenses and provenance

Sapphire declares **AGPL-3.0**; FineTune **GPL-3.0**. This report describes behavior and references, without incorporating code. Visual/functional inspiration, dependency and copying of sources are distinct choices; neither of the last two is decided here. [Sapphire license][s-license], [FineTune license][f-license]

[s-commit]: https://github.com/cshariq/Sapphire/commit/e718d72feba61538a61ffc14e3abc32a9b4e35b9
[f-commit]: https://github.com/ronitsingh10/FineTune/commit/2285279d36d3f8115c1c2d4aecd904f1bdf96a51
[s-background]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Notch/NotchController.swift#L656-L696
[s-glass]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Utilities/LiquidGlassView.swift
[s-activities]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/LiveActivities/LiveActivityManager.swift#L16-L99
[s-bluetooth]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Bluetooth/BluetoothManager.swift#L58-L81
[s-notifications]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Miscellaneous/NotificationManager.swift#L197-L306
[s-media]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Music/NativeMediaController.swift#L135-L285
[s-license]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/LICENSE
[f-process]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L91-L177
[f-tap]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L530-L705
[f-aggregate]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L295-L412
[f-project]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune.xcodeproj/project.pbxproj#L364-L493
[f-permission]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Permission/AudioRecordingPermission.swift
[f-info]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Info.plist
[f-entitlements]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/FineTune.entitlements
[f-input]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L454-L497
[f-thread]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L6-L50
[f-resources]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/TapResources.swift
[f-switch]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L708-L877
[f-recovery]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L1881-L2000
[f-orphans]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/OrphanedTapCleanup.swift
[f-license]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/LICENSE
[apple-glass]: https://developer.apple.com/documentation/appkit/nsglasseffectview
[apple-taps]: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
[apple-ioproc]: https://developer.apple.com/documentation/coreaudio/audiodevicecreateioprocidwithblock(_:_:_:_:)
