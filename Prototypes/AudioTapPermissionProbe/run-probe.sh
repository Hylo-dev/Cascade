#!/bin/bash
# Throwaway probe, see README.md. Run from anywhere: it needs a person listening.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
probe="$work/audio-tap-permission-probe"
tone="$work/tone.wav"
afplay_pid=""
tap_pid=""

cleanup() {
    [ -n "$tap_pid" ] && kill "$tap_pid" 2>/dev/null
    [ -n "$afplay_pid" ] && kill "$afplay_pid" 2>/dev/null
}
trap cleanup EXIT

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
    xcrun swiftc -O "$here/main.swift" -o "$probe" || exit 1

# A 10-minute quiet 440 Hz tone, so one afplay process (one tappable pid) lasts the whole run.
python3 - "$tone" <<'PY'
import math, struct, sys, wave
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(2); out.setsampwidth(2); out.setframerate(44100)
    second = b"".join(struct.pack("<hh", v, v) for v in (int(3000 * math.sin(2 * math.pi * 440 * n / 44100)) for n in range(44100)))
    for _ in range(600): out.writeframes(second)
PY

afplay "$tone" &
afplay_pid=$!
sleep 2

read -r -p "Baseline (nothing tapped): is the 440 Hz tone audible? (y/n) " audible_baseline

echo "=== tap on afplay ($afplay_pid), 15 s, muting ==="
"$probe" tap "$afplay_pid" 15 > "$work/tap.json" &
tap_pid=$!
# The first tap triggers the System Audio Recording prompt when the permission
# was never answered. Wait (up to 30 s) for the first JSON line, either a
# per-second report or an error, before asking.
for _ in $(seq 60); do
    [ -s "$work/tap.json" ] && break
    kill -0 "$tap_pid" 2>/dev/null || break
    sleep 0.5
done
sleep 1
if ! grep -q '"mode"' "$work/tap.json" 2>/dev/null; then
    echo "tap did not start. Its output (a denial that fails creation IS the P1 result):"
    cat "$work/tap.json"
    tapped_started="no"
    audible_tapped="n/a"
else
    tapped_started="yes"
    read -r -p "Tapped (15 s window, answer within it): is the tone audible now? (y/n) " audible_tapped
fi
wait "$tap_pid" 2>/dev/null; tap_pid=""

audible_after="$(read -r -p 'After the tap ended: is the tone audible? (y/n) ' a; echo "$a")"

cat <<REPORT

--- paste into the note ---
Permission state of this terminal: (write: granted / denied)
Tap started: $tapped_started
Audible baseline: $audible_baseline
Audible while tapped (the IOProc reads the tap and writes silence): $audible_tapped
Audible after the tap ended: $audible_after
Reading: while tapped, 'n' = the tapped app is silenced (muting held); 'y' = still audible
  (a denied tap neither muted nor failed, or never started).
tap output:
$(cat "$work/tap.json")
REPORT
