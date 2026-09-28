# Addon runtime: services and checkpoints

This report follows the [direct-v1 continuation](2026-09-10-addon-runtime-progress.md). The user authorized continuing on the parts already designed. The decision on the delegated work was not changed; the native launcher remains not admitted.

## Implemented parts

### C3 service broker

The broker receives verified identities and bindings chosen by the resolver through host APIs. Sessions are opaque and generate new grants on reconnection. It validates owner, feature, operation, private partition, provider/version and expiry before admitting calls. Interests survive the normal exit of the consumer; revocation, disabling and expiry remove them together with their grants.

Compatible sources share one registration and its metadata cost. Launch and invocation decisions are consumed only once; a stop request stays distinct from the observed stop. The ResourceGovernor keeps the process admissions until the exit is confirmed. No individual timer or loading of addon code in the graphics process. [Services contract](../../addons/services.md).

The review fixed the repeated admission of the same service requestID. The history keeps request and outcome per verified identity for ten monotonic minutes, even after reconnection; it requires current authorization to consult them and does not retry uncertain commands. It reserves space for the maximum response before sending. The 25 targeted tests pass and the review of the fixes has no open P1/P2 findings.

This is a protection limited to the retained history, not a promise of single execution after a restart or a removal of the history. The ResourceGovernor does not yet have an atomic reduction of the reservation: even small outcomes prudently keep the maximum reservation until expiry. The common 8 MiB budget can therefore reject new commands before the numerical limit of the history.

### C5 state and migrations

A save of opaque checkpoints within 64 KiB is implemented, with namespaces bound to identity/publisher, a bounded inventory of the files present, a prepared write and atomic replacement. Migrations receive a validated candidate and do not run addon code in the host. The 19 targeted tests pass and the review of the fixes concluded without P1/P2 findings.

Space already occupied and temporary files count toward the quotas. Revoking a handle keeps data and cost on disk; deleting the data is an explicit operation. A regular and bounded but corrupt or future checkpoint fails in its own namespace; unknown, unsafe or over-limit files make the reconciliation fail explicitly.

The review fixed two defects: the schema limit now belongs to each verified identity, and the checkpoint buffers are reserved only when needed. The registry admits up to 256 identities, with a limit the host can lower. One hundred inactive identities leave room for a real reservation of 7 MiB in the same ResourceGovernor. The tests also cover aggregate maximum migrations, rejection at full quota and release of only one's own resources, even when no memory remains available for another reservation. [State contract](../../addons/storage.md).

## Verification and integration

Full suite **337 Swift tests passed**, exit 0: Runtime 133, Presentation 15, engine 161, Contracts 24, tool 4. There are 44 new cases for this increment; the 5 further engine cases come from the preserved pre-existing changes. Environment: macOS 27.0 (26A5425a), arm64, Xcode 27.0 (27A5252f). These results do not qualify execution on macOS 14.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-addon-clang-cache \
swift test --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-addon-swift-build \
  --no-parallel --disable-sandbox
```

Full log: `/private/tmp/cascade-services-final-swift.log`. Only the pre-existing warning about the weak variable in the old PublicationStore tests remains. The behavioral RED runs and the targeted GREEN runs are kept in the execution reports. The native C0 fixtures and the unchanged Python suites were not rerun; their previous results remain historical.

The reviews of the two tasks, of the fixes and of the overall increment concluded without open P1/P2 findings. Integrated 18 exact files, comparing the previous versions and the reviewed hashes; verified 299 identical build inputs between the local copy and the original checkout. No commit or staging.

App build **succeeded**, exit 0, from the verified local copy via `scripts/build-development.sh`, with `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeAddonDevelopment`. Deep/strict signature verified and `/Applications/Cascade.app` updated. Log `/private/tmp/cascade-services-app-build.log`; the only warning of the app build: automatic extraction of the AppIntents metadata skipped in the absence of a dependency on the framework.

At the final launch no previous instance of the build was open, so no termination was necessary. Cascade was opened from the Applications link; observed a single new stable process, **PID 83405**, in the expected executable of `CascadeAddonDevelopment`. Verification: `/private/tmp/cascade-services-restart.json`. The operational updates after the review concern only this documentation and the summary in the plan. This concludes the services/checkpoint increment, not the whole feature.

The initial restricted check failed only the old popover test, because NSScreen.main was absent. The same test passed with access to the desktop session, 9/9. The updates to the graphics engine present in the original checkout, including NotchGlassRenderer, were also preserved in the build copy, without modifying them.

## Boundary of the result

These components do not constitute an admitted native runtime. C3 still requires authenticated transport, event cache/delivery, real sources and a coordinator. C5 does not include per-key SDK storage, an isolated asset/decoder or automatic restoration of the publications. No commands are replayed, nor are widget migrations simulated through in-process code.

The death of the supervisor can still leave a managed process alive in the C0 tests. This defect remains outside the already accepted risk on the autonomously delegated work. Clock, timer and later migrations wait for the real path and the tests required by the [plan](../plans/2026-09-10-addon-runtime-completion.md).
