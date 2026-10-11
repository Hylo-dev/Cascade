# Services, storage and assets

**Mostly planned.** Two services exist, `audio.system` and `audio.apps`, described below. The rest of this page is not built: `PluginContext` names only the plugin, the engine offers no client calls, and a feature that declares any service other than those two is unavailable. This page keeps the rules the plugin engine spec fixed, and the ones carried over from the v1 addon runtime, so that the services and Music sub-project, which brings the next services, starts from them.

## What exists: `audio.system`

`audio.system` is a kernel service: the app's `SystemAudioService` owns the system audio on its own queue, and the components `audio.volumeBar`, `audio.mixer` and `audio.outputPicker` read and command it directly, never through the plugin. It covers the global volume, mute, the system output device, and a multi-output: the system output played on several devices at once, through an aggregate device the service creates and removes. The Audio plugin (`com.cascade.audio`) declares the service and the three components, and publishes the same two documents, one per surface, whatever the volume does. It has no client call: the plugin never reads the service, so the synchronous client calls below are not needed for it.

## What exists: `audio.apps`

`audio.apps` is the second kernel service of the Audio plugin: the volume, mute and output of each app that plays audio, through `AudioHost`, a second bundled XPC service beside PluginHost. The plugin declares it together with the permission `audio.capture`, which the kernel grants a bundled plugin like any other; the system's own "System Audio Recording" permission is asked once, by Cascade, at the first real per-app control, never on opening the mixer. Like `audio.system`, it has no client call: `AppAudioService` in the app owns it, and `audio.mixer` reads and commands it directly through `AudioMixerModel`.

- **What the user asked for** is an intent per app, `{ gain, isMuted, outputs or follow the system }`, kept by bundle ID in `AudioIntentStore` and sent to `AudioHost` whenever it starts, so a restart loses nothing. A device that is gone never erases a preference.
- **What `AudioHost` does** is discover the apps producing audio without polling, group helper processes under their app, and run a pipeline only for an app that is not at 100 %, unmuted and following the system: a process tap that mutes the app, a private aggregate holding the tap and the outputs, and a render kernel in C that applies the gain and the mute. An app left at its defaults has no tap and costs nothing. Changing an app's outputs crossfades the old pipeline into the new one.
- **Failures are contained** as with PluginHost: every command has a 3 second deadline, past which Cascade kills `AudioHost` and counts a fault; it is also restarted past 64 MiB; after a pause of 1, 5 and 30 seconds it comes back and the intents are replayed. Three faults in five minutes and Cascade gives up: per-app audio returns to native and Settings (Widget page, Plugins section) shows `AudioHost` with Restart.
- **Cost at rest.** `AudioHost` runs only while an intent needs enforcing or the mixer is visible, and has no timer while it waits.
- **Denied permission is not yet measured.** What macOS does to a muting tap when the permission is refused has not been recorded, so the snapshot's `captureAllowed` stays unknown until it is, and the mixer treats unknown as allowed. The mixer already draws the read-only columns and the banner to System Settings for a `false` answer.

## Services

A service is a call a plugin makes, declared per feature in the manifest's `services`. Plugins stay thin: heavy or privileged work lives in services, placed by the rule of spec §6.

| Place | Rule | Members planned for v1 |
| --- | --- | --- |
| Kernel | Touches frames, input or the notch window, or updates the UI more than about ten times a second | Spectrum capture (Core Audio tap), the spacebar and Spotlight input taps, the file shelf, Spotlight |
| PluginHost | Talks to other apps or parses system data at human frequency | Now playing and Music commands (AppleEvents), Bluetooth, power, network |

The service-fed components, `audio.volumeBar`, `audio.mixer` and `audio.outputPicker` today and `audio.spectrum` and `media.scrubber` later, bind only to kernel services and get their data from them directly, never through the plugin; the other four components drawn today take the parameters their plugin passes (see [Content](content.md)). Data born in PluginHost reaches the kernel as publication data: artwork, for example, will travel through the asset pipeline. Volume, which spec §6 placed in PluginHost, is a kernel source today, beside the volume key tap it shares a subsystem with.

The SDK's client calls will be synchronous: each blocks the plugin's own thread with a timeout, and returning past the kernel's 250 ms deadline still counts as a hang. A plugin cannot make two client calls in parallel, which is acceptable for thin, event-driven plugins.

## Grants

- Everything is declared in the manifest, first-party included; undeclared use is denied.
- Grants are rechecked on every call and revocable per plugin with immediate effect: the service stops answering, its shared source stops when its last holder goes, and a component shows its unavailable state. The kernel already does this for sources and actions (`PluginEngine.revoke` and `grant`).
- A sensitive tier-2 component, such as `audio.spectrum`, activates only when both macOS (TCC) and the grant allow it. TCC is asked once, for Cascade, at the first real use; spike S2 showed that macOS attributes PluginHost's Automation and Bluetooth requests to Cascade.

## Shared leases

A service a plugin uses through a long-lived subscription is shared like a source: it starts with its first lease and stops with its last (`PluginSourceLeases` does this for sources today). A tier-2 component's service runs while at least one instance of the component is visible, and stops with the last.

## Storage and assets

- **Caps.** Assets: 8 MiB per plugin. Storage: 10 MiB of data and 20 MiB of cache per plugin. These are the v1 runtime's figures, kept as the starting values.
- **Ownership**, carried over from the v1 runtime. A plugin's storage and assets belong to the identity the host verified for it, never to an id the plugin states. A plugin reads and writes only its own; nothing reaches another plugin's except through a grant the host checks on every call.

## Where the earlier work is

The v1 addon runtime implemented most of these pieces and was deleted once this engine replaced it. Its service broker (`ServiceBroker`), keyed storage (`AddonKeyedStorage`), bounded assets (`BoundedAsset*`), scheduling (`DeadlineQueue`, `AddonScheduler`) and memory episodes (`ProviderMemoryEpisode`) can be read at commit `302cead`, the last that holds the whole runtime. Spec §15 says how they come back: the pure value types as they are, the actors unwrapped into value types behind a `Mutex`.
