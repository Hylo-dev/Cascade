# SwiftData Archive Qualification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. The root controls review, the single build cache and app delivery. Preserve the dirty checkout; no commits, staging or resets.

**Goal:** Make the selected SwiftData archive direction concrete and reproducibly verify its transaction, resource and lifecycle behavior before runtime integration.

**Architecture:** A standalone private ModelActor probe uses explicit saves and ordinary Data BLOBs, with separate-process reopen tests. A fixed stress case records the framework's retained files and memory rather than assuming payload size equals backend cost.

**Tech Stack:** Swift 6, SwiftData, Foundation, macOS 14 API floor, installed Xcode-beta toolchain. No external package or new SwiftPM cache.

**Spec:** [Selected SwiftData direction](../specs/2026-09-13-addon-swiftdata-archive-design.md).

## Global constraints

- SwiftData is approved; do not reopen that choice. Preserve original publication deadlines, no notice/command replay and compatible private asset sharing.
- No production runtime hookup before the resource contract is resolved; no C0d/provider launches.
- Use only task-owned temporary files; bound all probe modes, iterations and inputs. Do not inspect user archives or change process-wide umask.
- Record observed OS and signing/runtime limitations honestly. A probe is not production TDD, hard quota enforcement or minimum-OS qualification.
- Root verifies the selected sources, signed app build, Applications link and normal restart before delivery. Weekly consumption stays below 60%.

## Task 1 — Reproducible native probe

Files: `Prototypes/AddonPlatform/SwiftDataArchive/Probe.swift`, `README.md`, and `scripts/test-addon-swiftdata-archive.sh`.

- [x] Preserve the proven standalone ModelActor probe with private ModelContainer/ModelContext, autosave false, undo nil, CloudKit none and off-main assertions.
- [x] Compile with `swiftc -swift-version 6 -target arm64-apple-macos14.0` using the existing module cache. No package dependency is added.
- [x] In separate bounded processes, save/reopen generation 1, mutate then rollback/reopen, replace/reopen generation 3, and leave unsaved mutations/reopen. Assert both BLOB contents and generation each time.
- [x] Run a fixed 100-replacement case using a 1 MiB raster and 4 KiB document; inventory fixed DB/WAL/SHM files, current/peak memory and elapsed work. Report retained growth separately from current payload.
- [x] Precreate a private database under a task-owned 0700 root and verify observed file modes; reject unexpected probe paths/arguments. Save exact commands, exit codes and compact JSON evidence.
- [x] Independently review the complete three-file diff, including subprocess scope, cleanup, measurement units and unsupported claims. Fix concrete findings and rerun affected cases.

## Task 2 — Admission decision and delivery

- [x] Compare the real default-store behavior with existing managed-storage admission requirements. Record which allocations/file growth are controlled, estimated or only observed.
- [x] Update the previous archive decision and restoration draft to show SwiftData selected, while keeping unqualified production APIs pending.
- [x] Record the resulting implementation boundary and measured performance in a verification artifact. Continue runtime work only if it preserves approved authority and resource semantics.
- [x] Perform frozen-input signed app build, update `/Applications/Cascade.app`, normally restart and verify a new process. Run package tests only if package/app code changes; the probe has its own complete verification.

## Review ledger

Task 1: complete; exact three-file package independently approved. Root repeated all 11 stages from frozen inputs, exit 0. Evidence distinguishes while-open WAL from its observed truncation after normal exit.
Task 2: complete qualification; review established that estimated allowance plus post-save reconciliation does not meet the current managed-file preadmission contract. No weakened quota policy or deployment-floor change was selected. Production integration pauses at the explicit disk-policy decision. Signed build/link update and normal restart PID76239→78065 succeeded; 361 frozen inputs match. Weekly consumption observed27%.

[Final verification](../verification/2026-09-13-addon-swiftdata-archive.md) and [pending policy decision](2026-09-13-addon-swiftdata-disk-policy-decision.md).
