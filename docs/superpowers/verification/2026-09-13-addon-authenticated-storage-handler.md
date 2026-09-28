# Authenticated host storage request and reply

Status: delivered after corrected frozen review, complete serial tests, signed build and verified normal restart. [Approved plan](../plans/2026-09-13-addon-authenticated-storage-handler.md).

Baseline: 740 serial tests / 75 suites, 390 inputs, 44 approved hashes, signed build and normal restart to PID 8362 at 53% weekly use. The delivered slice preserves canonical permission/profile, a weak coordinator binding with strong accepted-operation ownership, a protected 8 MiB value/codec scope and a 256 KiB retained reply credit through exact receipt. Known backend outcomes remain distinct from reply suppression.

The initial full run passed 765 tests / 76 suites, but review identified that a disabled-host fixture masked the canonical-peer-profile check. Pre-review artifacts were preserved before replacing the final evidence below. Only the test/fixture changed; a compiling mutation test then proved the corrected regression was sensitive to the authority bypass.

## Final delivery

Independent rereview approved all eight final files after correcting the sole P2 test gap. The enabled-host 1.1 / canonical-peer 1.0 regression genuinely stages bytes. A one-line supplied-profile mutant compiled and failed on forbidden ingress take; later canonical decoding still prevented mutation. Production bytes were restored exactly. Final focused verification passed 50 tests / 4 suites; the earlier broader run passed 176 / 11 before that test-only correction.

The final complete serial suite passed **765 tests / 76 suites** (508 Runtime, 22 SDK/presentation, 170 transport/kit, 61 Contracts, 4 Tool). All **391 build/test inputs** matched original, normalized integration copy and frozen snapshot before and after the signed app build; **45 reviewed source/test hashes** matched the delivered union. Build succeeded, `/Applications/Cascade.app` was updated and normal restart verified **PID 8362 → 11511**, without forced termination. Last weekly reading: **55%**, below the requested 60% ceiling.

Artifacts share `/private/tmp/cascade-keyed-storage-handler`: `-report.md`, `-implementation-review.md`, `-hashes.json`, `.diff`, `-fix1-mutant-red.log`, `-fix1-green.log`, `-full-tests.log`, `-build-inputs.json`, `-reviewed-inputs.json`, `-app-build.log`, `-restart.json`. Initial pre-review evidence remains under `-pre-review/`.

The internal host path enforces canonical authority and declared/granted storage permission, shares exact ingress/delivery credits with other traffic, protects its 8 MiB value/codec workspace and preserves known mutation outcomes even when reply delivery is suppressed. Enabled replies use a prepaid 256 KiB slot; default delivery remains 80 KiB. Final inline control is 640 bytes per process on the tested ABI, replacing C7b0's 512-byte quote without removing any existing payload term. The weak coordinator binding avoids the shutdown ownership cycle; accepted operations retain their coordinator locally.

No native transport conformer, operational SDK storage client or application lifecycle driver is delivered by this increment.
