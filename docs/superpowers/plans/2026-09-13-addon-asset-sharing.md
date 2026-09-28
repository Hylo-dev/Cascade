# Asset Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this approved continuation. Steps use checkbox syntax.

**Goal:** Reuse one immutable raster across multiple publications of the same verified addon within a compatible host privacy partition, with independent lifetime and a public SDK asset contract.

**Architecture:** Explicit sharing issues a fresh publication-scoped alias over the existing AssetRasterBacking. Existing pin authorization, end/expiry/release semantics and protected physical accounting remain canonical. Host publication assignments select an immutable asset privacy partition; provider payloads never choose partitions.

**Tech Stack:** Existing Swift 6 contracts/runtime, Foundation Codable, ImageIO/CoreGraphics and ResourceGovernor; macOS 14 deployment floor.

**Spec:** User approved cross-publication sharing on 2026-09-13 following the alternatives in the preceding turn; existing runtime spec at ../specs/2026-09-09-addon-runtime-design.md remains binding.

## Global Constraints

- Preserve dirty workspace, no bulk staging, commits or global resets.
- One backing, one pixel charge; each new scoped alias prepays existing 4096-byte import metadata.
- Share requires current exact source alias/scope and target host assignment, equal verified publisher/addon, digest, connection token and privacy partition. Feature/publication may differ only through this explicit transfer.
- Default partition is addon-owned self-produced data. Distinct host-isolated UUID partitions never share. These labels are host administration, not wire grants or a replacement for service/account authorization. Service-derived asset imports remain absent.
- ContentDocument.Privacy remains redaction metadata, never sharing authority.
- Ending/releasing either alias must leave other aliases/pins alive. Exit revokes connection aliases, not publication pins. No revival through retained pins or stale connections.
- Existing resource ceilings, atomic publication commit, cancellation/disable revalidation and deferred-completion drain remain mandatory. No decoder invocation for share.
- No native launcher execution or C0d gate changes. Build, update Applications, normal restart and verify before final response. Weekly usage must remain below60%.

## Task1 — AssetState shared backing

Files: Assets/AssetState.swift; new Assets/AssetPrivacyPartition.swift; Tests/AssetSharingTests.swift.

Produce `AssetPrivacyPartition: Hashable, Sendable` with `.addonOwned` and `.isolated(UUID)`; host-only, fixed-size. Add `Scope.privacyPartition` default `.addonOwned` via explicit initializer preserving call sites.

Produce `sharingAdmissionBytes(assetID:source:target:) throws -> Int` and `share(assetID:source:target:) throws -> AssetHandle`. Validate exact stored source, compatibility as above and target bounded scope before quoting. `share` revalidates and calls existing insert with the source backing; no retained proposal or pixel copy.

- [x] Write state cases before implementation and attempt RED with a compiling unavailable share stub. Packaging/disk failure blocked state execution; runtime sharing RED was observed independently, and all state cases passed in final verification.
- [x] Implement explicit shared aliases and verify distinct aliases/same CGImage identity and unchanged assetBytes.
- [x] Verify cross-feature/publication sharing, incompatible partition/owner/publisher/digest/token denial, exact source spoof denial, metadata capacity, released/stale source denial, end/expiry independence and last-consumer disposal.
- [x] Self-review and provide focused test log and scoped diff from saved preimages.

## Task2 — Runtime authority and suspension

Files: AddonRuntime.swift; Tests/AddonRuntimeAssetSharingTests.swift.

Add host-only `assetPrivacyPartition: AssetPrivacyPartition = .addonOwned` to assignPublication; keep partition immutable in Assignment and reject same instance re-assignment with a different partition. Propagate into assetScope.

Produce `shareAsset(assetID:from:to:connection:) async throws -> AssetState.AssetHandle`. Use existing admission and pending asset metadata protection. Resolve both currently live assignments before and after waits, quote before growth, drain deferred completions before final synchronous alias insertion, then return without post-insert suspension. Catch clears pending quote, shrinks and drains normally.

- [x] Reproduce missing sharing behavior with a real PNG and actual governor; then implement using Task1.
- [x] Verify same backing across widget/activity features, independent release/end, quota exactly once for pixels, cross-partition denial and immutable assignment partition.
- [x] Gate metadata admission for cancellation/disable/exit; no alias or metadata leak, old source stays valid when appropriate.
- [x] Review Task1 and runtime diff independently; fix concrete findings.

## Task3 — Public SDK contract

Files: Contracts/AssetHandle.swift, SDK/AddonAssetClient.swift, SDK/AddonContext.swift, associated contract/SDK tests.

Expose immutable validated `AssetHandle` metadata (assetID, owner, publicationID, rasterRevision, width, height, byteCount), using existing identifier/Codable validation patterns and exact RGBA8 count. A decoded handle is untrusted metadata, not permission. Runtime maps its host-issued values to this common type without widening authority.

Expose `AddonAssetClient` with async `importAsset(_:publicationID:)`, `shareAsset(_:to:)`, `releaseAsset(_:)`. Client instances are connection-bound like existing storage/services. Add assets to AddonContext using an explicit initializer; preserve the current initializer with an unavailable default capability if needed for source compatibility, failing with an existing failure code rather than pretending success. No transport implementation claimed.

- [x] Test metadata invalid dimensions/count/owner/ID/revision and valid Codable roundtrip; closed decoding like adjacent contracts.
- [x] Test SDK context dependency forwarding and unavailable legacy capability behavior.
- [x] Implement common contract and update runtime return alias; compile all current consumers.

## Task4 — Verification and delivery

- [x] Update assets/protocol docs and previous pending-choice wording with the user's decision and precise implemented boundary.
- [x] Independent final review of exact turn diff, then full serial package tests from frozen inputs.
- [x] Signed app build via project script, Applications link update, normal restart and verified new PID.
- [x] Record evidence and weekly allowance. Public native transport and hostile decoder isolation remain qualification requirements.

## Verification result

552 serial tests passed (16 new),356 frozen inputs matched, signed build and normal restart succeeded (PID73683). State RED attempts were blocked by signing/disk exhaustion; actual runtime/contract/SDK RED evidence and final fullsuite evidence are distinguished in the [report](../verification/2026-09-13-addon-asset-sharing.md). No source commits were made in the dirty checkout.
