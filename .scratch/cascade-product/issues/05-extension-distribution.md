# Define extension installation and isolation

ID: 05
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 01, 04, 19, 22

## Question

How should widgets reach the user: installed automatically by the source app, modules added to a folder, or both? The user wants SwiftUI and has proposed import or loading from a folder: clarify what import means and decide format, discovery, activation, verifiable origin, update, removal, revocation and behavior after a crash. Choose the process boundary and document whether external code can block the host. The outcome must make concrete the promise "integrate the protocol and a widget appears".

## Progress of 9 September 2026

The native boundary in on-demand processes is approved, with ordinary content kept by the host and remote SwiftUI scenes. The addon can include the libraries it needs and work without the source app; Cascade must remain open. Preference for the container the system can register, to be tested before fixing the format. No special path for the team's widgets.

The [approved spec](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md) is made executable in [P0](../../../docs/superpowers/plans/2026-09-09-addon-runtime-00-platform.md), [P2](../../../docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md) and [P4](../../../docs/superpowers/plans/2026-09-09-addon-runtime-04-release.md). The ticket stays open for the actual tests of discovery, signing, sandbox, shutdown after a host crash and update on the supported macOS versions.

## Realignment of 14 September 2026

The [current plan](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md) documents the implemented internal contracts, resolver, runtime coordinator, services, resources and storage. The last complete path verified is still a package suite, not the installation and execution of an external addon.

The [approved control policy](../../../docs/superpowers/specs/2026-09-10-addon-control-policy.md) accepts the risk of work delegated autonomously to macOS; it keeps the requirements on managed processes. The launcher qualification stays open. The distinct C0d blocker is now tracked in [Define a safe exit proof for managed processes](22-managed-process-exit-proof.md); the scene tests remain in the [SwiftUI UI ticket](19-extension-host-probe.md).

Native transport/provider, real discovery and activation, identity in the update lifecycle, installation/distribution and integration into the app remain to be completed and tested. This update keeps the ticket open and does not enable any launcher.
