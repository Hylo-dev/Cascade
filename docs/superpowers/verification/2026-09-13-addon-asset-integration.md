# C5: canonical asset integration

## Implemented scope

`AddonRuntime` owns the ImageIO/CoreGraphics decoder, the raster coordinator and
`AssetState`, using the same ResourceGovernor. Import and release check the
verified identity, digest, feature, assigned publication and current connection.
The commit of publications and asset references is synchronous and atomic after
resource admission. A rejected request does not advance the sequence.

Publications retain all declared references, including in non-visible
representations and in the future entries of the timeline already admitted and
bounded by the host. Provider exit and explicit release remove the import
aliases, preserving the images already published. End, expiry, deactivation
and stop revoke the authority; the pixel quotas stay occupied until the last
real CoreGraphics reference.

The presentation resolver keeps the revision observed by the view and
forwards it in every lookup. The runtime verifies the canonical revision and uses its own
clock: the caller cannot choose a past date to get around the expiry.

## Evidence and fixes

Behavioral failures were observed before the implementations of
references, asset state, runtime integration, view revision and release.
The first tests with real PNGs also found UUID aliases that did not conform to the
content grammar; the host prefix `asset-` solves the problem.

The review and the final check fixed three regressions:

- Publications without assets needlessly required additional metadata.
  The case with an already full quota now keeps the pre-existing behavior.
- A successful import did not drain a service completion that arrived during
  admission. The deterministic test observed a missing outcome and the job quota still
  occupied. Draining now happens before the final insertion, keeping the
  reservation of the pending metadata and rechecking the authority after the wait.

A further test, after the admission of the message's temporary memory,
reproduced the rejection of the end of a publication with images at a full quota.
End and replacement with content without images now use the metadata already reserved
for the removals only. A mixed batch still reserves all new references
before the commit, without spending future refunds. The initial admission of the message
remains unchanged.

Targeted logs in `/private/tmp`: `cascade-asset-references-{red,green}.log`,
`cascade-asset-state-{red,green}.log`, `cascade-asset-empty-{red,green}.log`,
`cascade-asset-release-{red,green}.log`, `cascade-asset-presentation-{red,green}.log`,
`cascade-runtime-assets-{red,drain-red,release-red,final}.log`,
`cascade-asset-removal-{red,green}.log` and
`cascade-runtime-assets-removal-{red,green}.log`.

Independent review concluded with no open findings. The final targeted runtime
suite contains 37 tests; AssetState contains 12. The reference tests
number 5 and the presentation tests 18, including the pre-existing cases of those suites.

## Complete verification and delivery

**536 Swift tests passed**, 29 more than the decoder baseline (507), run with
`--no-parallel` and exit 0: Runtime 304, Presentation 20, CascadeKit 170,
Contracts 38, Tool 4. Final log:
`/private/tmp/cascade-asset-integration-final-tests.log`.

350 build/test inputs were compared between the workspace and the local copy
`/private/tmp/cascade-asset-integration`, then frozen in the record
`/private/tmp/cascade-asset-integration-build-inputs.json`. The final verification
also comes after the last formatting of the tests. No change from the earlier
work was reverted or included in a global commit.

Signed Debug build succeeded with `scripts/build-development.sh`; codesign
deep/strict verification succeeded and `/Applications/Cascade.app` updated to the build
in `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`.
Log: `/private/tmp/cascade-asset-integration-app-build.log`.
The 350 inputs are still identical after the compilation.

Normal quit and relaunch verified: PID 60288 terminated, new stable instance
PID 69877 at the expected path, no forced termination. Record:
`/private/tmp/cascade-asset-integration-restart.json`.
Last available reading of the weekly usage: 19%, below the 60% ceiling.

## Environment and limits

macOS 27.0 beta, build 26A5425a, arm64; Apple Swift 6.4 with Xcode beta.
The minimum target remains macOS 14: this is not evidence of execution on macOS 14.

The tests use the real decoder, CGImage and governor, with controlled transport and clock.
They do not qualify external addons, provider signing, launcher, real processes,
decoder resistance to hostile input or the lifetime of real SwiftUI views.
The native C0d gate remains closed. No tracing participant was started.

The API is internal: each import is limited to one publication. Before fixing the
public SDK contract, reuse across publications of the same addon within compatible
privacy scopes remains to be decided. This increment does not introduce a
new account model: the authority of the service partitions already exists in the
broker. Asset transport, snapshot transfer to the MainActor renderer,
cache and persistent restore remain to be integrated. C5 is not declared complete.
