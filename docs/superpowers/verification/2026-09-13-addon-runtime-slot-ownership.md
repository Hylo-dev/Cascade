# Exact runtime ingress and delivery ownership

Status: implemented, independently reviewed and delivered under the [C7b0 plan](../plans/2026-09-13-addon-runtime-slot-ownership.md). Baseline C7a delivered with 732 tests, signed build/link and verified restart to PID 6324 at50% weekly use.

This prerequisite replaces untyped occupancy flags with bounded exact ownership. An action acknowledgment releases its adapter payload while its job remains pending. Ingress ownership remains until actual adapter disposition, including deferred completion; an old cleanup cannot release another transfer. No storage-handler support or protocol1.1 activation belongs to this increment.

The approved tests respect the real one-job-per-owner ceiling. A newer legacy job cannot run while an acknowledged action still retains its job. Strong accepted-old-action/new-storage-reply overlap is reserved for the later complete handler. Tests must use actual forwarded gates and adapter transfer evidence; no fake policy widening or production testing hooks.

Before delivery: compiling behavioral RED/GREEN, frozen source hashes and independent implementation review, full serial package checks, identical original/copy/frozen inputs, signed app build/link and normal verified restart. All use existing scratch/cache/derived data; preserve the60% weekly ceiling with verification headroom. Delivery evidence follows.


Frozen test evidence: five exact source/test files, eight new methods with14 expanded cases. Compiling behavioral RED demonstrated retained adapter payload after accepted action acknowledgment; the existing composition acknowledgment assertion was deliberately updated to the corrected receipt behavior. No numeric quota baseline was reduced. Final focused suite passes93 tests/six suites; full serial package passes740 tests / 75 suites (483 runtime,22 SDK,170 transport,61 contracts,four tools). All390 original/copy/frozen inputs match. Independent implementation review and signed delivery completed below.

The complete process formula preserves16KiB process, configured envelope,32KiB ingress preparation and80KiB delivery, adding max(512,4×ProcessCreditState.stride). The current platform adds512 bytes; direct/indirect8KiB-ingress cases both grow139,776 bytes. The temporary concern about omitted legacy terms was disproved by source inspection: they remained at the callers before being factored into the shared formula. No112KiB refund defect occurred.


## Delivered evidence

All five frozen files were independently approved with no actionable findings. Full serial package: **740 tests / 75 suites**. All **390** original/copy/frozen input files match before/after build and **44** accumulated approved source/test hashes match. Signed development build, strict/deep verification and Applications link update succeeded. Normal restart verified **PID 6324 → 8362**, stable after two seconds, no forced termination. Weekly use at delivery: **53%**.

Exact artifacts use `/private/tmp/cascade-runtime-slot-ownership-`: `report.md`, `hashes.json`, `preimage/`, `frozen/`, `implementation-review.md`, `actual-red.log`, `final-green.log`, `full-tests.log`, `build-inputs.json`, `reviewed-inputs.json`, `app-build.log`, `restart.json`. Patch: `/private/tmp/cascade-runtime-slot-ownership.diff`. Existing scratch/module cache/derived data only. C7b1 complete authenticated host-handler implementation was dispatched separately after this delivery; no native transport or protocol enablement follows from b0 alone.
