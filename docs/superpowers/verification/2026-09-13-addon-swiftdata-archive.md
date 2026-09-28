# SwiftData archive qualification — verification

Status: reproducible probe implemented and independently reviewed; production archive
integration is withheld pending the managed-disk admission decision.

## Implementation and scope

The user selected SwiftData. Added:

- `Prototypes/AddonPlatform/SwiftDataArchive/Probe.swift`
- `Prototypes/AddonPlatform/SwiftDataArchive/README.md`
- `scripts/test-addon-swiftdata-archive.sh`

The private ModelActor uses an independent context and serial executor, explicit
saves, autosave disabled, no undo manager and no CloudKit. One row stores generation
and publication/raster Data BLOBs together, without external binary storage. All
container creation and storage operations assert they are off the main thread.
No persistent model crosses the worker boundary. No dependency was added.

This is experimental qualification, not the production archive implementation.
Publication validation, canonical asset reconstruction, native transport and runtime
bootstrap remain unchanged. No addon provider, tracing gate or C0d launcher ran.

## Fresh root verification

Command: `/bin/zsh /private/tmp/cascade-swiftdata-integration/scripts/test-addon-swiftdata-archive.sh`.
Result: **11 separate-process stages passed, exit 0**. The native probe was compiled
with Swift 6, optimization and deployment target `arm64-apple-macos14.0`, then ran
on **macOS 27.0, build 26A5425a**. macOS 14 runtime qualification remains false.
No warnings/errors were found in this final run's compilation or stage logs.

Checks cover explicit save/reopen, full-byte generation-pair consistency, rollback,
unsaved changes with autosave disabled, a 256 KiB publication plus 4,000,000-byte
raster replacement, and exactly 100 updates of a fixed 1 MiB raster/4 KiB document.
Both fixture roots were private, and every observed database/sidecar was a regular,
single-link file with mode 0600. Fixture hygiene is not production root-security
qualification. Every child had a fixed timeout and all completed normally.

Evidence:

- Final report: `/private/tmp/cascade-swiftdata-archive-kXpAlZ/report.json`
- Captured stdout: `/private/tmp/cascade-swiftdata-final-run.json`
- Harness stderr: `/private/tmp/cascade-swiftdata-final-run.log`
- Frozen reviewed diff: `/private/tmp/cascade-swiftdata-package.diff`
- Implementer report: `/private/tmp/cascade-swiftdata-package-report.md`

## Resource observations

| Workload | Open/work/verification wall time | Whole-process peak footprint | Managed files while open | Managed files after normal exit |
| --- | ---: | ---: | ---: | ---: |
| Replace with 256 KiB + 4,000,000 bytes | 83.934 ms | 26,378,912 bytes | 5,653,832 bytes | 5,218,304 bytes |
| 100 replacements of 4 KiB + 1 MiB | 688.899 ms total | 14,516,896 bytes | 5,756,064 bytes | 1,339,392 bytes |
| Reopen after the 100 replacements | 11.497 ms | 6,898,312 bytes | 1,339,392 bytes | 1,339,392 bytes |

Times include container opening, actor dispatch and verification, not just commit.
Peak/current physical footprint comes from Darwin `proc_pid_rusage`; it includes
the entire executable, frameworks and validation. It is not incremental Cascade
memory use, a benchmark comparison with GRDB/Foundation, or a resource ceiling.

The repeat-update WAL was 4,416,672 bytes while open and zero after normal exit
and subsequent reopen. Read-only inspection observed 101 ATRANSACTION and 101
ACHANGE rows; these private names are observations, not API dependencies. The
review caught and corrected an earlier overgeneralization from the disposable
probe that a nonzero WAL necessarily survived restart. The packaged and fresh
root runs demonstrate truncation here, without establishing an API guarantee.

No interrupted commit, save failure, disk-full case or power-loss test is claimed.
The measured cases do not prove a worst-case framework allocation or disk growth.

## Review and decision

Independent review approved the exact three-file package with no blocking code
findings. It separately confirmed that an estimated allowance plus post-save file
inventory does not establish the existing managed-file preadmission contract.
Container creation/open/recovery must also be accounted for, including failures
and any additional managed file. These corrections are reflected in the
[disk-policy decision](../plans/2026-09-13-addon-swiftdata-disk-policy-decision.md).

No resource policy was relaxed. To proceed with the evaluated default-store
approach, the user must decide whether to allow observed internal file growth,
explicit overbudget debt and recovery semantics. This is a new contract decision,
not a second approval of SwiftData itself or a claim that SwiftData is categorically
unsuitable. The [selected design](../specs/2026-09-13-addon-swiftdata-archive-design.md)
and [implementation plan](../plans/2026-09-13-addon-swiftdata-archive.md) record the boundary.

## Application delivery

All **361 selected build/probe inputs** match the workspace, normalized copy and
frozen SHA-256 record at `/private/tmp/cascade-swiftdata-build-inputs.json`.
The **334 application/package inputs** also exactly match the prior 560-test
storage-barrier baseline. No package/app source changed, so those tests were not
repeated for a standalone probe; the new harness was run in full.

The signed development build passed, exit 0, using the project's build script.
Strict/deep signature verification succeeded and `/Applications/Cascade.app` was
updated to the product in `CascadeAddonDevelopment` derived data. All 361 frozen
inputs still matched after the build. Log: `/private/tmp/cascade-swiftdata-app-build.log`.

Normal termination and launch passed, exit 0: **PID 76239 → 78065**, with the new
process still running after two seconds. No forced termination was used. Record:
`/private/tmp/cascade-swiftdata-restart.json`.

Latest weekly allowance observation: **27% consumed**, timestamp
2026-09-13T10:59:43.237Z, below the user's 60% ceiling. The intervention stops at
the verified managed-disk policy choice, not because that allowance is exhausted.
