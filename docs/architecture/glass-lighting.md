# Glass lighting SDK

`GlassLight` in `CascadeContracts` describes a decorative sRGB light projected
under the expanded notch's native glass. It is a framework-independent,
immutable `Codable`, `Equatable`, `Sendable` value, so native SwiftUI modules and
serialized addon content use the same contract.

## Coordinates and bounds

All seven components are finite `Double` values in `0...1`:

| Component | Meaning |
| --- | --- |
| `x`, `y` | Center in the expanded notch, from top left `(0, 0)` to bottom right `(1, 1)`. |
| `radius` | Radius as a fraction of notch width; must be greater than zero. |
| `red`, `green`, `blue` | sRGB color components. |
| `intensity` | Light strength; zero contributes no visible light. |

The throwing initializer rejects out-of-range values, zero radius, NaN, and
infinities. Decoding applies the same validation and rejects unknown or missing
light fields. `GlassLight.maximumCount` is eight. Native contributions retain
the first eight lights; serialized documents reject a larger array.

## Native SwiftUI content

Import `CascadeContracts` for the value and `CascadePresentation` for the view
modifier:

```swift
import CascadeContracts
import CascadePresentation
import SwiftUI

let warmLight = try GlassLight(
    x: 0.25,
    y: 0.7,
    radius: 0.4,
    red: 1,
    green: 0.25,
    blue: 0.1,
    intensity: 0.45
)

Text("Now playing")
    .notchGlassLights([warmLight])
```

The modifier adds values to `NotchGlassLightsPreferenceKey`. Descendant lights
retain priority when a parent adds its own contribution, and siblings combine
in view order. Each reduction and modifier applies the eight-light limit. Use
an empty array when a source has no light contribution; replacing or removing
the source lets the host clear its previous values.

Light updates are presentation data. Providers do not need to rebuild controls,
capture screen content, or drive a separate animation timer. The host owns
visibility, clipping, privacy, accessibility behavior, and stale-source
protection. It displays lights in expanded glass and keeps compact and closed
chrome unchanged.

## Serialized addon content

Lighting requires an explicit content schema of `2`:

```swift
let document = try ContentDocument(
    schemaVersion: 2,
    root: .text("Now playing"),
    privacy: .publicContent,
    accessibilityLabel: "Now playing",
    glassLights: [warmLight]
)
let data = try document.encode()
let restored = try ContentDocument.decode(data)
```

Both public `ContentDocument` initializers accept the final optional parameter
`glassLights: [GlassLight]? = nil`. Existing call sites keep schema `1` and omit
the new key when encoding. Schema `2` also accepts an omitted field or an empty
array. A schema `1` wire document containing `glassLights` is invalid, including
an explicit `null`; schema `2` decodes `null` as an absent contribution. Schema
versions outside `1...2` remain unsupported.

The wire representation is explicit numeric data:

```json
{
  "schemaVersion": 2,
  "root": { "kind": "text", "text": "Now playing" },
  "accessibilityLabel": "Now playing",
  "privacy": "publicContent",
  "assets": [],
  "glassLights": [
    {
      "x": 0.25,
      "y": 0.7,
      "radius": 0.4,
      "red": 1,
      "green": 0.25,
      "blue": 0.1,
      "intensity": 0.45
    }
  ]
}
```

Lights share the existing 65,536-byte content-document budget. They do not get
an extra payload allowance. Unknown document fields remain invalid.
`ContentRenderer` emits the document's lights through the same SwiftUI
preference as native modules, so both paths share host lifecycle and rendering
rules.

## Dynamic sources

A module can derive a new bounded array from information it already owns. For
music, decoded album colors provide ambient light and measured low-frequency
energy can increase radius and intensity. Pause, silence, and reduced motion
should retain a static ambient color. The light contract does not request
additional audio capture or synthesize a beat when measurements are absent.
