# SwiftData runtime archive implementation

Status: implemented, independently reviewed and delivered. This record is distinct from the earlier [native SwiftData probe](2026-09-13-addon-swiftdata-archive.md). The probe selected and measured a framework; this increment implements the approved observed-disk policy and host restoration boundary.

## Reviewed components

| Component | Evidence | Result |
| --- | --- | --- |
| Protected observed-disk governor | `/private/tmp/cascade-observed-disk-task1-report.md`, `/private/tmp/cascade-observed-disk-metadata-green.log` | 26 focused/adjacent tests; independent review clean |
| Owner-bound SwiftData backend | `/private/tmp/cascade-swiftdata-task2-report.md`, `/private/tmp/cascade-swiftdata-task2-fix1-green.log` | 44 focused/adjacent tests, including 18 backend tests; unsafe-inventory refund correction independently approved |
| Canonical publication restoration | `/private/tmp/cascade-restoration-issuer-fix-report.md`, `/private/tmp/cascade-restoration-issuer-green.log` | 25 focused/adjacent tests, including 9 restoration tests; divergent-copy proposal correction independently approved |
| Bounded contract/archive codec | `/private/tmp/cascade-runtime-archive-b1-report.md`, `/private/tmp/cascade-runtime-archive-b1-fix1-green.log` | 63 covering tests; seven frozen hashes verified; production and scoped test review approved |
| Asset capture/direct-pin/raster primitives | `/private/tmp/cascade-runtime-archive-b2a-report.md`, `/private/tmp/cascade-runtime-archive-b2a-final-green.log` | 65 covering tests; three frozen hashes verified; independent review approved |
| Runtime coherent save | `/private/tmp/cascade-runtime-archive-b2b-report.md`, `/private/tmp/cascade-runtime-archive-b2b-final-green.log` | 66 covering tests; two frozen hashes verified; independent review approved |
| Runtime restoration | [B2 plan](../plans/2026-09-13-addon-runtime-archive-integration.md) | 102 focused/adjacent tests, including 14 restoration tests; five frozen hashes verified; independent implementation review approved |

These counts overlap adjacent suites; do not add them to derive a total. Root verified all 11 frozen source/test hashes for the first three reviewed components against their final reports before B1 integration.

The B1/B2 preflight and scoped admission-order review passed. Input, shallow envelope, inspection scratch and decoded graphs have separate protected lifetimes. Foundation and SwiftData private allocations remain estimates and observations; application-controlled buffers must be admitted before materialization.

## Retained-registry integration

B1/B2 runtime save and restoration are independently approved. C1 persistent absent-directory discovery has36 covering tests/three suites passing and five frozen hashes verified; independent implementation review is approved. C2 complete-registry inventory has55 covering tests/five suites passing and three frozen hashes verified; the late known-entry type/permissions correction and scoped review are approved. C3 concrete coordinator/runtime operations are implemented and independently approved; 87 covering tests in eight suites pass and all three frozen hashes match. Their preflight reuses existing secure directory helpers, protected observed tokens and the fixed registration model. No dynamic-registry or production bootstrap claim follows from these internal APIs.

## Delivery evidence

Full serial package suite passed: **679 tests in 69 suites** (432 runtime, 22 SDK, 170 transport, 51 contracts and 4 tools). All **381** selected build/test inputs match the original workspace, normalized integration copy and frozen manifest before and after build. The combined reviewed package verifies **30** final source/test hashes against the approved component reports.

Signed development build succeeded, including strict/deep signature verification and `/Applications/Cascade.app` link update. Normal termination and restart verified **PID 78065 → 97296**, with the updated process still running after two seconds; no forced termination.

Exact artifacts: `/private/tmp/cascade-swiftdata-runtime-full-tests.log`, `cascade-swiftdata-runtime-build-inputs.json`, `cascade-swiftdata-runtime-reviewed-inputs.json`, `cascade-swiftdata-runtime-review.diff`, `cascade-swiftdata-runtime-app-build.log` and `cascade-swiftdata-runtime-restart.json` in the same temporary directory. Intentional invalid SQLite fixtures emit diagnostics; all five package test runs passed. Existing Xcode destination/AppIntents and environment warnings do not block the signed build.

Only `/private/tmp/cascade-storage-barrier-tests` is used for SwiftPM build products, with `/private/tmp/cascade-plugin-module-cache` as the shared module cache. The existing Xcode derived-data directory is reused. No native addon/provider launch or C0d qualification is included.

## Boundaries

- A known SwiftData commit remains committed when subsequent inventory reports debt or a fault. No automatic deletion, sidecar truncation or invented physical-close refund is introduced.
- Complete retained-registry archive inventory is implemented and independently approved for the fixed registry. Concrete runtime forwarding is implemented and independently approved; production application bootstrap, dynamic registry and authenticated SDK transport remain separate.
- Available execution host is macOS 27 with a macOS 14 deployment floor; macOS 14 execution and power-loss durability are not qualified.
- Weekly allowance checked at delivery: 43%; the user's 60% ceiling remains binding, including verification work.
