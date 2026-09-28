# Continuous shape, notices and volume verification

8 September 2026. Xcode beta, macOS 27 SDK. Working specification:
[plan](../plans/2026-09-08-notch-notices-volume.md),
[updated contracts](../../architecture/live-activity-contracts.md).

## Verified results

- **81 CascadeKit tests in 12 suites passed**, log
  `/private/tmp/cascade-notice-final-tests.log`.
- **28 volume checks passed** with Swift 6, default MainActor isolation
  and warnings treated as errors: `zsh scripts/test-volume.sh`.
- Full Debug app build and ad hoc signature valid; log
  `/private/tmp/cascade-volume-app-build.log`.
- `git diff --check` clean. No commit or global change to the macOS HUDs.
- Final app launched via CUA; process verified at the path
  `/private/tmp/cascade-volume-derived/Build/Products/Debug/Cascade.app`.
- Offscreen render of the real volume factories checked at 0, 6, 37 and 100%:
  icon, text, bar and percentage readable. Local diagnostic image
  `/private/tmp/cascade-volume-notice-preview.png`; the render verifies the
  content of the wings, not the full notch geometry or the system input.

## Regressions exercised

The old behavior failed the tests for expanded notice, replay on close,
priority of the latest notice and return to the base outline before the compact view.
The new implementation passes them and suspends the view resources during the
transition. Rehover, immediate close, reduced motion,
lock/unlock and width changes are also covered.

The independent review identified, and led to the fix of, two further
cases: display change with the compact spring already at rest, and temporary
activation of a secondary provider while locked. Both regressions were
run before and after the fixes.

Nine path tests compare the outline with `RoundedRectangle(.continuous)` and
verify fillets, symmetry, bounds, zero radii and small geometries. The native
segments are stored once; in the animation loop twelve cubics are transformed
and emitted, without building SwiftUI views.

The volume check verifies decoding, generations, silent baseline,
duplicates, callbacks off the MainActor, the native gesture until release, feedback at
the limits and expiry of the duplicate suppression. The CoreAudio code was
reviewed for master/channel mute, failed reads and write rollback.
The last review reported no remaining problems in the scope it read.

## Boundaries of the evidence

The optional probe `zsh scripts/test-volume.sh --probe` reads capabilities and
creates/immediately invalidates pass-through taps. On the already authorized host process
it confirmed reading of the output, control capability and creation of the HID and
session taps. It does not change audio, does not post events and does not grant permissions.
This outcome does not prove the TCC authorization of the signed app nor the real
suppression of the HUD while the keys are pressed.

For the real test, use the Cascade menu: **Test Volume Alert** does not change
the audio; **Allow Accessibility for Volume Keys…** opens the permissions
path. Replacing the keys requires the app's authorization. Unsupported
outputs, mixed mute or errors keep the macOS behavior.

CoreAudio does not identify the producer of a change. The 600 ms filter
around a gesture passed to macOS limits duplicates; it is a heuristic evaluated
only on events, with no recurring timer. It does not guarantee suppression of HUDs
emitted on their own by external applications.

## Build reproduction

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-hig-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-hig-module-cache \
/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
test --package-path CascadeKit --scratch-path /private/tmp/cascade-notice-build --disable-sandbox

zsh scripts/test-volume.sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug \
-derivedDataPath /private/tmp/cascade-volume-derived CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

codesign --verify --deep --strict /private/tmp/cascade-volume-derived/Build/Products/Debug/Cascade.app
```

Primary references: [Apple continuous curvature](https://developer.apple.com/documentation/swiftui/roundedcornerstyle/continuous),
[Quartz event tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[CoreAudio listener](https://developer.apple.com/documentation/coreaudio/audioobjectpropertylistenerblock).
