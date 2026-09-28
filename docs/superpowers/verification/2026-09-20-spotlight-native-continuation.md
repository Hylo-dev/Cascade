# Native Spotlight and settings: local verification

20 September 2026. Continuation authorized with Ponytail and CLI/AppleScript tools. No change to the app's code, no activation of the addon launcher, no permission changed. The Spotlight integration was enabled temporarily and returned to its initial disabled value.

## Build and conditions

The signed Apple Development build was completed by the official script on a local copy of451 inputs identical to the checkout, after the iCloud plist became available. The Applications link points to CascadeAddonDevelopment. [Build delivery](../../../.scratch/codex-addon/20260920-spotlight-native/delivery-resumed.json).

Evidence limited to the local macOS27 system and to a display1470×956. The observations use the owner com.apple.campo and the SpotlightSearchField descendant: the Siri conversations window is distinct and does not constitute evidence of the search.

## Observed outcomes

| Check | Local outcome |
| --- | --- |
| Opening from the «Apri Spotlight dal notch» command | Native field observed; settled capsule520×87. |
| Field focus | AXFocused=true on the identified field. |
| Synthetic calculation | AX insertion of2+2 succeeded; native result4 observed and captured. No result launched. Query cleared. |
| Disabling with the field open | Return from(475,64) to the initial position(475,65), with native dimensions preserved. |
| Disabling after close and reopen | The settled capsule's movement measured first; field then absent; reopening with the integration off at(475,65), equal to the baseline. |
| Settings | Window cascade.settings760×570 at(355,152), sidebar and controls visible; focus on the settings.size control. |
| Preferences | spotlightEnabled restored to0. |

[Structured evidence](../../../.scratch/codex-addon/20260920-spotlight-native/native-qualification-result.json), [cycle with close](../../../.scratch/codex-addon/20260920-spotlight-native/closed-cycle.json), [calculation result](../../../.scratch/codex-addon/20260920-spotlight-native/native-calculation.png), [final relaunch](../../../.scratch/codex-addon/20260920-spotlight-native/restart-evidence.json).

The key simulation produced no text and is not declared passed; the calculation is evidence of the AX insertion. Global focus required explicit selection of the native process for the close. A first cycle sampled the transient window as large as the display: it was replaced by a test that waits for and verifies a movement of the settled capsule before closing it.

## Limits and review

The restoration observed after close does not prove that the monitor manages to move a nonexistent window: the code keeps the limit already described in the review, and macOS may restore its own position on reopening. The hypothesized user-facing effect was not reproduced; the proposal of a generalized restoration in clearTarget is not applied, since it may interfere with clearing the query after Escape.

Keyboard/IME, VoiceOver, continuous dragging, display/OS combinations and performance measurements remain separate. The handoff/shortcut/AX clearing checks and the6 droplet behaviors had already passed on the same code; they were not repeated to increase the number of tests. This verification does not qualify transport, processes or external addons.
