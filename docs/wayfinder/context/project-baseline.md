# Cascade: baseline for the application map

Survey of 4 September 2026. This document collects the requirements received and the findings on the code; it is not yet the Wayfinder map nor an approved specification.

## Requested destination

Define Cascade's global plan: a modular notch for macOS, extensible by other apps through a protocol/SDK. The map will have to clarify product, architecture, contracts, feasibility of the integrations, dependencies and the order of the subsequent implementation specifications.

## Requirements stated by the user

- Opening on hover, with haptic feedback on the trackpad once open.
- Compact presentation extended to the sides for ongoing activities, inspired by the Dynamic Island; the activities too must be extensible through the protocol.
- Alignment to the physical notch; on displays without a notch it must protrude slightly.
- Two styles: black, and glass inspired by the new Siri and by Sapphire.
- First integrations: music and browser media, notifications and Bluetooth connections, search from the notch, temporary collection of dragged files, contextual audio management inspired by FineTune.
- Pages with widgets of different sizes on a grid; selection also based on context.
- Settings under the notch, with the visual language of the macOS settings: appearance, sizes including per individual display, active activities and contextual screens.
- Sapphire is also a functional reference; its other features do not automatically become Cascade requirements.
- The attachment is a visual reference for search: a rounded upper field and a separate, dark and translucent results surface. The entries and the microphone in the image are not, on their own, functional requirements.
- Ask the user when a product choice is missing; do not replace missing preferences with final assumptions.

## Observed project state

| Area | Evidence in the code | Consequence for the plan |
| --- | --- | --- |
| App/engine separation | `Cascade` uses the local package `CascadeKit` through `NotchEngine`. | Keep the existing public boundary and assess where the SDK for external apps should live. |
| Overlay and animation | `NotchPanel`, `NotchController`, `DisplayLinkMorphEngine`, `NotchHostView`; geometry with springs and `CAShapeLayer`. | There is an engine to evolve; there is no need to presume a rewrite. |
| Widgets | `NotchWidget` exposes identity, kind, size, `AnyView`, activation and suspension; direct registration of objects in the host's process. | Internal modularity exists; discovery, inter-process communication and a contract for external extensions are not implemented. |
| Grid and pages | `GridSpan`, `WidgetPlacement`, `NotchLayoutResolver`, `NotchScreen`; `WidgetHost` uses one page and an internal index. | Models and placement exist; navigation between pages, editor, persistence and contextual selection remain to be defined. |
| Notch state | `NotchState` is an `OptionSet` for the leading/trailing sides; the morph interpolates toward opening/closing. | It is not yet equivalent to a complete model of compact activities, expansion, notifications and surfaces that take focus. |
| Input | `NotchPanel` ignores mouse events and cannot become key/main; hover arrives from event monitors. | Widget clicks, drag-and-drop and typing in search require an explicit input and focus design. |
| Displays | Pointer-based resolver; repositioning on a change of the display identifier; a single configuration. | Behavior with multiple displays and per-display size profiles have to be decided. |
| Appearance | The renderer fills with a color; the app launches the red debug configuration. | Glass and appearance settings are not implemented. |
| Settings | The SwiftUI Settings scene contains `EmptyView`. | The requested interface has to be designed. |
| Integrations | The app registers the demo clock widget; no music, notification, Bluetooth, search or audio mixer services appear in the sources examined. | These areas require contracts and feasibility research before the execution specifications. |
| Compatibility | Deployment target macOS 14; package with Swift tools 6.2; app sandbox disabled. | Distinguish current requirements, future choices and API availability per individual feature. |
| Spaces | `SkyLightWindowPinner` loads private SkyLight symbols with a fallback if they are not available. | The distribution and compatibility strategy is an initial decision. |
| Verification | Tests exist for geometry, segments, springs, state and layout; app tests are mostly scaffold. | Do not consider lifecycle, interactions, performance or integrations already verified. No build or tests were run in this survey. |

### Differences from the earlier documentation

`CLAUDE.md` describes the notch as invisible on displays without a physical cut-out. The current request instead calls for a small protrusion and takes precedence. The code's default still follows the earlier description; the debug configuration already shows the chrome everywhere.

The rules on widget resources remain a constraint to incorporate into the contracts. Suspending the UI must not be confused with stopping the event sources that the compact activities need. It has not been verified that hiding the hosting view by itself stops every update of the demo view.

## User clarifications during the initial definition

These are entry constraints of the map, gathered before working on its decision tickets.

1. **Distribution**: direct download outside the Mac App Store, with Homebrew support.
2. **Extensions**: preference for SwiftUI and for modules obtainable through "import" or loading from a folder. The technical form has not been chosen yet: a package compiled into the host, a dynamic bundle and imported sources are not equivalent.
3. **Search**: an experience identical to the system Spotlight; preference for modifying the real one if technically feasible. The choice between integrating Spotlight and an own search depends on the research, which is not yet closed. No separate AI assistant was requested.
4. **Notifications**: also include those of other apps not integrated with Cascade.
5. **Initial audio**: per-app volume and mute, per-app routing and multiple outputs. Equalization was not selected as an initial requirement.
6. **Files**: present the shelf during the drag and acquire the files only when they are dropped on the notch. The kind of retention and its duration remain to be decided.

These clarifications do not automatically approve private techniques, resource load, copying of external code or functional limits not yet discussed.

## Other questions already identifiable for the map

- Which compact modes and which activities are included in the first version of "like the Dynamic Island"?
- How are priorities resolved between simultaneous activities, notifications, search, manual page choice and contextual suggestions?
- When does the file collection appear, when does it acquire the files and how long does retention last? References, copies, moves and promised files require an explicit decision.
- Which part of FineTune is required at the start: per-app volume, per-app routing, multiple outputs, equalization?
- How are extensions registered, authorized, updated and removed, and what happens if the source app quits or stops responding?
- How do the grid, the sizes supported by the widget, the notch sizes and the per-display profiles coexist?
- Which measurable CPU, memory, energy and latency thresholds must the host, glass and modules meet?
- Which permissions do the requested features need, and which behavior must remain available when they are denied?

## External references consulted

- [Sapphire](https://github.com/cshariq/Sapphire): the README describes Now Playing, per-app audio, file shelf and Bluetooth notices, among other features. The code of the glass treatment still has to be analyzed; no verified visual match is claimed.
- [FineTune](https://github.com/ronitsingh10/FineTune): the README describes per-app volume, routing, multiple outputs and EQ and states macOS 15 as the minimum. This does not imply that all these features must go into Cascade's first release or that they have the same minimum requirement if implemented separately.

## State of the planning tools

- Skill `wayfinder` read from `/Users/c4v4h/.codex/skills/wayfinder/SKILL.md`.
- No specific tracker or Wayfinding operations document found in the repository; the skill provides the local-markdown fallback and points to `/setup-matt-pocock-skills` for the setup.
- The companion skills `grilling`, `domain-modeling`, `research` and the local-markdown template were not installed: they were later read from the original repository `mattpocock/skills`. The sources are in the map guide; no global installation was performed.
- The MCP graph does not contain an index of Cascade: after the missing-project response, the files were read directly, as the repository instructions allow.
- Pre-existing change in `Cascade.xcodeproj/project.pbxproj` detected and left intact. No change to the application code.
