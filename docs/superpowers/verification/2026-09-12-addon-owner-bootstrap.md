# Separate per-addon bootstrap: 12 September test

The prototype with a distinct bootstrap per addon and a Worker that inherits its sandbox has
completed all four planned cases on the local configuration. Data isolation, data
continuity and the controlled replacement of the executable were observed.
The production launcher stays disabled: this test uses fixed code and does not yet qualify
supervisor death, arbitrary packages or all the supported platforms.

## Configuration and result

Five signed executables from the same build: trusted Supervisor without App Sandbox,
bootstrap A/B with App Sandbox only, Worker A/B with App Sandbox and inherit. All
use Hardened Runtime, without debug exemptions or additional permissions. The strict
signature, the expected certificate, the identities, the exact profiles and the embedded
Info were checked before running the fixture.

| Case | Observed behavior | Supervisor / child | Outcome |
| --- | --- | --- | --- |
| O1 | A creates and rereads its own sample | 45212 / 45216 | Both exited with code 0 |
| O2 | B creates its own sample; opening sample A for reading and writing denied | 45217 / 45218 | Both exited with code 0 |
| O3 | A finds content and inode again; access to sample B denied | 45221 / 45222 | Both exited with code 0 |
| O4 | Same A comparison under exec control; new Worker identity verified while stopped and single resume succeeded | 45223 / 45224 | Both exited with code 0 |

The cross denials are EPERM, not missing files. The owner's positive access
in the previous case proves that the target existed. The foreign open, had it
succeeded, would have been closed without reading or writing data. Only synthetic
samples were used: at most 192 bytes of content; the allocation of the containers by
macOS stays separate and unmeasured.

The eight processes have effective exit confirmations, through the wait of the owned child and
kernel notifications. No guardrail intervened. The observed durations of the whole case
are about 1.318 / 0.585 / 0.064 / 0.070 seconds: they are single observations of the fixture, not
runtime benchmarks or launch percentiles. The native and Python time domains stay
separate. O4 keeps the original alarm and observes the new public identity S3 before
the single resume request, followed by the Worker's S4.

## Provenance and checks

Environment run: macOS 27.0 beta 26A5425a, arm64, SDK 27.0, Apple clang 21.0.0;
compiled with deployment target 14.0. Development team `A6A5HQL6K4`, leaf
certificate SHA1 `4A857D842A5406C2D3071776FDE7B27B3098FE63`. They are not evidence on macOS 14,
with another publisher or with a distribution signature.

Command: `zsh scripts/test-addon-owner-bootstrap.sh`, in the isolated copy of the project.
Session 39329 ended with code 0. Artifacts `/private/tmp/cascade-owner-bootstrap-hgKoR6`.
Raw report `owner-report.json`, SHA-256
`e25739a128b3d6b53dbfe08b844ddcdb6aca9e13fb2f25fc7bcf6fd0c94bff59`.
The record distinguishes `fixedOwnerBootstrapObserved` from production admission, which stays false.

The first invocation had failed while preparing the signing command, before
launching any participant. That report and its only product stay unchanged
in `/private/tmp/cascade-owner-bootstrap-eNbrVB`. After the review, two arguments of
the command and the independent handling of signature validity errors were
fixed. The tests also cover real timeouts of the simulated observer, missing exit
confirmations and failures of the positive checks. 54 historical tests and 26 prototype tests pass.
The new run is the only attempt after the fix; there are no hidden
retries or permission variants. The review of the fixes concluded with no open findings. The later check on malformed fields was verified without repeating the native test and keeps the same outcomes on the recorded data.

## Limits and next steps

This evidence allows continuing with the bootstrap candidate with an inherited sandbox.
Still needed: control and testing of supervisor/host death, launch races,
verification of the distributed bootstrap and its dependencies, transport authentication,
native quotas and integration with the same SDK as the team's widgets. The VM protections
that cannot be fully observed stay unknown. The result does not enable addons in the app.

The two owners' samples stay in the diagnostic containers named in the report.
The only external check created by the observer was removed. No user data
was used or deleted; no recursive cleanup of the containers was performed.
