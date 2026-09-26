"""Verdicts for a throwaway XPC lifecycle probe, never launcher admission."""

import math
import os
import signal


def classify(record):
    mode = record.get("mode")
    if mode not in {"cooperate", "cancel", "normal", "crash"}:
        return "UNKNOWN"
    if record.get("observationError") or any(record.get(key) is not True for key in
            ("authenticated", "registered", "sameInstance", "actionConfirmed", "windowComplete")):
        return "UNKNOWN"
    if mode in {"cooperate", "cancel"}:
        if record.get("hostAliveAtWindowEnd") is not True:
            return "UNKNOWN"
    elif record.get("hostStatus") != (0 if mode == "normal" else -signal.SIGKILL):
        return "UNKNOWN"
    trigger, guard = record.get("trigger"), record.get("guardDeadline")
    if any(type(v) not in (int, float) or not math.isfinite(v) for v in (trigger, guard)):
        return "UNKNOWN"
    if trigger + 2.5 >= guard:
        return "UNKNOWN"
    exited = record.get("serviceExit")
    if exited is None:
        return "FAIL"
    status = record.get("serviceStatus")
    if type(status) is not int or type(exited) not in (int, float) or not math.isfinite(exited):
        return "UNKNOWN"
    if exited < trigger:
        return "UNKNOWN"
    if exited > trigger + 2 or exited >= guard - 0.5:
        return "FAIL"
    if os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGALRM:
        return "FAIL"
    if mode == "cooperate" and status != 0:
        return "FAIL"
    if mode != "cooperate" and not (os.WIFSIGNALED(status) and
            os.WTERMSIG(status) in (signal.SIGKILL, signal.SIGTERM)):
        return "FAIL"
    return "PASS"
