# Required SDK check before development builds — delivered

Status: corrected two-file implementation, independent review, live integration and positive signed app build/restart **PASS**. Delivered together with the accepted subscription unit. This does not certify native parity or complete C12.

The official build script adds a mandatory foreground invocation of the existing SDK checker before xcodebuild. It passes the same selected DEVELOPER_DIR and an explicit project root. Failure or a missing checker stops the script before compilation, signing or application-link update; there is no skip flag. All existing Xcode/signing/link arguments are unchanged.

Four real integration fixtures pass in37.448s using SwiftPM, the existing SwiftParser checker and zsh executed-command traces. Private source imports, private SDK target dependencies and a missing checker all stop before xcodebuild/codesign/update-link. A benign fixture passes the checker, then reaches real xcodebuild and fails because the fixture intentionally has no project. This is positive ordering evidence, not a successful app build. Historical behavioral RED uses the original build script, which reaches xcodebuild without checking the injected private import.

The corrected test inherits HOME/CODEX_HOME/CFFIXED_USER_HOME unchanged, uses private explicit cache/derived/temp paths and records only relevant allowlisted environment inputs. Historical full-environment records were minimized with a disclosed hash ledger; that does not turn earlier HOME-overridden runs into corrected-environment evidence. Exact logs/source outcomes remain preserved.

The [independent review](../../../.scratch/codex-addon/20260918-continuation/required-sdk-build-check-independent-review.md), including its documentary-coverage addendum, verifies257 archived hashes, the exact two-file diff, all four corrected fixture records and the unchanged live preimages. [Corrected handoff](../../../.scratch/codex-addon/20260918-continuation/required-sdk-build-check-corrected-handoff.md), freeze, proof and sanitation ledger retain details. Read-only archive mode0444 was installed as0755 for the shell and0644 for the Python test.

The guarantee concerns `scripts/build-development.sh`. Direct Xcode/UI invocations remain separate. The checker audits the selected source imports and target/package dependencies of trusted manifests; it does not establish complete legacy registration migration, absence of every name-based factory, dynamic loading behavior or runtime admission. The exact472-file root delivery snapshot includes Examples; the real guarded build checked all three packages.

## Positive app delivery

Root imported the exact two independently reviewed files after acceptance of the frozen subscription unit. The484-input combined freeze changes no Swift input covered by the1084-test/96-suite run and Release Runtime compilation. The real official script passes3 packages/9 targets/88 Swift files/132 imports, then builds with Apple Development signing, verifies the signature and updates Applications. Total command22.95s, exit0. Normal quit/relaunch changes PID20946 to85871, with the expected executable stable for five seconds. [Combined delivery and limits](2026-09-18-addon-service-subscriptions-host-sdk.md).

Exact artifacts: `service-subscriptions-guarded-combined-freeze.json`, `service-subscriptions-guarded-build-snapshot-manifest.json`, `service-subscriptions-guarded-app-build*` and `service-subscriptions-guarded-restart-evidence.json` in `.scratch/codex-addon/20260918-continuation/`. All484 live hashes and472 snapshot hashes match after the build. The missing-project fixture remains only ordering evidence; this separate successful app build supplies the positive delivery proof.
