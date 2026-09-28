# P1: contracts, SDK and presentations

Implementation started on 9 September 2026 in the isolated worktree `codex/addon-runtime`,
preserving the previous state of the project. This report distinguishes the implemented
library from the process runtime, which remains subordinate to the P0 evidence.

## Available code

- **CascadeContracts:** versioned manifest and protocol, identity, revisions,
  permissions/leases as values, correlated requests/responses and rejection of out-of-bounds data.
- **CascadePresentation:** Swift components for text, symbols, admitted images,
  rows/columns, progress, clock/countdown and identified buttons; a SwiftUI renderer
  shared with the previews. No serialization of arbitrary views or closures.
- **CascadeAddonSDK:** async handlers and a context with only storage/service clients,
  events and connection grants. The clients are interfaces; the transport is not
  replaced by running the provider in the graphics process.
- **CascadeRuntime / Resolution:** pure, deterministic decisions for addons and
  individual features, service versions, cyclic dependencies, launch order, old
  bindings, verified identity and separate consent for another publisher's services.
  The returned plan does not install, launch or grant permissions automatically.
- **CascadeRuntime / Publications:** host-owned state within 8 accounted MiB,
  instance, activity and alert quotas, finite timelines and deadlines, terminated sessions
  that cannot be reused. The producer can disappear without erasing the received values.
- **CascadeKit / AddonPresentation:** adaptation of the values to the notch, identities
  separate from the existing integrations, privacy before the views, references to
  admitted assets and revocable contexts/actions. No provider enters these factories.

The public documentation is in [protocol.md](../../addons/protocol.md),
[manifest.schema.json](../../addons/manifest.schema.json),
[content.md](../../addons/content.md) and [requires.md](../../addons/requires.md).
The new products keep macOS 14 and use Swift 6; the existing engine keeps
its own Swift 5 mode with MainActor isolation.

## Checks and limits

The final check of the whole package passes: **230 tests, zero failures**, with
`--no-parallel`. There are 35 Runtime tests (28 resolver, 7 publications), 15 Presentation/SDK,
156 engine/bridge (17 of them new bridge tests) and 24 Contracts: 91 tests added to the baseline.
The independent review of the resolver also repeated three external reproductions,
confirming coherent rollback, maximum depth and rejection of incompatible constraints.

Final command, run with exit status 0:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-addon-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-addon-swift-cache \
xcrun swift test --disable-sandbox --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-addon-final-tests --no-parallel
```

Session log: `/private/tmp/cascade-addon-all-verified.log`. An earlier targeted check
passes 90 tests; the full suite also includes the preview test that was excluded
by name from that filter. The test carries a compile warning on the weak variable
of the fixture producer; it is not a warning in the Runtime code.

The concurrent runs of the baseline and of the review had shown a pre-existing
timing failure in `controlDragKeepsExpandedContentAliveUntilMouseUp`
(`NotchControllerTests.swift:924`). The case passes in isolation and in the final sequential run
in 290 ms. We did not modify the drag behavior or that test to hide the
result; the interference from the concurrent suite remains to be investigated.

The fixes with behavioral regression tests cover oversized Unicode messages,
content accessibility, service scopes, rollback of nested dependencies,
limits on already-admitted chains, joint constraints on the same service, resurrection
of terminated sessions and loss of the identity of future publications. The search uses
choices in a bounded array to avoid exhausting the stack with wide conjunctions.
A Store → bridge test verifies present content, a pending future revision,
activation at the deadline and definitive deletion of the future entries on disable.

The [renderer preview](assets/addon-content-preview.png) was produced and inspected. It is a component fixture, not the final layout of a widget. VoiceOver in the panel,
reduced motion/transparency preferences and consumption with visible/hidden surfaces
remain **not qualified**. No static image test is presented as an
energy measurement or as validation of the remote scene.

The scheduler that will feed the deadlines, the broker, complete storage/assets, the catalog,
the remote SwiftUI scene and the Clock/Focus/alerts/media migration belong to later
phases. The team's addons will have to use the same SDK and the same controls;
no privileged path was added to anticipate the migration.

The [P0 gate](2026-09-09-addon-runtime-P0.md) remains open and prevents presenting
this work as a complete addon runtime or as already-qualified efficiency.

## Build and integration

The production code of the engine depends on Contracts and Presentation. Runtime is used
in the integration test, not imported by the notch factories. The adaptation
compiles, but the app → scheduler → bridge composition still belongs to P3.
The reintegration preserves the pre-existing files and verifies their hashes before copying.
Reintegrated **106 verified files** without conflicts; the hashes of the pre-existing files
outside this change remained unchanged.

Final build from the main checkout, outcome **BUILD SUCCEEDED** and signature verified:

```sh
CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeAddonDevelopment \
/bin/zsh scripts/build-development.sh
```

The script updated `/Applications/Cascade.app` to the freshly compiled build.
Verified the normal quit of the old process PID 32179 and the launch of the new
PID 49632 from the executable `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`.
Session logs: `/private/tmp/cascade-addon-integrated-build.log` and
`/private/tmp/cascade-addon-restart.json`. These PIDs describe the verification;
they are not identifiers to reuse to control future processes.

### Closing the verification, 10 September

Added 23 files from the P0 alternatives: the reintegrated total is 129 files, without conflicts
and without changes to the pre-existing files outside this change. The P1 code and
its tests did not change after the full 230-test run. The new prototypes remain
separate from the production package and keep the containment profile that was not passed.

Last build from the main checkout: **BUILD SUCCEEDED**, log
`/private/tmp/cascade-addon-final-app-build.log`; signature and Applications link
verified. Normally closed the PID 49632 instance and observed the launch of PID 56980
in the expected CascadeAddonDevelopment path. No fixture process was
left open. Evidence: `/private/tmp/cascade-addon-final-restart.json`.
