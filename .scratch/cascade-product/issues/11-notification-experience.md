# Define notifications from other apps and device alerts

ID: 11
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 02, 04, 08

## Question

Within which coverage limits and with which consent modes does Cascade present notifications from non-integrated apps, a requirement confirmed by the user? Decide duplication or replacement of the system banners, actions and opening of the source app, history, per-app filters, sensitive content, Focus and lock screen. Distinguish a notification received from another app, a detected Bluetooth event and a notification emitted by an extension; choose an explicit fallback where the research shows limits.

The research found polling on a private store in Sapphire: before adopting that path, verify coverage and permissions in a test account and address the conflict with the project constraint against polling and needless wakeups. The user's requirement does not authorize declaring a partial capture universal, nor implicitly loosening the resource constraint.
