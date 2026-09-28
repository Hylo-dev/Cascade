# C0d: offline diagnostics approved, native execution suspended

The observer and the D0–D3 diagnostic sequence for studying the worker's exit
after the death of the supervisor are implemented and reviewed. **The real test was
not run and is not authorized by the current driver.** The script always ends
with code 78 before creating products, compiling, signing or launching participants.
There is no option or variable to bypass the block. Removing it requires a
separately reviewed project and source change.

## Behavior implemented and verified offline

A single loop observes process output and notifications, preserving identity, status,
order and limits. The stop request is not equivalent to the observed exit. The PID
of the direct supervisor stays reserved before the fallback and the final wait. Missing
outcomes, unusable queues and the absence of the status stay unknown.
The four cases stop at the first incomplete or negative result, with no retry.

The first review found F01/P2: a rejection of the proc registration caused
already available stdout to be lost. The first fix round keeps the bounded
drain, without retrying the registration, registering late PIDs or releasing a
launch permission. A causal test reproduces the loss before the fix.
G01, the operational block of the script, is a separate later requirement. Its
RED used only a fake mktemp that records and exits: no real setup.

Final verification after the fix, with separate commands and exit 0:

- 35 ManagedDeathEvidenceTests tests, on the real observer/reducer with simulated endpoints.
- 54 historical Tracing tests and 26 OwnerBootstrapEvidenceTests unchanged.
- zsh syntax and Python parsing valid. The already protected driver was invoked and
  returned 78 as expected; the native body stayed unexecuted.

Re-review: spec PASS, quality APPROVED, F01 closed, G01 compliant, zero new findings.
Six source hashes verified against exact preimages; no change outside scope.
The initial logs and reports stay distinct from the fix ones. Final logs in the
working folder `continuation-managed-death`: `C0d-fix1-death-green.log`,
`C0d-fix1-historical-green.log`, `C0d-fix1-owner-green.log`.

## Why the native gate stays closed

The intentional D2/D3 injections would happen after confirmed tracing. However, an
early death of the supervisor, even during cleanup, can precede the Stub's call
to PT_TRACE_ME. A signal to the group does not prove an atomic order between the two
processes. In the public XNU source that branch uses the current parent and can reach
the protection-changing logic for that parent too; after reparenting,
it is not demonstrated that it is still a process of the test. The policy checks can
reject the operation, but the outcome on the installed beta is not known. No launchd
change was observed or provoked. [XNU ptrace](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/mach_process.c),
[XNU code signing](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_cs.c).

For this reason we deliberately do not run tracing after the loss of the parent and
do not treat the before/after getppid check as an atomic constraint. The C0e E2
proposal was withdrawn. No new privilege exception, GUI change or
implicit risk acceptance was introduced. The native C0o results already
observed with a live parent stay historical and are not rewritten.

## Delivery and limits

Six diagnostic files and three documents integrated, with 400 non-documentation inputs
identical between the original and the local copy (prototypes included). The 337 inputs
already used for the C5b build are unchanged: no change to the app code and no new
compilation needed. The deep/strict signature is reconfirmed with outcome 0; the same
confined check had returned CSSMERR_TP_NOT_TRUSTED, with no changes to the
keychain. The Applications link is that of the signed C5b build. Relaunch
verified: PID 51942 closed without forcing, new stable instance PID 53808 in the
expected path. Record `/private/tmp/cascade-c0d-offline-20260912-restart.json`.
The 474 Swift tests of the previous delivery are not presented as C0d evidence.

Native C0d compilations: 0. Native C0d participants: 0. Exit of the stopped/running
tracee, NOTE_EXITSTATUS authorization and compilation of the new C branches remain
unmeasured. Production launcher, distributed template, host death and launch
races remain unqualified; overall VM protections unknown. C5c can advance
on image resources without opening this gate or duplicating the runtime.
