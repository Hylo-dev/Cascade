# Interactive notch verification

Branch: `codex/interactive-notch`. Environment: macOS 27.0 beta, Xcode 27 beta,
deployment target macOS 14. Local Debug build with verified ad hoc signing.

## Implementation

- AppKit `.alignment` haptic requested on the accepted hover entry, before
  the opening. The preference can be turned off; no pulse on automatic events.
- Compact and expanded surfaces for Live Activities, interactive SwiftUI controls,
  a mask matching the shape and a transient queue limited to eight items.
  Notices last four seconds and give space back to the persistent activity.
- Classic Bluetooth monitor through IOBluetooth callbacks. Silent initial
  baseline, deduplication and rebuild after wake; no discovery or polling.
- Selective attempt to close native banners through Accessibility,
  correlated with a recent real connection. It observes only Control Center.
  An unrecognized window is not closed. The preview does not arm the service.
- `NowPlayingProviding` contract, immutable snapshots, command capabilities and
  compact/expanded music content. Explicit demo provider without audio;
  connection to real players still to be implemented.

No new external dependency. BoringNotch was examined as a reference;
no code was copied. The snapshots consulted do not contain a reusable Bluetooth
monitor or native override.

## Automated checks

- CascadeKit package: **47 tests in 10 suites, all passed**, for geometry, springs, hover, event
  routing, lifecycle, activity priority and music snapshots.
- `scripts/test-bluetooth.sh`: 10 monitor checks and 13 checks of selective banner
  recognition. The monitor tests do not simulate a hardware connection.
- Full `xcodebuild` Debug build with local ad hoc signing: succeeded; `codesign --verify --deep --strict` passed.
- Bluetooth integrations verified with Swift 6 and default MainActor isolation.
- `git diff --check`: no errors.

The final independent review found no further defects in the examined
scope. Six regression tests added during review verify widgets covered
by an activity, animations with the screen locked, discarding of notices received
while locked, hover on the compact extensions, drag duration and
absence of stale pointer segments after stop/start. Pointer sampling on
mouse press/release bypasses the rate limit used
for movements only. The final build after the fixes succeeded.

Total: **70 automated checks passed** (47 package + 10 monitor + 13 policy).

Repeatable commands:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-notch-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-notch-module-cache /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-notch-build --disable-sandbox
scripts/test-bluetooth.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-notch-derived CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
git diff --check
```

## Verified limits

**The native override is not yet validated on the device.** The system exposes
strings and components compatible with the chosen approach, but it was not possible
to confirm the Accessibility tree of a real banner. The “monitoring
active” status confirms only the observer's registration. It does not demonstrate that a
banner was closed. The closing happens after the banner appears and can leave a
brief flash; it is not a preventive suppression.

Recognition requires the exact device name, connection text localized
by the system, a compact non-modal window and a single explicit close
control. Pairing requests, codes, input, other actions,
truncated or unrecognized windows are excluded. Verification on macOS 14–26 and
in the other languages remains necessary. After a Control Center restart the
observer can be reactivated by opening the menu or using “Try Again”.

IOBluetooth covers the Classic devices exposed by the framework; it does not guarantee
BLE-only accessories. The reads of already present Bluetooth records
are synchronous on the main actor: they do not query the remote device, but their
real cost remains to be measured. The potentially blocking AX reads are on a
worker and have limits on time, windows and nodes.

The architecture avoids recurring timers for Bluetooth and metadata. Music
progress has one visual update per second only during playback
in the expanded view. These properties do not replace an energy measurement.

## Manual verification still to be carried out

The automatic permissions review had required explicit consent
to run the local build. The user then authorized launch and relaunch.
No attempt was made to bypass the block. Accessibility does not yet appear
enabled for a reliable test of the service.

The first check of the bundle identifier alone had launched an earlier red
build in Xcode's DerivedData. The subsequent check of the process path
and of the crash reports identified a real crash of the new build: IOBluetooth
invokes the connection selector on its own `coordinatorQueue`, even during
the initial registration. The MainActor-isolated selector caused an assertion trap
in Swift 6. Compilation did not detect this dynamic violation; the previous
monitor harness used Swift 5. A regression is needed that exercises the
Objective-C callback from a background thread with the same Swift 6 settings
as the app, followed by a verified launch of the exact path and of the updated menu.

1. Launch the build, enter the notch from the central body and from the compact
   extensions: one pulse on entry, none while staying inside.
2. Enable the music preview from the menu; verify play/pause, previous,
   next and the switch from compact to expanded. No audio is played.
3. Try a Bluetooth notice during music and verify its return after
   four seconds. A page already open must keep the current controls.
4. Connect and disconnect a real accessory; verify name, state, absence of
   duplicates and no notice for connections already present at launch.
5. Explicitly enable Accessibility from the menu and reopen the menu. Repeat
   a connection that produces a native banner; verify with Accessibility
   Inspector the recognition and the actual closing before declaring support.
6. Verify that pairing, passkey and other notifications stay intact;
   disable the replacement and check that no late closings happen.
7. Try clicks in the menu bar outside the shape and dragging a control
   past the edge, lock/unlock, sleep/wake, Mission Control and display change.
8. Measure CPU/energy at rest and with the expanded view using Instruments or Activity
   Monitor; repeat with Reduce Motion enabled.

Build: `/private/tmp/cascade-notch-derived/Build/Products/Debug/Cascade.app`.

## Outcome of the fix and the relaunch

The monitor now receives the callbacks through a nonisolated observer and forwards
only copied metadata to the MainActor asynchronously. Session identity,
token and baseline epoch exclude stale callbacks after stop/start and wake.
No lock stays held during calls into the framework or dispatch. The test of the
Objective-C selector from background runs with Swift 6; the epoch test prevents
an already queued callback from modifying the new baseline. Targeted review
concluded with no further blockers.

Launch of the exact build verified: the process runs
`/private/tmp/cascade-notch-derived/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`.
The actual menu contains “Haptic Feedback on Hover”, “Bluetooth Alerts”,
“Allow Accessibility…”, “Music Live Activity Preview” and “Test Bluetooth
Alert”. The previous instance in Xcode's DerivedData was closed.
The native override remains to be validated after explicit granting of Accessibility
and a real connection; the successful launch does not demonstrate the closing of a banner.
