# Spawn-time lifetime ownership: public API qualification

**Verdict: no candidate in the reviewed spawn/exec/fork family qualifies Cascade's complete managed-process contract. Keep C0d's unconditional exit 78 and the native launcher blocked.** This is a bounded rejection of specific mechanisms, not a proof that no macOS architecture can satisfy the requirement.

Research performed on 24 September 2026 against Apple documentation, Apple-published XNU source and the locally selected public SDK. This report adds a spawn-time API and implementation review to the [18 September investigation](../../../.scratch/codex-addon/20260918-continuation/managed-process-design.md) and the [23 September launchd investigation](2026-09-23-launchd-managed-lifetime.md). The accepted requirement remains actual managed-process exit after either host or supervisor loss, starting at creation and continuing through arbitrary addon code, with Hardened Runtime and App Sandbox unchanged.

No native probe, fixture, build, tracing operation, signal experiment, registration, entitlement change or existing-file edit was performed. Reading SDK metadata and headers is not a qualification run. The only written artifact is this report; the root task owns app restart.

## Evidence versions and limits

- The selected SDK, reported by `xcrun --show-sdk-path`, was `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`; its `SDKSettings.json` identifies macOS 27.0. This establishes the installed declaration surface, not execution behavior on macOS 14.
- For the deployment baseline, Apple's [macOS 14.0 release manifest](https://raw.githubusercontent.com/apple-oss-distributions/distribution-macOS/macos-140/release.json) associates that release with **`xnu-10002.1.13`**. The spawn flags, exec path and parent-exit path below are pinned to that release tag. A published source release does not include every closed security-policy implementation and does not substitute for signed distribution testing.
- Fork corroboration is pinned separately to **`xnu-12377.1.9`**. Fetching the macOS 14 fork file failed through the available web channel; this report does not claim to have inspected that baseline file. The newer source is explicitly supplementary.
- The archived Apple manual is dated August 2007. It provides the documented meaning of the Apple spawn extensions; it is not evidence of current App Sandbox authorization for every combination.

## Public SDK inventory

These are exact local header locations and line numbers from the selected SDK:

| Surface | Observed declaration | Consequence |
| --- | --- | --- |
| [`sys/spawn.h:45`](</Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/spawn.h:45>)–62 | Identity reset, process-group, default-signal, signal-mask, `SETEXEC`, `START_SUSPENDED`, session and close-on-exec flags. | No public flag here requests an atomic tracing relationship or death coupling to an identified host/supervisor. |
| [`spawn.h:91`](</Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/spawn.h:91>)–115 | Attribute lifecycle and flag/group/signal setters, available since macOS 10.5. | No public expected-parent, parent-death-signal or kill-on-owner-death setter is declared. |
| [`spawn.h:141`](</Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/spawn.h:141>)–171 | Architecture preference, audit-session port, exception ports, special ports and CPU mitigation setters. | These declarations do not expose a process lifetime-owner contract. Passing a port must not be interpreted as automatic child termination when a peer disappears. |
| [`sys/spawn.h:66`](</Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/sys/spawn.h:66>)–75 | Process-control constants describe resource-starvation responses, including `PCONTROL_KILL`. | The trigger is resource starvation, not owner death. The corresponding setter is absent from the public `spawn.h` inspected here. |

The SHA-256 hashes of the inspected files are `2d90f16beec60b2080553613234f004b58f384003feaa5eb809fe5e91b42b884` (`spawn.h`) and `988afa3a6d7a1ce18df118d234240c02eff0715b5712784ac28b44e7f66254dc` (`sys/spawn.h`). The baseline [XNU spawn flags](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/sys/spawn.h#L42-L82) expose the same relevant extensions and distinguish several other flags with `PRIVATE` guards.

This is a finite inventory of these two public headers, not a claim that every macOS framework has been exhaustively searched.

## START_SUSPENDED plus later parent attach

Apple documents `START_SUSPENDED` as stopping the new task before user-space execution. The benefit is real: it closes the interval in which addon initializers could run before a debugger manipulates the child. `SETEXEC`, separately, changes the operation into image replacement. Neither documented extension promises termination upon parent death. [Apple spawn flags manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_setflags.3.html).

In baseline XNU, the suspended-start branch changes the process state to `SSTOP` and calls `task_suspend_internal`; it does not establish tracing there. The same file bypasses new-process creation for `SETEXEC`. Later, `proc_exec_switch_task` explicitly transfers the existing tracing state during image replacement; that is not a new-child tracing attribute. [XNU `kern_exec.c`, suspension, spawn selection and exec switch](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L1863-L1874), [spawn selection](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L3449-L3457), [tracing-state transfer](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L4501-L4509).

The relevant parent-exit path distinguishes already-traced children from other children. It requests `SIGKILL` for the former and reparents the latter to `initproc`; the branch does not promote an ordinary suspended child into the traced case. This establishes a source-level counterexample to equating suspended creation with death ownership. It is not a newly observed orphan or a latency guarantee. [XNU `kern_exit.c`](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exit.c#L2151-L2232).

The failing sequence is therefore: create a suspended, untraced child; let spawn finish; lose its only intended supervisor before attach. The child has not executed addon code, but no reviewed contract causes actual exit. Adding an observer that remains alive changes the failure assumption and needs its own lifetime proof. A suspended bootstrap also cannot run an EOF handler. This inference is enough to reject this composition without executing a dangerous reproduction.

The existing review's separate attach-permission, tracing side-effect and stop-handling questions remain unresolved. Suspension supplies no evidence that debugger authorization or Hardened Runtime restrictions are bypassed; this report grants no permission to alter either security profile or to retry child-side `PT_TRACE_ME`.

## SETEXEC and a previously traced template

`SETEXEC` can preserve a relationship that was established safely before image replacement; it does not explain how the original managed process acquired that relationship from creation. Thus a bootstrap followed by `SETEXEC` merely moves the unresolved interval earlier. Having Cascade replace itself with an addon also removes Cascade as the continuing host and is outside the product architecture. These are architectural inferences from the documented image-replacement behavior, not new platform experiments.

A different suggestion is to trace one trusted template and fork workers from it. In the supplementary pinned source, `forkproc` allocates zeroed process state, copies `p_forkcopy` and selected flags, and explicitly carries `P_LREGISTER`; it does not copy `P_LTRACED`. The matching structure places `p_lflag` outside `p_forkcopy`. This is evidence against automatic inheritance of the template's ptrace relationship, not a macOS 14 runtime result. [XNU `kern_fork.c`](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.1.9/bsd/kern/kern_fork.c#L885-L983), [local-flag copy](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.1.9/bsd/kern/kern_fork.c#L1095-L1100), [matching process structure](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.1.9/bsd/sys/proc_internal.h#L301-L381).

The same fork implementation has a narrow cleanup when the parent dies during fork and leaves an inconsistent VM map. That check covers that construction failure; it is not a durable parent-death setting after a successful fork. Treating it as coverage of later death would exceed the code. [XNU fork construction cleanup](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.1.9/bsd/kern/kern_fork.c#L580-L589).

Consequently, neither fork inheritance nor exec-state transfer supplies the missing supported, atomic lifetime edge.

## Private interfaces are not qualifying candidates

Apple's published [`spawn_private.h`](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/spawn/spawn_private.h) declares process-control, importance-watch-port and coalition setters outside the public header inspected above. A macOS availability annotation on a private declaration does not make it a supported public API. The corresponding [`spawn_internal.h`](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/sys/spawn_internal.h) describes opaque attribute internals, including resource, port and coalition metadata. Directly constructing those internals would not supply a public contract either. These two references are moving `main` snapshots, used only to classify apparent leads, not to qualify deployed behavior.

The baseline coalition-spawn path also checks privileged coalition membership or a specific entitlement before assigning a child to another coalition. This supports retaining the public-API boundary; it does not demonstrate host-death coupling. [XNU coalition selection](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L3457-L3490).

## Decision and next admission condition

The new evidence narrows the search: suspension is execution ordering, exec transfer preserves an existing relationship, and the inspected fork path does not manufacture the required tracing relationship. No finite native qualification candidate emerges from combining these mechanisms under the unchanged requirements.

Keep the launcher and its dependent native transport admission blocked. Reopen this family only with a concrete **public** mechanism whose documented or reviewable semantics bind an identified managed process to host/supervisor lifetime at creation, plus a plan to verify actual exit under the existing profiles on macOS 14 and subsequent supported releases. Authenticated messages, in-process models and successful non-death tests cannot substitute for that missing lifetime mechanism. The C0d gate was neither edited nor executed by this investigation.
