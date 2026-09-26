# launchd-managed lifetime: qualification of the remaining lead

**Verdict: blocked.** The reviewed public `launchd`/`SMAppService` contracts do not establish the lifetime guarantee Cascade still needs: actual exit, beginning at process creation, after either the Cascade host or its supervisor dies, for an arbitrary worker that may attempt to escape its process group. The launcher decision therefore remains unchanged.

This report closes only the `launchd` lead left open by the [18 September investigation](../../../.scratch/codex-addon/20260918-continuation/managed-process-design.md). Sources were checked on 23 September 2026. No job was installed or registered, no process or signal experiment ran, and no entitlement, native launcher, gate, or product code changed.

## Direct answers

| Question | Answer | Basis |
| --- | --- | --- |
| Does process-group cleanup cover the direct job before its `main` runs? | **The historical source makes that plausible for the direct launchd job, but it is not a current-platform guarantee of exit.** Apple’s published launchd source establishes the child’s process group before `exec`, and its death path later signals the job’s remaining process group. The published source is old and cannot qualify current closed launchd behavior. | Source-level corroboration only. |
| Does cleanup run when the Cascade host or a separate supervisor dies? | **No supported contract says so.** The documented trigger is the launchd job’s own death. `SMAppService` registration deliberately persists an agent across later logins and a daemon across later boots; host death is not an unregister operation. | Current public API and current SDK contract. |
| Can arbitrary worker code leave the protected group? | **The documented process APIs permit it in ordinary eligible cases.** A non-group-leader child can create a new session and process group with `setsid`; `setpgid` can also change a process’s group subject to its documented session and timing rules. The launchd manual advises managed jobs not to call `setsid`; it does not document enforcement that prevents a descendant from doing so. | Public syscall contract plus source-level counterexample candidate; no target-OS bypass was experimentally claimed. |
| Does the group action prove actual exit? | **No.** The historical death path issues `SIGTERM` to the matching process group. It does not supply Cascade an identity-bound exit receipt, and that path does not show escalation of an uncooperative descendant to group-wide `SIGKILL`. | Historical source, not current-platform qualification. |
| Does ServiceManagement expose a supported non-escapable job/coalition lifetime owner? | **No documented public facility was found.** `SMAppService` registers, unregisters, and reports status for launchd jobs. The current SDK has no public coalition-management API that binds all descendants to the registering host’s death. | Current SDK/API surface. |

## What the current supported surface establishes

The current Xcode beta SDK’s [`SMAppService.h`](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ServiceManagement.framework/Headers/SMAppService.h>) is unusually clear about service duration:

- a registered LaunchAgent is bootstrapped immediately and again at subsequent logins;
- an approved LaunchDaemon is bootstrapped at subsequent boots;
- a login-item helper may be relaunched after a crash or nonzero exit;
- unregistering is the explicit operation that prevents future launches and kills a running agent or daemon; the synchronous API does not wait for reaping, while the asynchronous completion follows the kill operation.

Apple’s current [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice), [`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register()), and [`unregister(completionHandler:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/unregister(completionhandler:)) documentation expose the same registration model. Nothing in that contract makes registration contingent on the continued life of the app that performed it or on an XPC connection to that app. Therefore a host crash cannot be treated as an implicit, identity-bound unregister. This is an inference from the documented persistence and explicit unregister model; Apple does not publish a separate sentence promising behavior for every host-crash interleaving.

The platform prerequisites also make this an installed persistent-service architecture, rather than a transparent child-process primitive. Apps using `SMAppService` must be code signed. LaunchDaemons embedded this way must be notarized, require administrator approval, and should reside in an application bundle available before login, normally under `/Applications`. LaunchAgents require user-context registration and user consent. Changed agent/daemon plists or executables require re-registration. These requirements are relevant to distribution, but satisfying them would not add host-death coupling.

The installed macOS 27.0 build 26A5425a `launchd.plist(5)` manual says that, unless `AbandonProcessGroup` is enabled, launchd kills remaining processes with the **same process-group ID as the job when that job dies**. It also lists `setsid(2)` among startup operations a launchd-managed executable should not perform. This is current platform text observed locally. Its boundary matters: same PGID is narrower than arbitrary descendants, and job death is different from death of the app that registered the job or of a supervisor living inside it.

## What Apple’s published source does and does not prove

Apple’s public [launchd manual source](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5) is dated 2009. It is useful for understanding the mechanism, but it is not a source match for macOS 27.

In Apple’s published [`core.c`](https://github.com/apple-oss-distributions/launchd/blob/main/src/core.c#L3440-L3451), launchd reacts **after the job is dead** and, when process-group abandonment is disabled, invokes the group-directed termination path for the job PID as PGID. In the same published source, [`job_start_child`](https://github.com/apple-oss-distributions/launchd/blob/main/src/core.c#L4938-L4950) establishes a process group or session before executing the program. Together these support a narrow claim: that historical implementation can establish the direct job’s group before its image reaches `main`, and later requests termination of remaining members after direct-job death.

They do not prove the required property:

1. The trigger remains the launchd job’s death. If the job is the persistent supervisor, Cascade host death does not trigger this path. If the job is the worker, group cleanup begins only after that worker is already dead and cannot be its lifetime owner.
2. The published group cleanup sends `SIGTERM`. A signal request is not an observed exit, and this source path does not demonstrate group-wide escalation for a process that ignores or cannot service that signal.
3. The protected set is membership in one PGID at cleanup time. It is not a non-escapable descendant set.
4. The public repository is historical. It can rule out assumptions about what this implementation guaranteed; it cannot certify exact behavior of the current operating system.

The group-escape issue follows from Apple’s documented process model. [`setsid(2)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setsid.2.html) creates a new session and new process group when the caller is eligible. [`setpgid(2)`](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setpgid.2.html) permits process-group changes within the documented same-session and exec timing constraints. Current [Apple XNU source](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_prot.c) implements `setsid` with the group-leader/existing-group checks before entering a new group; it does not turn launchd ancestry into an unescapable group membership contract. This is a source-backed counterexample candidate for arbitrary code, not a claim that a particular sandboxed binary was observed escaping on macOS 27.

Coalitions do not close the gap through a supported product API. Apple’s public [XNU coalition implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/coalition.c) exposes kernel internals and privileged management concepts, but ServiceManagement and the current public macOS SDK expose no supported operation by which Cascade can create a non-escapable coalition and bind its termination to host death. Private launchd use of coalitions, if any on the target OS, would not be a contract Cascade can rely on or qualify from this source.

## Consequence for Cascade

The launchd lead cannot replace the managed-process exit proof. It fails two independent parts of the accepted contract:

- **lifetime coupling:** an `SMAppService` job is persistent system-owned registration, not a child whose lifetime is bound to the registering host;
- **containment and evidence:** same-process-group cleanup can be escaped by eligible arbitrary code and supplies neither a non-escapable membership rule nor Cascade’s required actual-exit observation.

Putting a trusted supervisor in the launchd job changes which death triggers group cleanup, but does not solve host-to-job binding. Putting the arbitrary worker directly in the launchd job removes the separate supervisor without creating host-death coupling and still does not provide the required exit receipt. Nesting worker processes under the job preserves the group-escape problem.

No further synthetic fixture can convert these missing public contracts into platform guarantees. A native qualification could characterize one signed build and OS version, but it could not prove that arbitrary code is unable to use documented group-changing syscalls; the present task therefore did not run one.

The smallest genuine future design fork is architectural, not another launchd setting:

1. retain the noncooperative arbitrary-worker and host/supervisor-death guarantee, and keep the launcher blocked until a compatible lifetime mechanism and identity-bound exit evidence are established and qualified; or
2. deliberately narrow the trust/lifetime requirement to fixed cooperative job code, or accept an OS-owned persistent supervisor whose lifetime is independent of the Cascade host.

The second branch weakens or changes the accepted product contract. This report does not select it or ask the user to repeat the already-resolved policy choice. The investigation is not a proof that no solution can exist on macOS. Under the existing decision, the native launcher remains disabled.
