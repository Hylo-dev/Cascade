# Prepare conversion formats and progress

ID: 86
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 76, 81

## Question

Extract the pure part of task 6 of the [approved plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): an incremental, bounded parser of FFmpeg progress, bounded decoding of ffprobe metadata, intersection of the compatible formats and closed presets consistent with the verified build. No process, file access, coordinator, job persistence or production mounting.

Acceptance: split chunks and CRLF, missing/non-finite/negative values and excessive input; correct microseconds also for the out_time_ms alias; progress=end does not represent success. MP4/M4A/WAV/FLAC formats, MP3 excluded; attached_pic covers do not become video tracks; mixed selections without silent skipping. Controlled arguments and no option or path coming from the widget. Targeted tests and the root's personal review. The component produces only a plan: authorization, confinement, quotas, physical exit and validation of the results remain in [Run file conversions in recoverable jobs](82-file-workspace-conversion-jobs.md).

## Answer

Implemented by GPT-5.6 Sol in commit `5c53ae5`, with the root's personal review and independent verification. Incremental parser with a maximum line of 4096 bytes and coalescing observation; ffprobe metadata bounded to 64 KiB and 32 tracks; shared MP4/M4A/WAV/FLAC selection. Closed presets with exact track indices, no path or command from the widget. Covers and video without an explicit disposition excluded from the MP4 capability. Duration from the selected tracks, fallback to the container only when there are no extraneous tracks. `progress=end` remains telemetry, not success.

Fifteen targeted tests with RED/GREEN cycles; independent root FileWorkspace/FFmpeg filter: 64 tests passed. Signed build succeeded, Applications link updated and restart verified at PID 34695. The review fixed the handling of unidentified covers, the audio arguments for silent videos and tests that did not measure the behavior. No process, coordinator or job activated. The [full conversions ticket](82-file-workspace-conversion-jobs.md) stays open; [tranche evidence](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).
