#!/bin/bash
# Throwaway probe, see README.md. Run from anywhere: it needs a person listening.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
probe="$work/audio-lifecycle-probe"
results="$work/results.txt"
tone="$work/tone.wav"
afplay_pid=""
creator_pid=""

cleanup() {
    [ -n "$creator_pid" ] && kill -9 "$creator_pid" 2>/dev/null
    [ -n "$afplay_pid" ] && kill "$afplay_pid" 2>/dev/null
    "$probe" inspect --destroy >/dev/null 2>&1
}
trap cleanup EXIT

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}" \
    xcrun swiftc -O "$here/main.swift" -o "$probe" || exit 1

# A 10-minute quiet 440 Hz tone, so one afplay process (one tappable pid) lasts the whole run.
python3 - "$tone" <<'PY'
import math, struct, sys, wave
with wave.open(sys.argv[1], "wb") as out:
    out.setnchannels(2); out.setsampwidth(2); out.setframerate(44100)
    second = b"".join(struct.pack("<hh", v, v) for v in (int(3000 * math.sin(2 * math.pi * 440 * n / 44100)) for n in range(44100)))
    for _ in range(600): out.writeframes(second)
PY

start_afplay() {
    afplay "$tone" &
    afplay_pid=$!
    sleep 2
}

ask_audible() {
    local answer
    read -r -p "$1 Is the 440 Hz tone audible right now? (y/n) " answer
    echo "$answer"
}

start_afplay

echo "=== A and B: private aggregate holding a muting tap on afplay ($afplay_pid) ==="
"$probe" create-private "$afplay_pid" > "$work/private.json" &
creator_pid=$!
sleep 2
echo "creator output: $(cat "$work/private.json")"
echo "(the IOProc copies the tap to the output, so the tone should be audible through the aggregate)"
kill -9 "$creator_pid"; wait "$creator_pid" 2>/dev/null; creator_pid=""
sleep 2
aggregate_uid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["aggregateUID"])' "$work/private.json")"
tap_uid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["tapUID"])' "$work/private.json")"
private_inspect="$("$probe" inspect "$aggregate_uid" "$tap_uid")"
echo "inspect after kill -9: $private_inspect"
audible_after_private="$(ask_audible 'B:')"

echo "=== C: public aggregate ==="
"$probe" create-public > "$work/public.json" &
creator_pid=$!
sleep 2
public_uid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["aggregateUID"])' "$work/public.json")"
kill -9 "$creator_pid"; wait "$creator_pid" 2>/dev/null; creator_pid=""
sleep 2
public_inspect="$("$probe" inspect "$public_uid")"
echo "inspect after kill -9: $public_inspect"

echo "=== cleanup ==="
destroy="$("$probe" inspect --destroy "$aggregate_uid" "$tap_uid" "$public_uid")"
echo "inspect --destroy: $destroy"
audible_after_destroy="$(ask_audible 'After destroy:')"

cat <<REPORT

--- paste into the note ---
A (private aggregate + tap gone after SIGKILL?): $private_inspect
B (afplay audible after SIGKILL, tap muting it): $audible_after_private
C (public aggregate survived SIGKILL?): $public_inspect
Cleanup: $destroy
Audible after destroy: $audible_after_destroy
REPORT
