# SwiftData managed-disk admission — approved

The user explicitly approved the observed-growth policy below after the qualification report (reply: “si”). SwiftData was selected by the user. The selected framework and macOS 14 floor are
not being reconsidered automatically. A native qualification probe verified the
save/reopen, rollback and explicit-save behavior, but exposed a separate admission
contract that the production integration cannot silently change.

## Current contract

[Storage accounting](../../addons/storage.md) charges managed logical file lengths,
including staging and directory/file allowances. This excludes APFS allocation
details, not SQLite WAL, shared-memory or history bytes. Old data and the full
candidate are admitted before controlled writes. The common governor rejects
overbudget growth and has no retained-debt reconciliation operation.

SwiftData's macOS 14 default-store API does not establish a maximum generated-file
growth for a save, nor a guaranteed checkpoint/truncate/close or history-prune path.
An allowance estimated from current payload followed by a size check is therefore
not equivalent to the existing contract. Rollback or process exit is not evidence
that generated files were removed. Native RSS observation already has qualifications
in the project and is not the new decision here.

The packaged probe observed a 1 MiB raster plus a 4 KiB document represented by
5.49 MiB of DB/WAL/SHM **while the store remained open** after 100 replacements.
After normal process exit and subsequent reopen its WAL was zero, leaving 1.28 MiB
and 101 retained history rows. An earlier disposable probe left a nonzero WAL;
that behavior was not reproduced by the reviewed package. Neither observation is
a lifecycle API guarantee. These are measured results on the available OS, not
a universal ratio or a demonstrated worst case.
The reproducible probe and final measured report are the evidence for review.

## Approved policy

Keep strict admission for application-controlled payloads, reference tables,
candidate buffers and raster allocations. Treat SwiftData-generated disk growth as
observed managed storage with these additional semantics:

1. Before opening the archive, inventory and charge every retained managed file,
   including DB/WAL/SHM;
   preserve existing owner and global ceilings through explicit conservative attribution.
2. Before container creation, open/recovery or saving, reserve the applicable
   old/candidate application data and a documented framework workspace allowance.
   This allowance is an estimate, not a hard backend limit.
3. After every successful or failed open/recovery or save, reconcile measured lengths
   of all managed files before exposing capabilities or returning normal results. The
   governor must be extended to record real overbudget debt without declaring it free.
4. If measured storage exceeds admission, stop further persistent writes, retain
   the archive and its charge, and report the state explicitly. A save already
   committed cannot be claimed rolled back merely because the size check failed.
5. Recovery must preserve data unless deletion is explicitly authorized. Never
   independently delete live SQLite sidecars or reset the store silently. Any store
   rebuild must occur through a separately verified closed-store lifecycle.

This policy accepts that internal files may exceed the intended quota before the
host observes the result. It does not promise a bounded overshoot. The user subsequently approved this policy explicitly; implementation is now authorized. The approval applies only to framework-generated files.

## Current disposition

The observed-growth policy is approved. Implement protected measured-disk reservations,
post-operation accounting including overbudget debt, and denial of subsequent writes
while owner/global ceilings are exceeded. Preserve strict preadmission for application
payloads and memory, existing checkpoint/keyed behavior, committed archive contents,
and the macOS 14 floor. No further confirmation of this policy is required.
