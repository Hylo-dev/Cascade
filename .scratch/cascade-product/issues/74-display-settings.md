# Connect display preferences and auxiliary surfaces

ID: 74
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/multi-display
Blocked by: 73

## Question

Implement and verify task 6 of the [multi-display plan](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) following the [spec](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). The execution tranche is authorized by the request of 25 September; close only with evidence and review.

## Answer

Implemented the native display and routing preferences, with the offline target preserved and temporary choices for non-persistent identities. Settings distinguishes the window anchor from the focus reserve; global and contextual commands make the target explicit. Spotlight waits for the actual closing, keeps the reserve while the native window is visible and recovers openings that never happened; lock and preview leave no orphaned reserves.

Evidence: 44 coordinator tests, 9 routing, 68 controller in the relevant checks; 15 signed Settings tests before the last fix and 2 new signed regressions RED→GREEN on the final fix. The Spotlight script and 7 droplet cases pass. Final scoped review PASS/PASS after three fixes: [report](../../../.superpowers/sdd/2026-09-24-multi-display-notch/task-6-rereview-3.md). The new full Settings run is in the delivery verification: the last attempts stopped because of an approval timeout before the launch. No restart and no physical multi-monitor qualification claimed here. [Evidence](../../../.superpowers/sdd/2026-09-24-multi-display-notch/task-6-report.md).
