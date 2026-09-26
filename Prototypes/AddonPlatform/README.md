# Native addon platform probe

**Experimental test fixture; not imported or launched by Cascade. P0 has not passed.**
It proves a real standalone containing application and a native sandboxed addon,
with an authenticated data channel. It also exposes two unresolved requirements:
explicit stop of a noncooperative worker while the host remains alive, and control
of subprocess resource usage. See [recorded results](../../docs/superpowers/verification/2026-09-09-addon-runtime-P0.md).

## Build and run

Requires Xcode, an Apple Development identity for the configured team, a logged-in
macOS desktop and Python 3. This fixture uses Cascade's development team and distinct
`hylo.Cascade.AddonProbe*` bundle identifiers; it does not impersonate another publisher.
The real Xcode ExtensionKit target supplies the extension entry point. Hand-linking
`@main AppExtension` as an ordinary executable does not create a working extension.

```sh
/bin/zsh scripts/test-addon-platform.sh --case browser
/bin/zsh scripts/test-addon-platform.sh --case standalone-echo
/bin/zsh scripts/test-addon-platform.sh --case lifecycle
/bin/zsh scripts/test-addon-platform.sh --case sandbox
/bin/zsh scripts/test-addon-platform.sh --case malformed
```

The first command opens Apple's extension browser. Enable only CascadeProbeProvider.
Discovery being empty before enablement is expected; the test never grants permissions
or silently substitutes an in-process provider. The container includes all provider
code and does not depend on a source application. First launching that container
registers the extension with the system.

Default configuration is Debug. Set `CASCADE_PROBE_CONFIGURATION=Release` to measure
an optimized build, `CASCADE_PROBE_DERIVED_DATA` for a different DerivedData directory,
and `DEVELOPER_DIR` for the selected Xcode. Avoid temporary/iCloud build products:
Launch Services disabled discovery under `/private/tmp` in this run, and iCloud
metadata broke signing. Source may remain in iCloud; products are in DerivedData.
The script unregisters **only the other configuration of this fixture's container**
to prevent a Debug provider from being measured by a Release host. Ambiguous discovery
is an error. No global registration database reset occurs.

Results and build output are written to ignored `Results/`. A nonzero exit means a
failed case; lifecycle and sandbox currently fail for documented requirements. `browser`
only opens setup UI and is not a verification. Metrics, unauthorized-peer automation,
and remote-scene cases are not implemented and do not return a synthetic PASS.

## Channel and authentication

1. `AppExtensionIdentity.matching` discovers the enabled identity.
2. `AppExtensionProcess` launches the real extension.
3. Its managed `NSXPCConnection` carries only an anonymous listener endpoint.
4. The addon connects to that endpoint over ordinary Foundation XPC.
5. `NSXPCListener.setConnectionCodeSigningRequirement` filters the provider's team and
   signing identifier before accepting it; the addon independently sets the expected
   host signing requirement before resuming its ordinary connection.
6. Only this authenticated channel exports the bounded JSON request protocol.

The bootstrap is not authentication and carries no business requests, permissions or
secrets. On the tested macOS beta, setting a signing requirement on ExtensionFoundation's
managed connection crashes inside libxpc; the public endpoint bootstrap avoids that
wrapper. No private method, KVC audit token, privileged task port or PID claim is used
as peer authentication. The response PID is cross-checked against Foundation's peer PID.
This is same-team development evidence, not cross-publisher qualification.

Supported fixed probes: echo, spin, malformed, checkpoint, exit, sandbox. `checkpoint`
currently only echoes a bounded value; durable checkpoint storage is not implemented.
`spin` deliberately runs noncooperatively; the external harness owns a short deadline,
checks the fixture executable and recorded start time, and cleans up only its own
fixture PID. The host has an additional five-second guard. **Run spin only through the
lifecycle harness.** Process observation/cleanup in that diagnostic harness is not a
production process supervisor or a claim of atomic PID-reuse-safe signalling.

## Platform matrix

| OS | API/build status | Executed |
| --- | --- | --- |
| macOS 14 | Deployment target; legacy discovery/process API is declared available | No machine available |
| macOS 15 | Same legacy path | No machine available |
| macOS 26 | Legacy discovery deprecated; newer APIs need a separate adapter/proof | No machine available |
| macOS 27 beta, 26A5425a | Xcode beta / Swift 6.4; native Xcode target builds | Yes, results linked above |

No minimum OS was raised. Compiling for 14 does not establish behavior on 14. The
production launcher and remote SwiftUI scene remain behind P0; the pure SDK can be
implemented and tested independently.

## Additional alternatives

- `--case application-stop` looks up the authenticated headless extension through
  NSRunningApplication. No handle is available on the tested OS; forceTerminate is
  not invoked. The host stays alive while the external harness records no exit.
- [DirectChild](DirectChild/README.md) proves useful direct-child stop/limits/metrics
  but fails complete process containment through a real Launch Services counterexample.
- [RemoteUI](RemoteUI/README.md) is compiled-only scaffolding. No live scene test passed.

None of these experiments changes the unpassed production gate.
