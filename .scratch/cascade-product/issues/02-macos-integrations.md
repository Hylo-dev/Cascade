# Integrate macOS Spotlight, notifications and activities: feasibility

ID: 02
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: codex-research-02
Blocked by: none

## Question

Which APIs and techniques let Cascade show notifications from non-integrated apps, Bluetooth connection events, current media (including from the browser) and haptic feedback? Which operations are possible on the real macOS Spotlight: invocation, position, style and integration into the notch? Explicitly distinguish public APIs, private techniques, Accessibility, permissions, incomplete coverage and system versions. Do not confuse the app's own UserNotifications with a universal reader. Do not yet choose between the system Spotlight and a search of our own: produce the feasibility matrix for both.

## Answer

Research resolved on 4 September 2026 by codex-research-02. [Feasibility matrix, sources and remaining checks](../../../docs/wayfinder/research/macos-integrations.md).

- The real Spotlight can be invoked; any repositioning through Accessibility must be tested. No public contract was found to change its materials and hierarchy or to host it in Cascade. A search UI of our own does not automatically have feature parity.
- UserNotifications concerns one's own app. Sapphire polls a private Notification Center SQLite store: this demonstrates neither universal coverage nor immediate delivery. Accessibility is another technique to verify; its permissions are not equivalent to access to the store.
- Bluetooth and requesting haptic feedback have public APIs; the availability of accessory data and the perception of the impulse depend on the hardware and the system.
- In the projects examined, global Now Playing information goes through private MediaRemote. Detecting or routing audio with Core Audio does not by itself provide the title, the artwork or the identity of the browser tab.
- ActivityKit and the iPhone activities shown by the system do not constitute a protocol for Cascade to automatically capture other apps' activities.

Reproducible context: branch `codex/research/cascade-system-20260904`, commit `38dc5b7081d6badebaa419f7223a39d06b1e6a46`, worktree `/private/tmp/cascade-wayfinder-system`. No access to notifications or personal databases, no permission changes, no UI test performed. The fallback choices and the scope of supported versions remain open.
