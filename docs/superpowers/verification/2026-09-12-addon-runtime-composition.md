# Addon coordinator verification: 12 September 2026

Task C2b2 is implemented and approved in the isolated working copy. The package
passes **436 tests**, with an independent review concluded without required findings.
This result qualifies the internal composition of the runtime; the native launcher,
the integration into the app and the complete feature remain to be qualified.

## Verified behavior

`AddonRuntime` coordinates catalog and resolved dependencies, publication assignments,
launching and connecting providers, actions and services using the same
`ResourceGovernor` as the private broker. The content, the history of results,
the service interests and the process have distinct lifetimes. The expected exit of
a provider preserves the publications and the interests that are still valid; the new
generation must obtain new authorizations.

Admissions and the return of resources share a single owner
of the operation. Suspensions toward the broker and resource actors are
followed by checks of the current authority. Disabling and expiry of a job
can request the stop of the provider immediately even while another admission
is suspended. The permits of uncertain work remain counted until the exact exit
is observed; a stop request is not equivalent to that exit.

The internal transport distinguishes the message still being received from the one already
transferred to the operation that processes it. The limit is reported before
retention; the transfer keeps the slot occupied. Repeating a receive
does not allow discarding the message that another operation is processing.

A pending service completion does not confer a recoverable outcome,
a sequence update or a return of the permits. The broker remains
the only registry of the results. The receipt keeps the instant sampled
by the host without restoring revoked authorizations. The immediate outcome derives
from the effective confirmation; the removal of an entry during the exit of the process
is not interpreted as success.

Completions without a change to the content validate their own session and
sequence. Two independent providers do not invalidate each other through the global
revision of the publications. Normal content batches keep the atomic checks
already present. The replay, revocation and old-generation checks remain.

The projections of the configuration data and of the resolution are bounded
before encoding and retention, including the strings nested in the
versions. The tests also verify restricted quotas, outcomes retained at full quota,
exact returns, references to the publications and revision of exhausted authority.

## Evidence and review

Environment: Xcode beta, module cache in
`/private/tmp/cascade-addon-clang-cache`, SwiftPM scratch
`/private/tmp/cascade-addon-swift-build`. From the `CascadeKit` directory:

```sh
swift test --no-parallel --scratch-path /private/tmp/cascade-addon-swift-build
```

Result: exit 0, **436 tests**: Runtime 205, Presentation 20, engine 169,
Contracts 38, tool 4. Log `/private/tmp/cascade-c2b2-fix3-full-package.log`,
SHA-256 `3349e5e5d969f80613945a5c068912f8d54f918188c81a33ce34d08fc337fee0`.

The targeted check of the eight affected suites passes 104 tests. It must not be added to the
full suite, which includes it. All 14 hashes of the fix files were
compared with the report and rechecked after the full check.

The initial review and the three subsequent reviews of the fixes closed
the findings on resource ownership, authorities and concurrent completions.
The final verdict is Spec compliance PASS and Code quality APPROVED, without required
findings or new important defects in the last change. The reports, the immutable
diffs and the RED/GREEN evidence are kept in the plan directory
`.superpowers/sdd/2026-09-10-addon-runtime-completion/continuation-production/`.
The errors in the test preparation and the disk space error are recorded
separately from the behavioral failures.

## Current limits

The adapter used by the tests is internal to the tests. Not yet qualified: production
IPC transport, native decoding, stopping the worker on the death of the supervisor,
remote scenes, other publishers or macOS versions that were not run. The serial test uses the
mode already adopted by the project; the earlier problem of the AppKit test run
concurrently remains documented separately and is not declared resolved.

This continuation is not yet integrated into the original checkout and has not yet
produced a build, an update of the Applications link or a relaunch of the app.
The next task C0o is a limited experiment on the identity and data of two owners,
not the automatic admission of the launcher. The [completion plan](../plans/2026-09-10-addon-runtime-completion.md)
keeps the native prerequisites and the other deliveries separate.

Additional check before integration: the `ActionDispatcherTests` assertion on the reference to the publication after the history expires was checked separately, because it did not appear among the 14 final hashes. Review approved and single test passed on the current version; this evidence does not replace a complete pruning sequence in the runtime.

## Integration and build of 12 September

43 approved files were integrated into the main project; 332 build inputs
were compared and are identical to the verified copy. The build from the path
of the project was interrupted after observing Xcode waiting on NSFileCoordinator
in the recursive read of the project. Only the build process was interrupted,
with its effective exit observed; no iCloud setting or Xcode app was changed.

The same official script then compiled successfully from the identical local copy,
with signature verified and the `/Applications/Cascade.app` link updated. Cascade was
closed normally (PID 8956) and reopened from the new build: PID 47210, expected
path and stability verified. Log `/private/tmp/cascade-production-20260912-local-app-build.log`;
record `/private/tmp/cascade-production-20260912-restart.json`.

This delivery integrates the runtime foundations and the verified prototype into the project.
It does not yet enable addons in the product nor conclude the widget migrations.
The implementation of the shared storage and of the complete native path continues.
