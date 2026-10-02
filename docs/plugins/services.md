# Services, storage and assets

**Planned, not built.** Nothing on this page exists in the plugin engine yet. `PluginContext` names only the plugin, `PluginEngine` is composed with no services, and a feature that declares a service is unavailable. This page keeps the rules the plugin engine spec fixed, and the ones carried over from the v1 addon runtime, so that the services and Music sub-project, which brings the first services, starts from them.

## Services

A service is a call a plugin makes, declared per feature in the manifest's `services`. Plugins stay thin: heavy or privileged work lives in services, placed by the rule of spec §6.

| Place | Rule | Members planned for v1 |
| --- | --- | --- |
| Kernel | Touches frames, input or the notch window, or updates the UI more than about ten times a second | Spectrum capture (Core Audio tap), the spacebar and Spotlight input taps, the file shelf, Spotlight |
| PluginHost | Talks to other apps or parses system data at human frequency | Now playing and Music commands (AppleEvents), Bluetooth, power, network |

The planned service-fed components, `audio.spectrum`, `media.scrubber` and `audio.outputPicker`, will bind only to kernel services and get their data from them directly, never through the plugin; the four components drawn today take the parameters their plugin passes (see [Content](content.md)). Data born in PluginHost reaches the kernel as publication data: artwork, for example, will travel through the asset pipeline. Volume, which spec §6 placed in PluginHost, is a kernel source today, beside the volume key tap it shares a subsystem with.

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
