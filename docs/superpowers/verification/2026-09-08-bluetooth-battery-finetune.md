# Bluetooth battery, AirPods and volume diagnosis

8 September 2026. Request: circular charge on the right side of the notice,
rotating AirPods and a check of the volume override by comparison with FineTune.

## Reproduced diagnosis

FineTune 1.9.0 (38) is running with `mediaKeyControlEnabled: true` and the Tahoe
HUD. The public list `CGGetEventTapList` shows its HID tap enabled
for systemDefined events only. It shows no Cascade volume tap.

The TCC logs of Cascade process 61596 report `result: false` for
`kTCCServiceAccessibility`. After build and relaunch, process 65586 confirms
`Volume routing status: permissionRequired`. The established cause of the missing
filter is the permission denied to the current build; it is not shown that
FineTune is taking events away from an already authorized Cascade tap.

The FineTune code examined is commit
`2285279d36d3f8115c1c2d4aecd904f1bdf96a51`:
[MediaKeyMonitor](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Keys/MediaKeyMonitor.swift).
It consumes the keys with an HID tap and changes the volume through its own
backend, then presents its HUD. It does not globally disable the macOS OSD.
Cascade keeps its own CoreAudio implementation and its own queue;
no GPL sources were copied and no FineTune preferences were modified.

## Implementation

- Private IOBluetooth battery with verified runtime signatures, IORegistry fallback
  attributed through the exact address. Unavailable data remain unknown;
  the persistent cache provides only the model identity, never historical charge.
- Read on connection off the main actor, with at most one retry.
  Cancellation and event identity prevent stale updates.
- Circular charge with an accessible value and label; minimum of the known earbuds,
  case separate. The ambiguous zeros of the private APIs are unknown; the explicit
  zeros of the registry are preserved.
- AirPods and Pro: original 3D geometry, precomputed atlases, one three-second
  turn in the compositor. Static under Reduce Motion, teardown and cancellation
  of loading when the view hides. AirPods Max uses the symbol.
- `updateNotice` updates only an existing notice with the same identity/source
  and a higher revision, without extending the expiry or changing its priority.
  The integration arms the Bluetooth override only for the initial event.
- Fixed the `addressString` IUO crash on disconnection, reproduced before
  the fix. Nil callbacks are guarded and the token keeps the identity
  when the framework has already discarded the device data.
- Volume: bounded recovery of the tap after the system disables it, renewal
  after sleep/session, new permission check on return to the app/menu.
  Mute repeats do not repeat writes, reads or notices.

## Checks run

- 85 CascadeKit tests, 12 suites: `/private/tmp/cascade-airpods-kit-tests.log`.
- 37 Swift 6 volume checks with warnings as errors:
  `/private/tmp/cascade-airpods-volume-tests.log`. The regression for mute
  held down failed before the fix (`cascade-volume-red.log`).
- Bluetooth harness and 13 legacy policy checks passed:
  `/private/tmp/cascade-airpods-bluetooth-tests.log`.
- Full Debug build and `codesign --verify --deep --strict` succeeded:
  `/private/tmp/cascade-airpods-app-build.log`. The only build warning:
  AppIntents metadata extraction skipped because they are not used.
- Updated app launched through CUA from the path
  `/private/tmp/cascade-airpods-derived/Build/Products/Debug/Cascade.app`.

- Graphical test of the factories and the animation cycle passed:
  `zsh scripts/test-bluetooth-presentation.sh /private/tmp/cascade-airpods-derived/Build/Products/Debug`.
  Checked: three-second duration, no restart on enrichment, Reduce
  Motion, fast cancellation and release of resources. Real render of the
  factories: `/private/tmp/cascade-bluetooth-presentation/notices.png`.
  The render verifies the contents, not a new real Bluetooth connection.

## Verification boundaries

The Bluetooth probe had no connected devices; battery and recognition
are verified through runtime, parser and fixtures, not through a new
hardware connection. The preview in the menu uses explicitly synthetic values.

The actual volume override still requires granting Accessibility to
this build from the system and trying real keys. The test in an already
authorized CLI process does not prove the app's permission. No valid development
certificate is available: the build is ad hoc signed and a recompilation may
require a new macOS authorization.

No audio apps were closed and no volume, FineTune settings or
system permissions were changed. If FineTune reinstalls its own tap before Cascade,
the priority between the two apps must be verified on the real gesture; no
loop of competing tap reinstallation is introduced.

Sources for the metadata: installed Apple runtime and
`IOBluetoothUI.framework/Resources/AssetPaths.plist`,
[Hammerspoon battery](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/battery/libbattery.m),
[ESPHome AirPods implementation](https://github.com/myhomeiot/esphome-components/blob/main/examples/ble_gateway/airpods.yaml).
