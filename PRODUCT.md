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
- Build Cascade's own widgets, notices and activities as plugins of the same [plugin engine](docs/superpowers/specs/2026-09-29-plugin-engine-design.md) external plugins will use: the same manifest, declarations, grants and limits, with no private code path. Only the default approver differs: bundled plugins signed by us receive the permissions they declare, external ones will ask the user.
- Isolation is the one deliberate exception (the microkernel decision): first-party plugins share one PluginHost process, a thread each, while external plugins will get a process each. Running a plugin inside Cascade is reserved for the test and development double.
- Keep valid content on screen independently of the code that produced it: publications live in Cascade and survive a PluginHost restart, while PluginHost stays alive and idle when nothing changes. Separate an activity's visibility, work and lifetime.
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
