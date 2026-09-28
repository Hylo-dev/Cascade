# Live Activities HIG adaptation verification

Date: 8 September 2026. Toolchain: Xcode beta, SDK macOS 27.
Reference contract: [notch activities and alerts](../../architecture/live-activity-contracts.md).

## Results

- CascadeKit: **62 tests passed in 11 suites**, including host, controller,
  geometry, hit testing, haptics and music snapshots.
- Regression verified before and after the fix: moving `startedAt`
  through `present` or `invalidate` does not extend the session limit;
  a future start does not allow more than eight hours of presence.
- Full Debug build of the app: succeeded; ad hoc signature verified with
  `codesign --verify --deep --strict`.
- `git diff --check`: no errors.
- Independent review of lifecycle, scheduler, privacy, selection of the
  second activity, sizing and provider: no remaining blocker.
- App launched from the exact build path and relaunched after the final
  dark theme fix. Observed the notch, the application menu and the accessibility
  hierarchy of the expanded music preview with title, artist, play/pause and
  progress. No real music integration is declared verified.

## Reproducible commands

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-hig-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-hig-module-cache \
/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
test --package-path CascadeKit --scratch-path /private/tmp/cascade-hig-build --disable-sandbox

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug \
-derivedDataPath /private/tmp/cascade-hig-derived CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

codesign --verify --deep --strict /private/tmp/cascade-hig-derived/Build/Products/Debug/Cascade.app
git diff --check
```

Session logs: `/private/tmp/cascade-hig-tests.log` and
`/private/tmp/cascade-hig-app-build.log`. The warnings concern SwiftPM caches
not writable in the sandbox and the absence of the AppIntents dependency; no
compilation errors.

## Limits of the checks

The automated tests verify rendering decisions, redaction before the
factories, context revocation, expirations, sizes and stopping the animation.
They do not measure the perception of haptics, do not replace a full VoiceOver
test and do not prove that a future provider's links work.
The override of the native Bluetooth banner still requires a test with a real
event and Accessibility authorization. This work does not modify the Bluetooth
monitor or the native suppressor.
