# Audio tap permission probe

Throwaway, not linked into Cascade. `main.swift` compiles with `swiftc -O`
against the configured Xcode SDK into a temporary directory.

## Modes

`tap <pid> [seconds]` taps `<pid>` with `mutedWhenTapped`, builds a private
aggregate over the default output and runs an IOProc that reads the LAST input
buffer (the tap) and writes zeros to the outputs. It prints one JSON line per
second (default 5 s) with the callback count, the peak of the tap buffer in that
second, the tap format and the input buffer count, then tears everything down.
A failing `AudioHardwareCreateProcessTap` prints the exact OSStatus and exits.

`processes` prints every Core Audio process object as JSON: object ID, PID,
bundle ID, `IsRunningOutput`, executable path (`proc_pidpath`) and the outermost
enclosing `.app`. It is read-only and needs no permission.

## Runs for the human partner

`run-probe.sh` plays a tone with `afplay`, runs `tap` against it for 15 s and
asks y/n whether the tone is audible; run it once with the permission on and once
with it off for the terminal (System Settings, Privacy & Security, Screen &
System Audio Recording). `processes` is run once with Safari and once with
Chrome playing a YouTube video. The commands and where the results go are in
`docs/superpowers/verification/2026-10-10-audio-tap-permission-spike.md`.
