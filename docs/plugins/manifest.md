# Manifest

Every plugin, first-party included, is declared by a manifest v2 (`PluginManifest` in `CascadeContracts`). The manifest says what the plugin is and what each of its features needs. The kernel trusts nothing a plugin did not declare: an undeclared source, component, permission or action is denied, and a declared one the host cannot provide makes its feature unavailable. Spec §10 has the reasons.

This is Cascade's charging alert, `CascadeKit/Sources/CascadePlugins/Resources/com.cascade.power.json`:

```json
{
  "manifestVersion": 2,
  "id": "com.cascade.power",
  "version": "1.0.0",
  "compatibility": { "macOS": "15.0", "cascadeProtocol": { "major": 2, "minimumMinor": 0 } },
  "execution": { "entryPoint": "ChargingPlugin" },
  "features": [
    {
      "id": "charging",
      "surfaces": { "notice": {} },
      "sources": ["power"],
      "components": [{ "id": "power.battery", "version": 1 }],
      "actions": ["preview"]
    }
  ],
  "resources": { "profile": "eventDriven" }
}
```

## Fields

Every object rejects fields it does not know, so a typo fails validation instead of passing for an option the host does not have. The whole manifest is at most 64 KiB.

| Field | Rule |
| --- | --- |
| `manifestVersion` | Exactly `2`. Version 1 is not decoded and has no migration. |
| `id` | Reverse-DNS `PluginID`, at most 255 bytes. It names the plugin and says nothing about who published it. |
| `version` | SemVer. |
| `compatibility` | `macOS` as `major.minor`, never older than Cascade's floor of `15.0`; `cascadeProtocol` with `major` `2` and a `minimumMinor`. |
| `execution` | Only `entryPoint`, a Swift identifier of at most 128 characters: the key PluginHost looks the provider up by (`FirstPartyPlugins.providers`). Execution mode and trust are absent on purpose, and a manifest that states them is rejected: the host takes both from the package signature. |
| `sourceApp` | Optional bundle identifier of the app the plugin's content comes from. |
| `REQUIRES` | Optional, at most 32 conditions outside Cascade: `appInstalled` or `appRunning` with a `bundleID`, or `anyOf` with two to eight such conditions. Alternatives do not nest. |
| `features` | One to sixteen features with unique ids. |
| `resources` | Only `profile`, and v1 has one profile, `eventDriven`: the plugin wakes for a source event, a scheduled wake or a user action, and never polls. The limits themselves belong to the host. |

A requirement looks like this:

```json
"REQUIRES": [
  { "kind": "anyOf", "alternatives": [
    { "kind": "appRunning", "bundleID": "com.apple.Music" },
    { "kind": "appInstalled", "bundleID": "com.spotify.client" }
  ] }
]
```

The kernel decodes and validates `compatibility`, `sourceApp` and `REQUIRES`, but does not evaluate them yet: no first-party plugin needs them, and external plugins, which will, are not built.

## Features

A feature (`PluginFeature`) is one thing a plugin does. Each declares, with unique entries in every list:

| Field | Meaning |
| --- | --- |
| `id` | The feature's identifier, named by every publication and action. |
| `surfaces` | At least one of `activity: {}`, `notice: {}` and `widget: { "sizes": [...] }`, plus an optional `detail: {}`, which needs the widget of the same feature: it is the page the widget's click opens, and the plugin publishes into it like into any surface. An activity is presented by the notch (see [Activities](#activities)). A widget lists one to eight distinct sizes as `"columnsxrows"`, each from 1 to 4 (`"2x1"`, `"2x2"`); the user picks the size and the position, a plugin never places itself. |
| `sources` | The catalog sources that wake the plugin: `media.nowPlaying`, `bluetooth`, `power`, `volume`, `caffeinate`, `network`, `net.webSocket`, `net.sse` (`PluginCatalog.sources`). Plugins cannot write sources. |
| `services` | The services the plugin calls. The host provides `audio.system` and `audio.apps`; a feature that declares any other is unavailable. |
| `components` | The tier-2 components its documents show, each `{ "id", "version" }` from `PluginCatalog.components` at that version or older. |
| `permissions` | What the feature needs granted. Bundled plugins signed by us receive every permission they declare; external plugins will need the user's approval for the sensitive ones. |
| `actions` | The action names its controls and Cascade's menu may send, such as `preview`. |
| `supportsFullscreen` | Optional, `false` when absent. A widget feature that sets it may publish an options page, drawn over the grid in the notch's expanded footprint (see [Content](content.md#options-page)). Requires a `widget` surface. |

**Declared means required.** The kernel keeps a feature available only while the host provides every source, service and component it declares and every permission it declares is granted. An unavailable feature leases no source, its publications are dropped quietly and its actions are refused. Today the host provides the `power`, `bluetooth`, `volume` and `caffeinate` sources, the `audio.system` and `audio.apps` services, and the components `power.battery`, `volume.level`, `bluetooth.device`, `bluetooth.battery`, `audio.volumeBar`, `audio.mixer` and `audio.outputPicker`. The catalog lists more, so a manifest that names them validates, but its feature stays unavailable until the host implements them.

## Activities

A feature that declares `activity: {}` publishes a live activity: a document of three regions (compact leading, compact trailing and minimal) or four (those plus expanded, see [Content](content.md#vocabulary)). An activity without an expanded region is a status: it never takes over the opened notch, which shows the widgets while it runs, and clicking its compact presentation does the same. The publication also carries `PluginActivityAttributes`, which only an activity carries:

| Attribute | Meaning |
| --- | --- |
| `startedAt` | When the activity began, and its identity over time. A new `startedAt` is a fresh lifetime: the old session ends and the activity is presented anew, with a fresh cap. Repeating the current one keeps the session. |
| `relevance` | From 0 to 1: the plugin's own say in the order of competing activities. The arbitration weighs it, it does not command it. |
| `accessibilityLabel` | The sentence VoiceOver reads for the compact regions, at most 512 bytes. The expanded region keeps its own controls reachable. |

`PluginSurfaceRouter` turns the publication into one `PluginActivity` and hands it to the notch's live-activity host (`LiveActivityHost`), which arbitrates it with every other activity, Music's included, and ends any session after eight hours (`NotchActivityLifetime.maximumDuration`). Later publications update the content in place; a change of relevance or label presents the activity again so the host sees the new values; withdrawing the publication ends it. The kernel asks the plugin for one `refresh` only if the activity becomes visible with content older than its `staleAfter`. An activity's controls go through the same broker as a widget's, so each must be one of the feature's declared actions.

## Validation

`PluginManifest.decode` checks the size before parsing and every rule above while decoding. Three places run it:

- `cascade-plugin validate`, which `scripts/build-development.sh` runs on every bundled manifest before Xcode compiles anything, so a broken first-party manifest stops the build. It refuses a version 1 manifest by name instead of by whichever v1 field the decoder trips on first.
- `FirstPartyPluginsTests`, which decodes every bundled manifest and checks that each has a provider.
- `FirstPartyPlugins.manifests()` in Cascade at launch. A manifest that fails there can only come from a broken bundle, and is left out.

The tool's `--help` prints its usage. It reads at most 64 KiB plus one byte and refuses directories, pipes and other non-regular files without blocking on them.
