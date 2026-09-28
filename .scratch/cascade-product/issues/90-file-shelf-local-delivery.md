# Verify and deliver the first local file shelf

ID: 90
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 89, 91, 92

## Question

Run phase D of the [approved local plan](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): root review of the commits, targeted tests and full suite, native QA on Finder drag/refusal/cancellation/partial, restart, default page and manual navigation, VoiceOver and Reduce Motion. Record the URL/promise limits and the deferred conversion. Signed build, update of `/Applications/Cascade.app`, closing and reopening with the updated process verified. Do not claim the external launcher as qualified.

## Partial progress: ticket open

Final signed build exit 0 (`local-app-build.log`), SDK boundary and signature checks passed. `/Applications/Cascade.app` points to `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf/Build/Products/Debug/Cascade.app`. The previous process PID 34695 did not exit with Quit via CUA: the root sent a targeted TERM and verified that the process was gone, then reopened the app via CUA. New PID 52683, launched on 26 September 2026 at 20:23:07 CEST, executable in the linked bundle and binary updated at 20:21:40. Screenshot of the closed notch visible. SwiftPM tests 1,416/1,416 and signed app tests 6/6 passed. Remaining weekly reserve 95%.

The shelf's native QA stays **open**: Finder `getApp`/AX fail repeatedly with ScreenCaptureKit `-3812` (`invalid parameter`); the coordinates 64/72 in Cascade's AX/screenshot did not open the notch. So Finder input/output, real cards and animations, copies and originals in Finder, cancellation/refusal/partial, persistence observed in the app, manual navigation, VoiceOver and Reduce Motion in the notch are not verified. The persistence and Reduce Motion unit tests do not replace these tests. Incoming file promises and Convert remain unavailable. Resume from the native QA when Finder/notch access is recovered; the addon launcher and the external tickets stay separate.

A later direct test by the user: dragging files under the edge produces the pulse and the opening; the drop sound is heard, but the file is not captured. This is a failure of the incoming QA, tracked in [Fix file capture in the shelf's native drag](91-file-shelf-native-drop-regression.md). The removal of the Shelf/Activity selector was requested by the user and is in progress; the temporary drop area, the native loop and the Mission Control guard still require review and testing. The delivery ticket stays open.

The source fix was reviewed and delivered in a new signed build; `/Applications/Cascade.app` restarted at PID 59537 on 26 September 2026 at 21:36:32. The automated Finder test keeps failing in the CUA capture with ScreenCaptureKit `-3811`; the user's manual confirmation is still pending. The ticket stays blocked by the native test of the [incoming drag](91-file-shelf-native-drop-regression.md), without inferring from the build that the capture succeeded.
