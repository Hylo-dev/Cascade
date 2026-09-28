# Notch surfaces: state and remaining choice

Survey of 20 September 2026 for [Design the notch states and surfaces](../../../.scratch/cascade-product/issues/07-notch-surfaces.md). A comparison document, not a newly run prototype nor an approved specification.

## Decisions already settled

| State | Contract to keep |
| --- | --- |
| Rest | Alignment to the physical notch, chrome also on the display without a notch; non-activating panel. |
| Hover | Haptics at the start of the hover, as in the approved specification; the ticket's initial text "after opening" is historical. |
| Compact | Primary activity on the left; second activity in the separate right circle. |
| Expanded | Hover on the primary; click or accessible action on the secondary. The manual interaction is not replaced by a notice. |
| Notice | Occupies both wings; the most recent replaces the previous one. Hover removes it. No replay of the notices discarded during expansion or screen lock. |
| Widgets | Page hosted in the expanded state; editor, customization and contextual priorities stay in their own tickets. |
| Black and glass | Keep the existing renderer; glass lights in the expanded state, still when not needed and with Reduce Motion. |
| Search | Field and results of the real Spotlight, with native sizes, confirmed by the user. Integration already present; native proofs of focus, join and restore remain. |
| Settings | Under the notch, macOS language. Sidebar, Form, search and connection to focus already present; the visual verification of the current build remains. The functional scopes depend on their respective tickets. |

Sources: [approved interactive specification](../../superpowers/specs/2026-09-04-interactive-notch-design.md), [activity contracts](../../architecture/live-activity-contracts.md), [glass](../../architecture/glass-lighting.md), [requirements received](project-baseline.md). The first six rows are not proposed again as open choices.

## Comparison that led to the search choice

The [local probe of 9 September](../research/spotlight-notch-live-probe-macos27.md) moved the real Spotlight under the notch through Accessibility on macOS 27 beta. The inner field did not turn out to be resizable; focus/IME/VoiceOver, restore after closing, other displays/OSes and the complete visual composition are not qualified. It was not rerun today.

| Path | What the person sees and uses | Consequence |
| --- | --- | --- |
| **First tranche with the original Spotlight (recommended)** | System field and results, native sizes; Cascade only studies the join to the notch. The keyboard stays with Spotlight. | Keeps the preference for the real Spotlight. Accepts that the field does not follow Cascade's custom sizes. AX requires consent and verification; if unavailable, Spotlight stays in its normal position. |
| Field redrawn as part of the notch | A field with Cascade geometry and style that should keep driving the original results. | The available probe does not demonstrate replacement of the field, IME, selection, keyboard or accessibility. Separate research is needed; any new private API requires the individual exception just approved as policy. It cannot be implemented as a simple refinement of the first path. |

**Decision presented (now approved):** accept for the first tranche Spotlight's original field, with its own sizes, instead of immediately demanding a field redrawn inside the notch. This is a choice about the visible result; not an approval to qualify AX in advance or to use private APIs.

The choice was approved. The subsequent survey found the join already implemented: the next step is to verify its native close/restore and focus cycle, without producing a duplicate prototype. The settings are also already implemented; verifying their position does not replace the functional decisions of their respective tickets.

## Answer received

On 20 September the user confirms "yes, exactly": first tranche with the original Spotlight field and native sizes. The canonical decision is recorded in the surfaces ticket. The join, restore, focus/accessibility and display/OS combinations remain to be tested.

## Correction after the confirmation

The search in the code found SpotlightCoordinator, SpotlightAccessibilityMonitor and SpotlightDropletPanel already integrated in CascadeServices, with the [plan and tests of 9 September](../../superpowers/plans/2026-09-09-spotlight-droplet.md). The earlier reference to the probe alone uses incomplete information. The path with the original field already exists; the remaining work concerns qualification and restore, not its first implementation. The current details are in the surfaces ticket.

## Outcome of the continuation

The surfaces ticket is resolved as a decision/prototype. The [local verification](../../superpowers/verification/2026-09-20-spotlight-native-continuation.md) observes native field, focus, calculation via AX and restore in the two cycles, as well as the settings. The general qualifications remain listed in the report; they do not justify a new prototype of the same surfaces. The subsequent arbitration is in its own ticket.
