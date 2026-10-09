#
#  run-probe.py
#  AudioSystemProbe
#

"""Build and bound the standalone capability probe; product audio is never loaded."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    source = Path(__file__).with_name("AudioSystemProbe.mm")
    developer = os.environ.get("DEVELOPER_DIR", "/Applications/Xcode-beta.app/Contents/Developer")
    environment = dict(os.environ, DEVELOPER_DIR=developer)
    with tempfile.TemporaryDirectory(prefix="cascade-audio-system-probe-", dir="/private/tmp") as directory:
        binary = Path(directory) / "audio-system-probe"
        subprocess.run(
            [
                "/usr/bin/xcrun", "clang++", "-std=c++20", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                "-framework", "Foundation", "-framework", "CoreAudio", "-framework", "AudioToolbox",
                str(source), "-o", str(binary),
            ],
            check=True, env=environment, timeout=60,
        )
        completed = subprocess.run(
            [str(binary), "--silent-stream"],
            check=True, capture_output=True, text=True, timeout=12,
        )
        report = json.loads(completed.stdout)
        print(json.dumps(report, indent=2, sort_keys=True), flush=True)
        if completed.stderr:
            print(completed.stderr, file=sys.stderr)
        assert report["schemaVersion"] == 1
        assert report["private"]["functionsCalled"] == 0
        assert report["otherProcessSettersCalled"] == 0
        assert report["audibleEffectMeasured"] is False
        if report.get("queueStartStatus") == 0:
            assert report["callbacks"] > report["retiredCallbacks"], "No active render callback progressed"
            assert report["callbackEnqueueStatus"] == 0, "Queue callback could not return its buffer"
            assert report["queueDisposeStatus"] == 0, "Queue disposal failed"
        round_trip = report.get("ownMuteRoundTrip", {})
        if round_trip.get("attempted"):
            assert round_trip["muteStatus"] == 0, "Own-process mute write failed"
            assert round_trip["whileMuted"]["value"] == 1, "Own-process mute readback failed"
            assert round_trip["unmuteStatus"] == 0, "Own-process unmute write failed"
            assert round_trip["whileUnmuted"]["value"] == 0, "Own-process unmute readback failed"
            assert round_trip["restoreStatus"] == 0, "Own-process mute restoration failed"
            assert round_trip["before"]["value"] == round_trip["after"]["value"]


if __name__ == "__main__":
    main()
