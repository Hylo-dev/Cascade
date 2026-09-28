# Load external SwiftUI widgets: mechanisms and limits

ID: 01
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: codex-research-01
Blocked by: none

## Question

Which mechanisms let Cascade, distributed outside the Mac App Store, discover and host SwiftUI widgets provided by other apps or installed as modules in a folder, without recompiling the host? Compare Swift Package/import, dynamic bundles or frameworks, IPC/XPC and UI hosted in a separate process. Distinguish documented possibilities, ABI and type identity limits, signing and hardened runtime, real isolation, compatibility and what requires a test. Clarify why conforming to a protocol inside another app does not by itself produce discovery or transport of the UI. Indicate the technically viable alternatives, without choosing the final format on the user's behalf.

## Answer

Research resolved on 4 September 2026 by codex-research-01. [Report with sources and matrix of the alternatives](../../../docs/wayfinder/research/swiftui-extensions.md).

- Import and SwiftPM serve the build; they do not provide automatic discovery in another process.
- A binary bundle can provide SwiftUI UI loaded into the host, with signing/ABI constraints and without isolation from crashes or main-thread blocks.
- ExtensionKit offers public remote UI. The base classes are available since 13; the new extension point and discovery APIs require macOS 26. Separate distribution happens through a container app and requires user enablement.
- Compatibility of the legacy path on 14/15, signatures from different developers and behavior inside the notch panel require a test; the choice of format remains open.

Reproducible context: branch `codex/research/cascade-sdk-20260904`, commit `7a89398`, report also kept in the worktree `/private/tmp/cascade-wayfinder-sdk`. No prototype was run and no compatibility guarantee was inferred from API availability alone.
