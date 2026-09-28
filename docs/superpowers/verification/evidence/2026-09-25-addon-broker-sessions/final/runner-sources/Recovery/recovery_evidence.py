"""Classify a bounded external-extension recovery experiment, never admission."""
import math


def classify(record):
    if record.get("mode") not in {"normal", "crash"} or record.get("observationError"):
        return "UNKNOWN"
    flags = ("authenticated", "registered", "sameInstance", "invalidationObserved",
             "stillAliveAfterInvalidation", "freshAuthenticated", "freshInstance",
             "freshRegistered", "freshConfirmed")
    if any(record.get(key) is not True for key in flags): return "UNKNOWN"
    times = ("trigger", "guardDeadline", "hostExitObserved", "serviceExit", "restartStarted",
             "freshGuardDeadline", "freshStopTrigger", "freshExit")
    if any(type(record.get(key)) not in (int, float) or not math.isfinite(record[key]) for key in times):
        return "UNKNOWN"
    if any(type(record.get(key)) is not int for key in
           ("hostStatus", "serviceStatus", "freshHostStatus", "freshStatus")): return "UNKNOWN"
    if record["hostStatus"] != (0 if record["mode"] == "normal" else -9) or record["freshHostStatus"] != 0:
        return "UNKNOWN"
    trigger, stop = record["trigger"], record["freshStopTrigger"]
    if trigger + 8.5 >= record["guardDeadline"] or stop + 8.5 >= record["freshGuardDeadline"]:
        return "UNKNOWN"
    if record["serviceExit"] < trigger or record["hostExitObserved"] < trigger or record["freshExit"] < stop:
        return "UNKNOWN"
    if record["restartStarted"] <= max(record["hostExitObserved"], record["serviceExit"]) or stop < record["restartStarted"]:
        return "FAIL"
    if record["serviceExit"] > trigger + 8 or record["freshExit"] > stop + 8:
        return "FAIL"
    if record["serviceStatus"] not in (9, 15) or record["freshStatus"] not in (9, 15): return "FAIL"
    return "PASS"
