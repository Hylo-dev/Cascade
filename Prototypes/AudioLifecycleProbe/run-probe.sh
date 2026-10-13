#!/bin/bash
# Throwaway probe, see README.md. Run from anywhere: it needs a person listening.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
probe="$work/audio-lifecycle-probe"
tone="$work/tone.wav"
afplay_pid=""
creator_pid=""

cleanup() {
    [ -n "$creator_pid" ] && kill -9 "$creator_pid" 2>/dev/null
    [ -n "$afplay_pid" ] && kill "$afplay_pid" 2>/dev/null
    [ -x "$probe" ] && "$probe" inspect --destroy >/dev/null 2>&1
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
audible_baseline="$(ask_audible 'Baseline (nothing tapped):')"

echo "=== A and B: private aggregate holding a muting tap on afplay ($afplay_pid) ==="
"$probe" create-private "$afplay_pid" > "$work/private.json" &
creator_pid=$!
# The first run triggers the System Audio Recording prompt, and the probe prints
# its JSON only once the tap, the aggregate and the IOProc are running. Wait for
# that line (up to 30 s, so the prompt can be answered) before judging (b).
for _ in $(seq 60); do
    [ -s "$work/private.json" ] && break
    kill -0 "$creator_pid" 2>/dev/null || break
    sleep 0.5
done
if ! grep -q '"mode"' "$work/private.json" 2>/dev/null; then
    echo "error: create-private never reported a running tap. Its output:" >&2
    cat "$work/private.json" >&2
    exit 1
fi
sleep 1
echo "creator output: $(cat "$work/private.json")"
echo "(the IOProc reads the tap and writes silence, so the muted tone should now be SILENT)"
audible_tapped="$(ask_audible 'Tapped, before the kill:')"
kill -9 "$creator_pid"; wait "$creator_pid" 2>/dev/null; creator_pid=""
sleep 2
aggregate_uid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["aggregateUID"])' "$work/private.json")"
tap_uid="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["tapUID"])' "$work/private.json")"
private_inspect="$("$probe" inspect "$aggregate_uid" "$tap_uid")"
echo "inspect after kill -9: $private_inspect"
audible_after_kill="$(ask_audible 'After the kill:')"

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

if [ "$audible_tapped" = "y" ]; then
    reading="INVALID RUN: (b) was audible, so the tap never muted afplay"
elif [ "$audible_tapped" = "n" ] && [ "$audible_after_kill" = "y" ]; then
    reading="A yes, B no: the tap and its muting died with the process"
elif [ "$audible_tapped" = "n" ] && [ "$audible_after_kill" = "n" ]; then
    reading="A no, B yes: the muting tap outlived the process"
else
    reading="INCONCLUSIVE: an answer was not y/n (a=$audible_baseline b=$audible_tapped c=$audible_after_kill)"
fi

cat <<REPORT

--- paste into the note ---
Audible (a) baseline, before create-private: $audible_baseline
Audible (b) tapped, before the kill (the IOProc reads the tap and writes silence): $audible_tapped
Audible (c) after the kill: $audible_after_kill
Reading: $reading
  (b) silent -> (c) audible = tap and muting died with the process;
  (b) silent -> (c) silent  = the muting tap outlived it;
  (b) audible               = the tap never muted, the run is invalid.
Supporting, NOT conclusive (private objects are invisible to a fresh process): $private_inspect
C (public aggregate survived SIGKILL?): $public_inspect
Cleanup: $destroy
Audible after destroy: $audible_after_destroy
REPORT
