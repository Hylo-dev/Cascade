# Product

## Register

product

## Users

macOS users who check activities and contextual controls without leaving the app they are using.

## Product Purpose

Cascade gathers widgets, Live Activities and contextual tools in a modular notch, while keeping CPU, memory and energy use low.

## Brand Personality

Native, discreet, responsive. Functional references: Dynamic Island and BoringNotch; for the future glass style, Sapphire.

## Anti-references

Controls that steal focus, continuous decorative animations, interfaces that interrupt work, and duplicates of system alerts. Constraints taken from CLAUDE.md and the approved interactive specification.

## Design Principles

- Show context without interrupting the action in progress.
- Keep the physical bond with the notch and the native macOS conventions.
- Make modules independent through small, verifiable contracts.
- Build Cascade's own widgets with the same [addon SDK and runtime](docs/superpowers/specs/2026-09-09-addon-runtime-design.md) too: identical permissions, isolation and limits, with no privileged private paths.
- Keep valid content without needlessly keeping alive the code that produced it; separate an activity's visibility, work and lifetime.
- Update the UI only when a real input changes.
- Activities and notices follow the [notch contracts](docs/architecture/live-activity-contracts.md), adapted from Apple's Live Activities HIG.

## Design Workflow

For design, use **Impeccable** and **Taste** (`design-taste-frontend`), applying their guidance to the native SwiftUI/AppKit product and to [Apple's guidelines for Live Activities and the Dynamic Island](https://developer.apple.com/design/human-interface-guidelines/live-activities). The Music widget is the internal reference for size, density, diffused color and motion.

- No shelf page exceeds the notch's standard footprint: rearrange the content, do not enlarge the surface.
- The physical cutout excludes only the top center; the sides may use the top band. Keep margins consistent with the silhouette, without a uniform empty band.
- Use contained glows and the notch's color to give the content identity, as the music does; respect Reduce Transparency and Reduce Motion.
- An occupied page's priority does not mean it stays open: the shelf remains the main context until it is cleared, with the notch opening and closing normally.
- Recognizing and admitting a drag does not depend on how long animations take.

## Accessibility & Inclusion

Use native controls with accessible labels, readable contrast, reduced-motion preferences and optional haptics. No formal certification target has been specified.
