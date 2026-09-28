# SwiftData archive feasibility probe

Run from the repository root:

```sh
scripts/test-addon-swiftdata-archive.sh
```

The script compiles one standalone Swift executable with deployment target macOS 14.0, then runs eleven fixed stages as separate processes. It uses the selected `DEVELOPER_DIR` (default `/Applications/Xcode-beta.app/Contents/Developer`) and the existing `/private/tmp/cascade-plugin-module-cache`; it creates no SwiftPM build cache. Native Swift macro execution must be permitted by the calling environment. Only no arguments or `--help` are accepted.

Each invocation creates its own `/private/tmp/cascade-swiftdata-archive-XXXXXX` directory and retains its executable, compiler/OS/SDK records, stage JSON, stderr logs and final `report.json`. The artifact directory is printed to stderr; stdout contains the compact final JSON report. No existing store is reused or deleted, and no provider, addon launcher, app bundle or native C0 gate is exercised. Compile/setup failures leave an incomplete report; stage failures return nonzero and preserve diagnostics. Each subprocess has a fixed timeout (30 seconds, or 90 seconds for the 100-save stage).

The two store roots are created with mode `0700`; each empty database is exclusively precreated with mode `0600` and no symlink following. The executable checks root/database ownership and modes, then checks the actual database, WAL and SHM files are private regular files with a single link. These checks are fixture hygiene inside a fresh trusted temporary root, not qualification of production descriptor-relative storage security.

The consistency fixture performs:

1. Save generation 1 with a 4 KiB publication BLOB and 1 MiB raster BLOB, then reopen in another process.
2. Change the generation and both BLOBs, explicitly roll back, then reopen and verify generation 1.
3. Explicitly save generation 3 with a 256 KiB publication BLOB and 4,000,000-byte raster BLOB, then reopen.
4. Change the generation and both BLOBs without saving while autosave is disabled, exit, and reopen to verify generation 3.

A separate retention fixture saves generation 1, performs exactly 100 replacements with fixed 4 KiB publication and 1 MiB raster payloads, then reopens in another process. Every observation verifies the expected generation, payload lengths and every byte in both BLOBs. Payload bytes are synthetic deterministic raster data; this probe exercises persistence rather than raster decoding. A single model row stores the generation and both plain `Data` properties, with no `.externalStorage` attribute. No save occurs between individual field changes.

The worker creates its container and independent context from a detached task and uses `DefaultSerialModelExecutor`. Both initialization and operations fail if they run on the main thread. Autosave is explicitly disabled and the undo manager is nil. The probe exposes no model objects across actor boundaries.

Each stage reports synchronous open/work/verification wall time, total subprocess wall time, current physical footprint and lifetime peak physical footprint from Darwin `proc_pid_rusage(RUSAGE_INFO_V4)`. The two timing measures have different boundaries: the subprocess measure includes executable startup and shutdown. Memory includes the whole probe process, loaded frameworks and validation work; it is neither archive-only allocation nor ResourceGovernor accounting. Measurements occur after the operation while the context/container remain alive; the kernel lifetime peak can include earlier transient work. There is no polling sampler.

File observations report logical lengths and modes while SwiftData is open and after process exit. The final read-only SQLite inspection reports BLOB column declarations and persistent-history row counts if those private table names exist. Those details are observations, not stable SwiftData API contracts or correctness requirements. The report records the actual OS/build, SDK and compiler. A successful macOS 14 deployment-target compilation on a newer OS is **not macOS 14 runtime qualification**; the report deliberately leaves that qualification false.

This probe establishes ordinary explicit save/reopen, rollback and unsaved-change behavior. It does not inject a save failure, interrupt a transaction mid-commit, prove physical power-loss durability, measure production archive serialization, or qualify a physical-memory/disk ceiling. SwiftData's internal caches, history and WAL are framework-controlled. Retained file lengths can exceed current BLOB lengths and can remain large after reopen; dropping a container does not provide an explicit close/checkpoint/truncate contract. Production admission must account for the actual managed files and state the framework's allocation boundary explicitly.

Primary API references: [ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext), [autosaveEnabled](https://developer.apple.com/documentation/swiftdata/modelcontext/autosaveenabled), [transaction(block:)](https://developer.apple.com/documentation/swiftdata/modelcontext/transaction(block:)), and [concurrency support](https://developer.apple.com/documentation/swiftdata/concurrencysupport).
