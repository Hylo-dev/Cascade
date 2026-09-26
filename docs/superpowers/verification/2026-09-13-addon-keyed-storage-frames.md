# Dedicated keyed-storage frames

Status: implemented, independently reviewed and delivered under the [C6 plan](../plans/2026-09-13-addon-keyed-storage-frames.md).

Foundation JSONEncoder/JSONDecoder implement closed semantic request/response shapes. Exact UTF-8 keys, full 65,536-byte values and bounded failures fit a 196,608-byte encoded frame, including slash/control escaping. Correlation checks require matching UUID and operation; they do not authenticate a caller or prove freshness. Direct Codable remains distinct from the codec's raw-bound/profile gates.

Protocol negotiation supports an explicit host opt-in to minor 1.1. Every existing operational caller retains its default 1.0 behavior; no authenticated storage handler, SDK native transport or application event driver is claimed.

Independent review approved all six exact source/test hashes with no introduced blockers. Actual compiling behavioral RED and **51 focused/adjacent tests in six suites**, including **13 new tests**, were reviewed. Full serial package verification passed **723 tests in 73 suites**: 466 runtime, 22 SDK, 170 transport, 61 contracts and four tools. All **388** frozen build/test inputs match the original workspace and normalized build copy; **40** accumulated approved source/test hashes match.

Signed development build, strict/deep signature verification and `/Applications/Cascade.app` link update succeeded. Normal restart verified **PID 2818 → 4658**, stable after two seconds, without forced termination. Weekly allowance at delivery: **48%**.

Canonical artifacts use `/private/tmp/cascade-keyed-storage-frames-`: `report.md`, `diff`, `hashes.json`, `preimage/`, `frozen/`, `final-green.log`, `full-tests.log`, `build-inputs.json`, `reviewed-inputs.json`, `app-build.log` and `restart.json`. The original RED log is `/private/tmp/cascade-keyed-storage-c6-red.log`. Only the existing shared scratch, module cache and Xcode derived data were used.

The codec owns no governor reservation. Its caller must cover raw input, decoded values, parser workspace and encoded output until actual release/handoff; value maxima are not a Foundation heap qualification. The future total transport envelope still has its own 512-KiB limit. The next concrete coordinator outcome slice is independently preflighted and dispatched separately.
