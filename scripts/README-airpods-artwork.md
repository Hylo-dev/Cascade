# Official AirPods connection artwork

Cascade reads Apple's installed artwork at runtime. No Apple video, image,
private framework binary, downloaded model, or procedural replacement is
included in the app bundle.

The resolver reads `AssetPaths*.plist` from:

`/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Versions/A/Resources`

These catalogs supply product IDs, image names and verified color variants.
The corresponding animated banners live in:

`/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/Banner-PID-<decimal>-mov/`

Files are named `Banner-PID-<decimal>-Loop.mov` and, for colored models,
`Banner-PID-<decimal>-<color>-Loop.mov`. Foundation reads the files directly;
no private framework code or APIs are loaded. The resolver only searches the
two fixed resource directories, bounds catalog and resource sizes, and rejects
image names containing path components.

Verified installed catalog mappings:

| Product IDs | Apple catalog artwork |
| --- | --- |
| `0x2002`, `0x200F` | AirPods, `B188-B288.png` |
| `0x200E` | AirPods Pro, `B298.png` |
| `0x2013` | AirPods 3, `B688.icns` |
| `0x2014`, `0x2024` | AirPods Pro 2, `B698.icns` |
| `0x2019`, `0x201B` | AirPods 4, `B768.icns` |
| `0x2027` | AirPods Pro 3, `B788.icns` |
| `0x200A` | AirPods Max, `B515` color variants |
| `0x201F`, `0x202D` | AirPods Max, `B515c` color variants |

When a PID has no dedicated movie, a sibling movie is used only when Apple's
catalog assigns the exact same image name to both products. This covers Pro 2
connector variants, AirPods 4 variants, and newer Max revisions without guessing
their appearance. A verified color uses the matching colored movie; when
unavailable, its official catalog image is retained. Missing system resources
fall back to the corresponding official SF Symbol. Generic accessories retain
their own supplied system symbol.

Native movies are 168 × 168 pixels at 60 fps with a six-second loop. A mounted
notice samples 48 frames at a maximum of 96 × 96 pixels on a utility task, then
plays one three-second Core Animation contents sequence. No live player or
repeating timer remains. Decoded images occupy approximately 1.7 MiB during
playback, followed by one small poster. Unmount cancels loading and clears
images; Reduce Motion decodes only a static poster. Nothing is persisted to
disk by the app.

The `bluetooth.device` component in CascadeKit draws this artwork. Its checks are
package tests:

```sh
cd CascadeKit && swift test --filter PluginBluetoothComponentTests
```

They check the resolver's catalog reading, aliases, colors, unknown IDs and
refused image names against a catalog they build, and decode the installed
AirPods Pro movie into one bounded turn, a Reduce Motion poster and the static
fallback. They mount the real turntable offscreen to check one three-second
turn, no restart on battery enrichment, teardown and cancelled decoding. The
checks that read system files are skipped where macOS lacks them. They do not
launch Cascade or access Bluetooth or audio devices.
