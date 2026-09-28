# Review of the host options after the VM: 26 September 2026

Research only: no new addon/helper/fixture-root process, signal,
suspension, privilege or app change. The pause requested by the user is
respected. The policy against orphaned managed processes and the gate stay unchanged.

The next candidate probe is **administrative recovery of a normally launched
provider**, authenticated, with its guard already active, root and broker alive. It does
not appear to have been run already in the evidence consulted; the SIGCONT planned by the
VM runner was never reached. The command to evaluate in the next execution design is:

```text
launchctl kill SIGKILL pid/<authenticated-broker>/<exact-fixture-job>
```

It is not a command to run now. No sudo on the host is implied. The public
manual describes sending the signal to the running service. Any PASS
would require the SIGKILL exit of the precise instance already registered in kqueue,
before the guards, without concurrent launch requests or a new incarnation.
Denial, timeout or intervention of the cleanup remain FAIL/inconclusive. The ordinary
recovery through root already measured would be separate from the result.
[Local launchctl manual](</usr/share/man/man1/launchctl.1>),
[external identity probes](</Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/docs/superpowers/verification/2026-09-25-addon-external-identity.md>).

**Service does not mean incarnation.** The command addresses the current service,
not an audit token. Moreover, `pid/<pid>` resolves the domain through a PID number:
the retained connection to the broker and before/after checks do not atomically prevent
its reuse. This addressing must be reviewed before execution;
a PASS with the domain alive does not qualify recovery after the death of broker/root.
Parsing `launchctl print` remains diagnostic, not production API.
[Local launchctl manual](</usr/share/man/man1/launchctl.1>).

**No automatic move to SIGSTOP/SIGCONT or START_SUSPENDED.** A process
stopped after HELLO has already run code. An active SIGALRM guard can stay
pending while the process is stopped: it is not an independent recovery. XNU 14 uses
`task_suspend_internal` both in the signal stop and in the suspended spawn, but that
does not make the point in time or the measured counters equivalent on every OS.
SIGKILL has a specific path; its success on an ordinary process is not
already proof about the provider stopped before its first instruction.
[XNU signals](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_sig.c#L2155),
[XNU suspended spawn](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L1862).

A separate calibration could create a tiny ordinary direct child
with `POSIX_SPAWN_START_SUSPENDED`, acquire task-name port/token/signature without HELLO,
then terminate it and compare kqueue with wait. The live controller, the only reaper,
with default SIGCHLD and without SA_NOCLDWAIT keeps the PID of its own child
until the reap; `WNOWAIT` does not consume it. This is different from a discovered PID. But the
death of the controller loses that premise: **it does not resolve the EF lifetime and does
not offer the containment of the VM**. I do not propose it as the next experiment nor
as a new probe needed to unblock the product.
[Apple spawn](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_setflags.3.html),
[Apple DTS and compatibility limits](https://developer.apple.com/forums/thread/842442),
[XNU reap/WNOWAIT](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exit.c#L2562).

No architectural choice is needed for this research or for designing the ordinary
probe. Adopting direct children in place of EF, or launchctl as production
control, would instead be a new choice, with packaging, privilege
and lifetime problems still to be solved. The already failed invalidate,
guards/EOF after main, or an exception for orphans already refused are not proposed again.
[Spawn analysis already concluded](</Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/docs/wayfinder/research/2026-09-24-spawn-managed-lifetime.md>).
