# Notch glass lighting implementation plan

**Goal:** Extend the transparent region upward and let SDK modules project bounded colored light into expanded glass, with real music bass as the first dynamic source.

**Architecture:** `CascadeContracts.GlassLight` is a finite, normalized value. `CascadePresentation` transports light preferences from SwiftUI and decoded documents to the host. The host caps and clears contributions and renders them beneath native glass; music emits the same values from its existing artwork palette and measured spectrum.

**Constraints:** Keep compact/closed chrome unchanged. No additional audio capture, polling, screen capture, private framework API, or synthetic beat clock. Preserve sensitive-content redaction, reduced transparency, and reduced motion. Work in the user's current checkout and preserve unrelated changes; do not commit or publish. Build through `scripts/build-development.sh`, update `/Applications/Cascade.app`, visually inspect the actual expanded panel, then restart normally.

## 1. Shared SDK contract and presentation

- [x] Add validated `GlassLight: Codable, Equatable, Sendable` with public Double fields `x`, `y`, `radius`, `red`, `green`, `blue`, `intensity`. Coordinates/colors/intensity in 0...1; radius in 0...1 excluding zero; reject nonfinite values and unknown wire fields. Maximum 8 lights.
- [x] Extend `ContentDocument` with optional `glassLights: [GlassLight]? = nil`. Preserve legacy schema 1 encoding; lighting requires explicit schema 2. Support decoding both versions, bound light count and total document bytes.
- [x] Add public `NotchGlassLightsPreferenceKey` and `View.notchGlassLights(_:)` in CascadePresentation, combining contributions with the same cap. ContentRenderer emits document lights through this path.
- [x] Test legacy roundtrip, schema-2 roundtrip, malformed and oversized lighting, preference reduction and document propagation. Document both native and serialized SDK usage.

## 2. Host and glass

- [x] Observe the preference on content roots; revision-guard callbacks so replaced/hidden content cannot relight the glass. Clear contributions on removal. No rebuild of content for light-only updates.
- [x] Render a bounded radial light field behind native glass, clipped to the actual notch path. Update only the small material host. Retain the current dark top cap, move the mesh middle row from 60% to 43%, reduce middle opacity from 0.9 to 0.65, and use bottom opacity 0.25. This is the user-requested refinement after the first 35% / 0.55 / 0.22 preview was too transparent.
- [x] Test source replacement/clearing, expansion-only visibility, multiple contributors, and geometry/interaction regressions.

## 3. Music and visual verification

- [x] Build a pure music-to-light mapping using decoded sRGB artwork colors and existing low-frequency bands. An expanded-only emitter uses the public modifier. Bass increases radius/intensity with bounded values; paused/silent/reduced-motion states have static ambient color. No fake spectrum.
- [x] Test low-band response against treble-only input, silence, pause, and invalid measurements.
- [x] Run the contract/presentation/host and music checks, build, inspect the actual app with `--inspect-expanded-notch`, compare ambient and measured playback, and restart without diagnostics.

## Progress

- User confirmed that "larger glass" means extending transparency upward, not changing notch dimensions.
- Graph discovery unavailable: Cascade is not indexed; direct source reads used.
- Baseline has an expanded-only glass renderer and a diagnostic launch option verified against the actual media surface.

- Final checks: 139 Swift tests, seven music-response checks, app build, and scoped review passed. The actual expanded music panel was inspected through CUA. A debugger breakpoint confirmed two artwork-derived SDK lights reaching the renderer during real playback (radius 0.5924 and intensity 0.6164 for the primary source). The grayscale cover correctly yielded neutral light. Playback was restored to odeon, paused at 111.76 seconds. Cascade was then restarted normally as PID 89540 and the closed opaque notch was visually confirmed.
