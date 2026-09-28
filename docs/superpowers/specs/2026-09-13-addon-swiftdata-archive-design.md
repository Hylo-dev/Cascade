# SwiftData restart archive — selected direction and qualification

The user selected SwiftData on 2026-09-13 after comparing GRDB/SQLite and Foundation
snapshot files, then explicitly instructed implementation to proceed. This supersedes
the earlier GRDB recommendation. No further approval of the framework choice is needed.

## Accepted behavior

Use Apple's SwiftData, with the existing macOS 14 deployment floor, for a private
host archive. Model containers, contexts and mutable persistent models remain inside
the storage layer. Storage work runs independently of MainActor; immutable runtime
and presentation values remain separate from persistent models. Disable autosave,
undo and CloudKit integration; save explicitly on meaningful state changes.

One verified owner's committed generation must contain coherent canonical publication
records, original civil activity deadlines, terminal history and deduplicated raster
assets with their reference/partition metadata. Never restore notices or execute
commands. The host revalidates current owner/feature authority, creates fresh runtime
capabilities and preserves privacy boundaries before exposing any restored content.
The existing 64 KiB checkpoint and SDK keyed-preference formats remain unchanged.

The minimal archive representation being qualified is one SwiftData generation row
per owner, holding bounded immutable serialized values and ordinary Data BLOBs.
Foundation serialization can encode the bounded canonical values. No external binary
storage or custom SwiftData store belongs to this first direction. A shared BLOB
appears once within its owner/privacy partition; content equality does not authorize
cross-owner or cross-partition sharing.

## First implementation step: reproducible qualification

Before attaching the framework to the resource-governed runtime, preserve a standalone
native probe in `Prototypes/AddonPlatform/SwiftDataArchive` and a bounded script in
`scripts/test-addon-swiftdata-archive.sh`. This is experimental code, not a production
archive backend or a new provider launcher.

The probe uses macOS 14-compatible API and separate native processes to verify:

1. Explicit save and reopen preserve the same publication/raster generation.
2. Rollback preserves the previous pair.
3. With autosave disabled, unsaved changes disappear on reopen.
4. Repeated replacements expose retained DB/WAL/SHM growth independently of live payload.
5. Storage operations stay off MainActor, with reported timing and memory observations.
6. Private root and precreated database modes are retained by observed framework files.

Compile-floor compatibility and runtime qualification are separate results. The
available host runs macOS 27; a successful deployment-target-14 compile does not
qualify execution on macOS 14. Native addon C0d remains closed.

## Resource contract that must remain explicit

Bound and prepay application-controlled records, input/candidate copies, references,
decoded pixels and validation work using the existing ResourceGovernor. Inventory
all managed persistent files before startup admission; do not omit the database,
WAL, shared-memory file, history or failed-save growth. No other consumer's charge
may be released. Committed data is not silently deleted to make admission succeed.

SwiftData's default store controls its own object cache, SQLite pages, journal and
history. The macOS 14 API does not provide a held-file-descriptor open, cache/page
ceiling, guaranteed checkpoint/truncate, explicit nondestructive close or history
pruning. A multiplier applied to the latest payload is not proof of a bound on
those resources. The probe therefore measures them separately; it must not report
logical payload limits as an enforced bound on framework file growth or RSS.

The user explicitly approved the observed-pressure policy after reviewing the probe:
measure framework-managed files after operations, retain any owner/global overage
as debt, and block subsequent writes until measured usage permits them. This approval
is specific to internal SwiftData files; application-controlled payloads and memory
remain strictly admitted. See the [approved policy](../plans/2026-09-13-addon-swiftdata-disk-policy-decision.md)
and [implementation plan](../plans/2026-09-13-addon-swiftdata-storage.md). The deployment
floor remains unchanged; no bounded overshoot or framework RSS guarantee is claimed.

## Sources and existing boundaries

- [Apple ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)
- [Apple concurrency support](https://developer.apple.com/documentation/swiftdata/concurrencysupport)
- [Apple autosave control](https://developer.apple.com/documentation/swiftdata/modelcontext/autosaveenabled)
- [C5 design](2026-09-09-addon-runtime-design.md), especially resource control and persistence.
- [Storage contracts](../../addons/storage.md) and [asset contracts](../../addons/assets.md).
- [Canonical restoration draft](../plans/2026-09-13-addon-publication-restoration.md).

Installed SDK signatures and real probe output supply API-floor and runtime evidence;
documentation alone does not establish performance, power-loss durability or quota safety.
