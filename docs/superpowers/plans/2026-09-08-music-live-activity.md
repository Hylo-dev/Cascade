# Music Live Activity Implementation Plan

**Goal:** Replace the music preview with a real Apple Music/Spotify activity matching the supplied Dynamic Island references, including bars derived from captured playback audio.

**Architecture:** Event-driven player adapters publish bounded metadata and truthful command capabilities. A separate native Core Audio tap supplies six measured frequency bands only while the activity is visible and playing. The provider-independent host owns geometry, presentation and lifetime; the app owns permissions and integrations.

**Constraints:** macOS 14 floor; audio taps require 14.2+. Swift 6/MainActor. No microphone, audio files, network upload, polling, fake spectrum, player launch during reads, or permission bypass. Preserve 12 pt regular compact typography and host-owned 12/8/6 pt insets. Preserve existing uncommitted work.

- [x] Extend NowPlayingSnapshot with artwork data, stable track identity, favorite state and playback rate; test timing and invalid inputs. Add truthful favorite capability/command.
- [x] Implement and test native Music/Spotify event adapters with worker AppleEvents, explicit Automation consent, generation guards and bounded artwork reads.
- [x] Implement and test private Core Audio output capture plus six-band DSP, silence/stop behavior and native-resource cleanup.
- [x] Replace the UI with compact artwork/spectrum and expanded artwork/title/artist/spectrum, seek/remaining time, previous/play/next, supported favorite and output-device control. Decode artwork off-main and update only the bars for spectrum frames.
- [x] Allow a separate bounded expanded-activity height while retaining the ordinary widget height; validate geometry and input behavior.
- [x] Integrate real providers, lifecycle and menu controls; add native usage descriptions and the Automation entitlement. Do not grant permissions through scripts.
- [x] Run DSP/provider/host tests, inspect rendered compact and expanded variants, build with the development script, update /Applications/Cascade.app, and verify the restarted process.

Native platform references: [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), [Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography).

Music/Spotify are the initial adapters because global MediaRemote access is restricted on current macOS. The implementation uses public scripting interfaces and system consent instead of impersonating an Apple-signed client. Unsupported actions remain unavailable. The output control selects a real available macOS output device; it does not claim to transfer a third-party player's private AirPlay session.


## Validation

- CascadeKit: 107 tests passed, including playback rate and the separate expanded-activity height bound.
- `scripts/test-now-playing.sh`: native descriptor fixtures, source arbitration and stale-command rejection passed with Swift 6 and warnings as errors.
- `scripts/test-audio-spectrum.sh`: real PCM sine/amp/silence/phase tests and capture lifecycle passed with Swift 6 and warnings as errors.
- Presentation harness: compact/expanded views rendered; visible playback starts capture, pause/disable/end stop capture, hidden updates stay stopped, and PCM frames do not advance metadata revisions.
- Native development build succeeded and the application link was updated. The updated process was restarted and verified before delivery; signature, Automation entitlement and both privacy descriptions were checked in the installed bundle.
- Live player validation remains conditional on the user's native Automation and system-audio consent. A silent probe found Music running without Automation consent; Spotify was not running. No consent was bypassed and no actual playback was altered during tests.

The activity retains its identity across track changes so an expanded player stays open. Each visible command carries the displayed snapshot; the provider rejects dispatch after source/track replacement. HAL output discovery and switching run on a worker actor. The artwork fallback is neutral when a player provides no cover. External seeks in Music/Spotify may not emit a notification; Cascade's own seeks and subsequent playback/wake events refresh timing.

Build verification caught Xcode omitting the custom audio-capture key from generated settings. `Config/Cascade-Info.plist` now supplies `NSAudioCaptureUsageDescription` explicitly, merged with the generated application metadata.

## Startup permission update

At the user's request, Cascade now starts native consent at app launch for enabled integrations. Bluetooth already requests through monitor registration; Accessibility is requested once for volume/native Bluetooth replacement. An independent private audio tap requests system-audio access even without playback, discards PCM and stops immediately after setup or failure. The startup task is cancelled on shutdown. Automation setup opens installed players in the background for their first consent attempt because Apple's API requires a running target; it rechecks real permission for running players without caching grants. Subsequent metadata reads remain silent and never launch players.

The audio regression test failed before implementation, then passed for idle startup, resource cleanup on success/denial and cancellation. Audio and player suites passed after the change. Native consent remains the user's decision; macOS will not repeat a prompt for an already granted permission.

## Album light and spectrum styling

The album now emits a static multicolor light that fades to transparent inside the host's safe bounds. A bounded 24×24 color histogram preserves up to three distinct sampled hues; transparent pixels are ignored and neutral artwork stays neutral. The same palette colors one continuous gradient across the six audio bars. Compact bars reach 18 pt (previously 16), expanded bars 27 pt (previously 23); their narrower width is 1/12 of the group width, capped at 2.4 pt, and resting height equals width to form circles. Reduced transparency removes the light; reduced motion disables bar interpolation. PCM acquisition remains unchanged.

Validation: `scripts/test-music-artwork.sh` covers distinct colors, grayscale, transparency and invalid/oversized images. Its red/blue fixture failed against the previous average-color implementation before passing with the histogram. The presentation harness rendered active, paused and compact multicolor fixtures and passed capture lifecycle checks.

## Radial light and notch spacing refinement

The original light was anchored to the expanded content's upper-left corner and clipped by the shared content rectangle. It now sits directly behind the artwork with a centered radial alpha falloff, preserving equal reach in every direction. The expanded diameter is 1.65× the artwork size at 0.65 opacity; compact artwork uses only a 1.28× diameter at 0.18 opacity. Compact bars gain a local 1.2 pt blur at 0.2 opacity. Both effects use the same sampled album palette and disappear with Reduce Transparency.

The host allows at most 20 pt of decorative overflow while its native notch mask remains the final clipping boundary. Native hosting views allow this paint across their rectangular frames, including into the visible area beside the physical cutout. Content layout and interaction bounds remain unchanged by the glow.

These spacing values supersede the initial insets above: expanded activities use 4 pt above content, 16 pt below and 20 pt horizontally; music declares its actual 138 pt content height and aligns to the top. Compact content keeps 12 pt outer and 6 pt vertical padding, with just 2 pt toward the hardware notch. Music requests 40 pt per wing and aligns artwork and spectrum inward. Provider widths may be smaller than the configured fallback; two simultaneous activities still use the larger requested width. Minimal presentations remain centered.

Validation includes pixel checks through the actual native host for all four glow margins and the area above the expanded content frame. Geometry checks cover the reduced top inset and a compact provider smaller than the default width. The native presentation harness renders compact, expanded and paused music fixtures through NotchController, and verifies capture lifecycle and metadata revision isolation.


## Reference proportions and stopped playback

The supplied reference has a 198 px cover and 33 px title glyphs (6:1). The native 15 pt title renders 22 px glyphs at 2×, so expanded artwork is now 66 pt with a 66 pt header and 144 pt declared content height. Compact artwork retains its pre-enlargement sizing. Resting spectrum dots use equal pixel-aligned dimensions.

Music now has an independent expanded fallback: paused playback ends the finite live session and releases compact resources, while manually opening the notch activates the same full-width music controls. Resuming publishes the live session again. A stopped/missing source retains the last cover and title but requires a fresh player snapshot before commands become available. Disabling the integration clears both presentations. The fallback does not reserve a compact slot, compete with live tasks or acquire a session deadline.

Validation: four host/controller regression cases cover closed resource ownership, pause while expanded, reopening, resume, source removal and fallback lifetime. The full suite passes 132 tests in serial execution; a parallel run exposed contention in an existing timed AppKit close test, which also passed independently. The native music harness verified pause → bare notch → reopened player → resumed capture, and rendered the reference proportions.
