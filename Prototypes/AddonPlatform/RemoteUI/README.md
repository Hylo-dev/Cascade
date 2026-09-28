# Remote SwiftUI scene — source-verified prototype

This separate target compiles a native ExtensionKit scene containing a SwiftUI title,
count, button and menu. The host mounts EXHostViewController in a nonactivating NSPanel.
Its identities use `hylo.Cascade.AddonSceneProbe` so it does not replace the headless
process fixture. Deployment target remains macOS 14.

**Source logic and compilation are verified; native interaction is not.** On20September2026,
the counter protocol passed its standalone Swift check and all three targets built in
Release with the existing Apple Development signing configuration. The host assigns a
fresh session after validating echo/PID on the authenticated anonymous XPC channel.
Initial/increment/reset events must have the expected sequence and count transition;
the host emits `counterChanged` observations with session, sequence, action and count.
The UI permits one event in flight and waits for its matching acknowledgement before
enabling the controls. Payloads are checked against1024 bytes before application decode,
with a2s acknowledgement deadline and at most1000 user actions per session. Errors,
channel loss and scene deactivation disable the session; no automatic reconnect or polling.
The fixed probe supports only echo and subscription, not workload/crash commands.

No scene activation, actual counter delivery over XPC, visual interaction, focus,
VoiceOver, resize, clipping, process termination or resource measurement is qualified.
The reducer check is complemented by host/provider callback checks that execute the real
classes in memory with controlled delivery and invalidation. They create no OS connection
or scene; XPC admission/delivery and physical process lifecycle remain unqualified.
Application payload checks do not constrain allocations performed internally by XPC.

Run the single in-memory check from the repository root:

```sh
check_dir=$(mktemp -d /private/tmp/cascade-scene-check.XXXXXX)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -warnings-as-errors -module-cache-path "$check_dir/modules" \
  Prototypes/AddonPlatform/RemoteUI/Shared/ProbeMessage.swift \
  Prototypes/AddonPlatform/RemoteUI/Tests/ProbeCounterTests.swift -o "$check_dir/check"
"$check_dir/check"
```

The native UI tool stalled for approximately 10.5 hours on reading the extension
selection window. After it returned, the provider switch was still off. The browser
was closed and the interaction was not repeated. This is a test-tool impediment,
not evidence that ExtensionKit scene hosting itself failed.

Build independently of Cascade:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun xcodebuild -project Prototypes/AddonPlatform/RemoteUI/AddonPlatform.xcodeproj \
  -scheme AddonPlatform -configuration Release \
  -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/CascadeAddonRemoteScene" build
```

Products are `CascadeAddonSceneProbe.app` and `CascadeAddonSceneProbeContainer.app`
in that DerivedData directory's `Build/Products/Release`. First register/open the
container and use the host's `--browse` mode to enable this fixture through Apple's
selector. Launching the host normally then attempts the scene. The browser and interactive host have a180second exit timer, which does not prove
provider termination; connection setup has a2second deadline. The browser must be closed before launching a fresh host test.
Neither target is a production dependency. This stub does not pass task 00.3 or P0.

The launcher and C0d remain blocked. The source increment does not authorize new native
process-death experiments or qualify the installed OS/editor/signing matrix.

## Endpoint callback checks

The following checks exercise the actual endpoint classes. `PROBE_COUNTER_TESTING`
removes only their app entrypoint attribute. The host check creates no XPC object;
the provider check controls acknowledgement delivery and exercises the real2s timeout.
Both reject invalid/stale replies and preserve terminal state. The host retires its
invalidation callback once, including concurrent close requests; provider activation
completion is delivered once on success, timeout or channel loss.

```sh
check_dir=$(mktemp -d /private/tmp/cascade-endpoint-checks.XXXXXX)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -target arm64-apple-macos14.0 -D PROBE_COUNTER_TESTING -warnings-as-errors \
  -module-cache-path "$check_dir/modules" \
  Prototypes/AddonPlatform/RemoteUI/Shared/ProbeMessage.swift \
  Prototypes/AddonPlatform/RemoteUI/Host/ProbeHost.swift \
  Prototypes/AddonPlatform/RemoteUI/Tests/ProbeCounterHostTests.swift -o "$check_dir/host"
"$check_dir/host"
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swiftc \
  -target arm64-apple-macos14.0 -D PROBE_COUNTER_TESTING -warnings-as-errors \
  -module-cache-path "$check_dir/modules" \
  Prototypes/AddonPlatform/RemoteUI/Shared/ProbeMessage.swift \
  Prototypes/AddonPlatform/RemoteUI/Provider/ProbeProvider.swift \
  Prototypes/AddonPlatform/RemoteUI/Tests/ProbeCounterProviderTests.swift -o "$check_dir/provider"
"$check_dir/provider"
```

These commands were verified on the local arm64 machine. The deployment target
matches the prototype; this is not an execution result on macOS14 or Intel.
