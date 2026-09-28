# P0: outcome of the native test of 9 September 2026

**Launcher gate: NOT PASSED.** The prototype is separate from the product and is not
an executor usable by Cascade widgets. P1 may proceed; P2/P3 do not incorporate
this launcher until termination and resource control are demonstrated.

## Environment and verified path

macOS 27 beta (26A5425a), Apple Silicon, Xcode beta / Swift 6.4. Minimum compiled target:
macOS 14. The 14/15/26 machines and a second publisher identity are not available;
those cases are **unverified**, not implicitly compatible.

Three distinct Xcode targets: host `hylo.Cascade.AddonProbe`, standalone container
`hylo.Cascade.AddonProbeContainer`, extension
`hylo.Cascade.AddonProbeContainer.Provider`. Apple Development signing from the
project's development team. The container includes the extension and all its code;
no complete source app, framework of that app or same-named service is required.

The ExtensionKit target generates the correct entry point. Discovery through
`AppExtensionIdentity.matching`, activation through the Apple browser, launch with
`AppExtensionProcess`. A first channel passes only an anonymous endpoint;
the ordinary application channel verifies team and signing identifier in both
directions with the Foundation code-signing requirements. The PID declared in the
response must match the peer PID provided by Foundation and differ from the host.

The tests use only sentinel files created by the harness, localhost and `/usr/bin/true`.
No user file or credential is read. The test process is not a
worker registered or launched by Cascade.

## Observed results

| Test | Outcome | Evidence / limit |
| --- | --- | --- |
| Real ExtensionKit build | PASS | Signed Debug and Release, products in DerivedData |
| Standalone authenticated echo | PASS | Release: host 43206, provider 43209, correlated UUID, 165.41 ms overall; external deadline 2 s |
| Normal host shutdown | PASS in the fixture | `NSApplication.terminate`: host 43401, provider 43403, exit observed 318.72 ms after the start of the test |
| Host crash/kill with an uncooperative worker | PASS in the fixture | SIGKILL of host 43410 only; provider 43412 exited, 154.12 ms after the start of the test |
| Explicit stop while the host is alive | repeated FAIL | `AppExtensionProcess.invalidate`, invalidation of both channels, listener and release of all references: spin worker still present after 2 s, in Debug and Release |
| Reading the sentinel of another addon folder | Access denied | Sandbox without external-file entitlements; the fixture really exists |
| Direct network connection | Access denied | `connect` to localhost returns a permission error |
| Subprocess creation | Allowed | `/usr/bin/true` is launched: App Sandbox alone does not guarantee the absence of additional processes |
| Host with a different bundle/signing identity | Discovery denied | No identity found; this is **not** equivalent to a complete proof of rejection on the authenticated channel |
| CPU and physical footprint, subprocess aggregation | Not qualified | No RSS measurement is presented as physical footprint; an admitted supervision adapter is missing |
| Corrupted JSON message | PASS | Rejection caught without a host crash, 150.22 ms overall |
| PID reuse and safe atomic stop | Not qualified | The harness cleanup verifies fixture and start time, but it is not a production solution to PID reuse |
| Remote SwiftUI UI / focus / VoiceOver | Not implemented in the test | The preview of the ordinary P1 renderer does not count as remote ExtensionKit evidence |
| Other publisher / other OS | Unverified | Local signing and compilation with target 14 are not enough |

The individual latencies are diagnostic observations, not qualified p95s, benchmarks or
energy budgets. The spin case lasts a few seconds; the harness first closes
its own host and cleans up only the fixture's authenticated PID, verifying its
path and launch time. The host also has a five-second guardrail.

## Reproduced problems and decision

1. On the beta system in use, calling `setCodeSigningRequirement` directly on the
   `NSXPCConnection` managed by ExtensionFoundation causes SIGSEGV in libxpc. The
   public bootstrap with an ordinary listener resolves the authenticated exchange; no
   private API is used to work around it.
2. Invalidation did not stop the blocked worker while the host stayed open.
   Removing the earlier browser window, releasing all references and switching
   to the Release build did not resolve the test. Closing the connection is
   therefore not treated as terminating the process.
3. The sandbox allows subprocesses. Before public admission, evidence is needed
   that their cost and their exit are governed together with the addon, or a profile
   that actually forbids their execution. A declaration in the manifest does not solve it.

The gate remains closed because these points directly affect the promise of
controlled resources. No in-process executor was introduced, not even for
team widgets, and the approved guarantees were not silently reduced.
The next production work depends on a verified termination and observation
strategy; a different launch solution requires new P0 tests before the P2
transport. The remote scene and the widget migration remain open tasks in the plan.

## Reproduction and sources

[Prototype README and commands](../../../Prototypes/AddonPlatform/README.md).
The regenerable raw outputs are in `Prototypes/AddonPlatform/Results/` (ignored
in git). The JSON files record PID, requestID, fixture path, timings and outcome;
`lifecycle` and `sandbox` return an error as long as their respective conditions fail.

APIs compared against the public headers in the local SDK and the Apple documentation:
[app extension host](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app),
[extension for a host](https://developer.apple.com/documentation/extensionfoundation/building-an-app-extension-to-support-a-host-app),
[discovery](https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app),
[invalidate](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()).
The fact that a symbol is present in the SDK was not used as proof of the
corresponding runtime guarantee.

## Alternatives verified on 9–10 September

The direct child process alternative foreseen by the specification was also
implemented and repeated. The [DirectChild prototype](../../../Prototypes/AddonPlatform/DirectChild/README.md)
uses a separate native supervisor that preserves the identity of the not-yet-reaped
child, imposes `RLIMIT_NPROC` soft/hard 0 before exec and reacts to the closing of the
host's pipe. Host and supervisor keep their original limits.

The real tests show termination of the uncooperative child with the host still alive and
after host exit/crash; direct child creation and raising the limit denied;
successful CPU/footprint reads and CPU compared with wait4. These results
solve the child-control primitive, **not the whole profile**.

A counterexample prevents the move to production: the worker can ask
Launch Services to open a harmless, signed, readable app inside its own
bundle. The direct-child limit remains 0, but the launched process has parent PID 1 and
does not belong to the supervisor. The test checks the exact bundle path and
the marker produced by the app; it does not launch user applications. The three runs
explicitly fail `delegatedLaunchDenied`, with the other 15 checks passed.
The reproducible command is `/bin/zsh scripts/test-addon-direct-child.sh`; it exits 1 for
this reason. Independent review confirms the consistency of source, evidence and cleanup.

For ExtensionKit, looking up an NSRunningApplication handle on the already
authenticated peer was also tested. The headless provider returns **no handle**:
`forceTerminate()` is therefore not called. This is not a rejected termination
request. Command: `CASCADE_PROBE_CONFIGURATION=Release /bin/zsh
scripts/test-addon-platform.sh --case application-stop`; outcome FAIL observed with
host PID 50118/provider PID 50120. The full log preserves the diagnostic event.
The [Apple documentation](https://developer.apple.com/documentation/appkit/nsrunningapplication)
limits this API to tracked applications, not to every process.

The [remote SwiftUI scene prototype](../../../Prototypes/AddonPlatform/RemoteUI/README.md)
compiles, but the graphical check of the selector stayed blocked for about 10.5 hours.
The scene was neither enabled nor run: no interaction or remote lifecycle
test is declared passed. It is an impediment of the test tool,
not a demonstrated defect of ExtensionKit.

**Decision:** both execution paths remain experimental. Before P2,
control of work delegated to macOS must be demonstrated, or the total-containment
requirement for native code must be explicitly revisited. Forbidding
only this fixture's specific nested app would not demonstrate the guarantee.
The system of host-owned components and the P1 contracts remain valid; no
bypass was introduced to move the team widgets forward.

Independent repetition on 10 September: `/private/tmp/cascade-direct-child-root-verified.log`,
outcome 1 with only the delegated-launch check failing in all three cases.
The observed harmless apps have PIDs 56745/56749/56753 and parent PID 1. Final
RemoteUI build succeeded in `/private/tmp/cascade-remote-scene-final-build.log`; no
launch of the scene. Final ExtensionKit diagnostics in
`/private/tmp/cascade-application-stop-final.log` with the correct specific reason.
