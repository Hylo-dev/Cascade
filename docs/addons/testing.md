# Verifying an addon provider

A source provider can be verified without launching an addon process inside Cascade. These tests check the provider's behavior and its use of the public contracts; qualifying the installed addon also requires the host's native path.

## Standalone project

The [getting started guide](quickstart.md) shows how to generate a package with a provider, a manifest and tests. Run the build from a copy outside the checkout, pointing explicitly at the SDK package. The project must depend on the `CascadeAddonSDK` and `CascadeContracts` products; their public dependencies are resolved by SwiftPM. An import of `CascadeRuntime`, `CascadeKit` or private app sources introduces a dependency on the host and does not demonstrate the addon's independence.

Validate the manifest with `cascade-addon validate` and run `swift test` in the generated project. Manifest validation does not run the provider and does not verify signature, authorizations or process identity. The subsequent build evaluates the `Package.swift` chosen by the developer: the SDK path must therefore be treated as an explicit code dependency.

## Cases to cover

- Use host-assigned publication identities and verify that a foreign owner or session is rejected. The identifier in the manifest does not constitute authentication.
- Verify schema, content, finite lifetime, increasing revisions and the round trip of the returned values. A declarative countdown does not require a provider task that publishes every second.
- Correlate every action response with its `requestID`; cover wrong inputs, deadlines, a stale observed revision and duplicate requests. Publishing an updated state does not replace the action's completion.
- For persistent providers, destroy and recreate the instance using shared storage and a new context generation. Verify revisions, corrupt data, read/write errors and uncertain commit results. Do not turn a read error into absence of data.
- During the `await`s, try a second request, cancellation and stop. Actor isolation alone does not make a read, modify and write sequence indivisible.
- Use capability clients that fail explicitly when the fixture must not invoke them. A fake service that always returns success can hide an unexpected dependency.

An injected clock makes deadlines and restoration reproducible. Do not replace concurrency tests with arbitrary delays: explicitly control the points at which a write or a response stays suspended.

## Limits of provider tests

Unit tests do not prove package admission, publisher identity, revocation of an OS connection, process quotas, exit after the supervisor's death, or bundled/external parity. A successful write likewise does not prove that the host admitted the following output: persistence and publication are not a single transaction of the public API.

These properties need the integration and platform evidence described in the [addon plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md), using the same admission path planned for team and third-party addons. The native launcher gate remains distinct from the tests of source packages.

## SDK and example boundaries

The official `scripts/build-development.sh` script runs the check as a mandatory step before Xcode: a violation or a missing verifier stops the path before compilation, signing and the update of Applications. It uses the same DEVELOPER_DIR and passes the explicit checkout root, examples included. This guarantee covers the official script; direct Xcode invocations are separate. The [protected build verification](../superpowers/verification/2026-09-18-addon-required-sdk-build-check.md) distinguishes negative fixtures from the positive signed build.

To run it separately, use `scripts/check-addon-boundaries.sh` from the checkout. The check evaluates the trusted manifests of CascadeKit, StandaloneFocus, ServiceConsumer and StandaloneClock with the selected Xcode toolchain, verifies the targets' dependencies, derives from `swift package describe` the sources selected by the toolchain, and analyzes the actual Swift imports, including conditional branches. The allowed public products are CascadeAddonSDK, CascadeContracts and CascadePresentation. Private host dependencies/imports, @testable/@_spi access to the SDK, and generation through plugins or macros in the verified source profile are rejected. The examples' tests can use @testable on their own targets.

`--json` includes the source/manifest hashes, the evaluation commands and the compiler version; `--root /path/checkout` selects another copy of the four packages. The command uses its own temporary caches and deletes them when it finishes. It requires Python3 and an Xcode with SwiftParser/SwiftSyntax in the toolchain; DEVELOPER_DIR lets you select it. The manifests are executed by SwiftPM and must be trusted. This profile requires only Package.swift: the presence of versioned Package@swift manifests causes an explicit error.

`--test` runs the check's tests and compiles the real parser. The complete tests of the command require CASCADE_BOUNDARY_FIXTURE_ROOT pointed at a minimal, immutable source copy with CascadeKit and the three examples; if it is missing, these cases are reported as skipped. Do not point it at a checkout that contains build/cache or other large directories: the tests copy the fixture to introduce controlled defects.

The result concerns the static imports and graph in the chosen evaluation of the manifests. It does not replace compiling the providers, does not expand macros, does not certify alternative manifest environments or dynamic loading, and does not prove native parity, isolation or admission.
