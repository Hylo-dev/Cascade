# Audio tap permission spike: a denied capture permission and helper grouping

Probe: `Prototypes/AudioTapPermissionProbe/` (throwaway, not linked into Cascade).
Part B's Tasks 5, 7 and 10 read the four answers below.

## Environment

- macOS: 27.0 (build 26A5425a), `sw_vers`
- Hardware: `Mac14,2` (`sysctl hw.model`)
- Toolchain: Xcode (`/Applications/Xcode.app`), `xcrun swiftc -O`

## Status

The probe builds and `processes` ran (smoke check below). The permission runs
need a person to toggle System Settings and listen, so P1 to P3 and the
Safari/Chrome part of P4 are pending. `tap` was NOT run during the build: the
terminal's System Audio Recording state was not known, and a tap can raise a
permission prompt.

## P1. With System Audio Recording denied, does `AudioHardwareCreateProcessTap` fail?

Pending: run by the human partner.

## P2. If it succeeds, is the tapped app silenced (`mutedWhenTapped`) or still audible?

Pending: run by the human partner.

## P3. Is there any readable signal of denial?

Candidates: the tap creation status, `kAudioTapPropertyFormat` (the probe prints
its fields or the OSStatus that refused it), the IOProc input all-zero for a
known-loud source (`peakThisSecond` of 0 with `callbacks` above 0).

Pending: run by the human partner.

## P4. Browser audio process objects (PID, bundle ID, executable, outermost `.app`)

Safari and Chrome playing a YouTube video: pending, run by the human partner.

Smoke check (not the requested run): `processes` with Brave Browser playing, on
this machine. Only the audio-rendering process has `isRunningOutput: true`, and
it is a helper, not the browser's main process:

```json
{"bundleID": "com.brave.Browser.helper", "executablePath": "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/154.1.96.61/Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper", "isRunningOutput": true, "objectID": 158, "outermostApp": "/Applications/Brave Browser.app", "pid": 96095}
{"bundleID": "com.brave.Browser.helper", "executablePath": "/Applications/Brave Browser.app/Contents/Frameworks/Brave Browser Framework.framework/Versions/154.1.96.61/Helpers/Brave Browser Helper.app/Contents/MacOS/Brave Browser Helper", "isRunningOutput": false, "objectID": 159, "outermostApp": "/Applications/Brave Browser.app", "pid": 96097}
```

Reading, for the smoke only: the bundle ID is the helper's
(`com.brave.Browser.helper`), not the browser's, so grouping by bundle ID would
not find the app; the outermost `.app` of the executable does
(`/Applications/Brave Browser.app`). The rest of the output confirms the walk:
`Claude Helper.app` inside `Claude.app` groups under `/Applications/Claude.app`,
and `PluginHost.xpc` inside Cascade groups under the Cascade `.app`. Daemons with
no `.app` in their path (for example `/usr/libexec/audiomxd`) have no
`outermostApp`, and some have an empty bundle ID.

## How to run

Build once (the script builds its own copy; this is only for `processes`):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swiftc -O Prototypes/AudioTapPermissionProbe/main.swift -o /tmp/audio-tap-permission-probe
```

P1 to P3, permission on, then off. Run from the terminal under test, someone
listening:

1. System Settings, Privacy & Security, Screen & System Audio Recording: the
   terminal ON. Run `Prototypes/AudioTapPermissionProbe/run-probe.sh`, answer y/n,
   paste the `--- paste into the note ---` block under P1 to P3 as "granted".
2. Turn the terminal OFF in the same pane (quit and reopen the terminal if macOS
   asks). Run `Prototypes/AudioTapPermissionProbe/run-probe.sh` again, paste the
   block as "denied". Record: does `tap` print an `osStatus` error (P1), is the
   tone audible while tapped (P2), what `tapFormat`, `callbacks` and
   `peakThisSecond` show (P3). Turn the permission back ON afterwards.

P4, no permission needed. Play a YouTube video in Safari, then run, then repeat
with Chrome:

```bash
/tmp/audio-tap-permission-probe processes | python3 -c 'import json,sys;[print(json.dumps(p)) for p in json.load(sys.stdin)["processes"] if p.get("isRunningOutput")]'
```

Paste the lines for each browser under P4.
