# Chunked asset transfer: messages and internal assembler

Status: implementation and review approved, final suite and signed build succeeded, relaunch of the updated version verified. [Plan](../plans/2026-09-14-addon-asset-chunks.md). Mechanism approved by the user in the [Wayfinder ticket](../../../.scratch/cascade-product/issues/21-asset-transfer.md).

## Delivery

Nine source/test files: seven new and two modified. Dedicated Foundation frames for begin/chunk/finish/abort and correlated responses, with an explicit syntactic profile. Chunks up to 65,536 bytes, compressed input up to 1,048,576 bytes and JSON frames up to 196,608 bytes, checked before parsing. The existing semantic validators are reused. No new dependency or alternative implementation of an image codec.

The internal assembler keeps a single reception per instance, with the exact identity of incarnation, connection, publication and assignment. It reserves `2 * totalBytes + 4096` bytes of temporary memory, plus the 1,024 bytes of the existing governor's entry, before the fixed-size buffer. Non-renewable monotonic expiry of 30 seconds, exact order and length of the chunks, exclusive cleanup. The ImageIO decoder and the rasters keep their own independent quotas; revocation or cancellation does not refund memory still used by the decoder.

## Final verification

- **795 serial tests / 80 suites**, including **14 new methods**; final targeted group **36 tests / 5 suites**.
- **400 inputs** for app/tests identical between the original, the normalized copy and the frozen snapshot; **55 paths** in the cumulative manifest of the reviewed sources/tests verified. Pre-existing checkout preserved, without commit or staging.
- Initial compiling RED: two behavioral assertions on the quotas and on the protection from releaseAll. Separate mutants after the implementation: three tests failed with 16 findings for authority, order and premature refund; restoration documented. They are not presented as a RED preceding the implementation of the assembler.
- Independent review: one race found and fixed. Invalid append/finish now move to the disposal state under the same lock as the validation; the checks for foreign authority and occupancy remain non-mutating. New deterministic test with the governor's refund suspended; it verifies the final invariant, without claiming to deterministically reproduce the earlier window between locks. Final review approved, no remaining findings.
- A separate test assembles and decodes through ImageIO a real PNG over multiple chunks, compares the pixels and verifies the lifetime of the raster. The exact 1 MiB / 16 chunk test verifies all the bytes through a controlled decoder that then forwards a valid PNG to the real decoder. No handwritten PNG/CRC parser.

The suite before the fix passed 794 tests / 80 suites. The earlier logs and snapshots are kept separately; the 795 / 80 result concerns the corrected and frozen code.

Local artifacts with the prefix `/private/tmp/cascade-asset-chunks-`: `report.md`, `review.md`, `hashes.json`, `build-inputs.json`, `reviewed-inputs.json`, `red.log`, `mutant-red.log`, `restoration.json`, `review-green.log`, `full-tests.log`, `app-build.log`, `restart.json`; preimages, diffs and frozen trees preserved. The compilation warnings about weak variables and the errors from the deliberately corrupted SwiftData fixtures are not new failures.

## Remaining boundary

This increment is an internal primitive: on its own it does not authenticate the assignment, does not negotiate the channel, does not reserve the transport adapter's workspace, does not publish a canonical alias and does not connect the SDK client. The runtime will have to call expiry and shutdown explicitly and integrate the shared inputs/responses. The transfer is not yet an operational path for external addons. The native launcher and the C0d gate remain separate and not qualified.

The user requires at least 35% of the weekly quota to remain available: ceiling at 65% used. Last official final reading: 15 September 2026, 10:12:01 UTC, main quota at 61% (39% available). The Spark counter is distinct and is not used for this limit.

Build through `scripts/build-development.sh` succeeded, signature verified with codesign deep/strict and `/Applications/Cascade.app` updated to the CascadeAddonDevelopment build. Launch verified: PID **28860**, the only active Cascade instance, persistent after launch. At the check before launch no instance of the build was found; the old PID 12667 was no longer present. No forced termination.

Final normal relaunch, at the end of the work: PID **28860 → 28937**, verified after two seconds; no forced termination. The file `restart.json` records this last step. Wayfinder realigned: 22 tickets, 4 resolved, 18 open, no dangling dependency on a nonexistent ticket and no cycle; 215 local links verified, plus 4 in the component-specific documents.
