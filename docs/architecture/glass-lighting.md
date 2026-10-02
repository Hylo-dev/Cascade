# Glass lighting

`GlassLight` in `CascadeContracts` describes a decorative sRGB light projected
under the expanded notch's native glass. It is a framework-independent,
immutable `Codable`, `Equatable`, `Sendable` value, so native SwiftUI surfaces
and plugin documents use the same contract.

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

Import `CascadeContracts` for the value and `CascadeKit` for the view modifier:

```swift
import CascadeContracts
import CascadeKit
import SwiftUI

let warmLight = try GlassLight(
    x        : 0.25,
    y        : 0.7,
    radius   : 0.4,
    red      : 1,
    green    : 0.25,
    blue     : 0.1,
    intensity: 0.45
)

Text("Now playing")
    .notchGlassLights([warmLight])
```

The modifier adds values to `NotchGlassLightsPreferenceKey`. Descendant lights
retain priority when a parent adds its own contribution, and siblings combine
in view order. Each reduction and modifier applies the eight-light limit. Use
an empty array when a source has no light contribution; replacing or removing
the source lets the host clear its previous values. The file shelf lights the
glass this way (`FileShelfGlassLightEmitter`).

Light that follows a live signal skips the preference. Music's lights follow
the spectrum 30 times a second, and through a SwiftUI preference every tick
re-evaluated the view tree, measured at about 1.3% of a core more. An AppKit
view inside the notch's content instead finds the nearest
`NotchGlassLightReceiving` among its superviews and hands it lights in the
same normalized space, as `MusicGlassLightEmitter` does. Static light keeps
using `notchGlassLights`.

Light updates are presentation data. Providers do not need to rebuild controls,
capture screen content, or drive a separate animation timer. The host owns
visibility, clipping, privacy, accessibility behavior, and stale-source
protection. It displays lights in expanded glass and keeps compact and closed
chrome unchanged.

## Plugin documents

Glass lights are a document-level feature of a plugin's content, not a node:
`PluginDocument` carries them beside its root.

```swift
import CascadeContracts
import CascadePluginSDK

let document = try PluginDocument(
    root       : Text("Now playing"),
    glassLights: [warmLight]
)
```

`glassLights` defaults to an empty array, and a decoded document that omits
the field has none. A document holds at most eight lights and rejects a ninth;
the lights share the document's 65,536-byte budget, with no extra allowance,
and unknown fields in a light remain invalid. `PluginDocumentView` hands the
document's lights to the same `notchGlassLights` modifier native surfaces use,
so both paths share the host's lifecycle and rendering rules.

## Dynamic sources

A module can derive a new bounded array from information it already owns. For
music, decoded album colors provide ambient light and measured low-frequency
energy can increase radius and intensity. Pause, silence, and reduced motion
should retain a static ambient color. The light contract does not request
additional audio capture or synthesize a beat when measurements are absent.
