"""Classify the fixed two-chain experiment; never launcher admission."""
import math

NODES = {"A.broker", "A.worker", "B.broker", "B.worker"}


def classify(record):
    mode = record.get("mode")
    if mode not in {"stop", "broker-crash", "host-normal", "host-crash"}:
        return "UNKNOWN"
    if record.get("observationError") or any(record.get(key) is not True for key in
            ("authenticated", "registered", "sameInstances", "actionConfirmed", "windowComplete")):
        return "UNKNOWN"
    host_expected = {"stop": None, "broker-crash": None, "host-normal": 0, "host-crash": -9}[mode]
    if "hostStatus" not in record or record["hostStatus"] != host_expected:
        return "UNKNOWN"
    trigger, guards = record.get("trigger"), record.get("guards", {})
    if set(guards) != NODES or any(type(v) not in (int, float) or not math.isfinite(v)
                                   for v in [trigger, *guards.values()]):
        return "UNKNOWN"
    if any(trigger + 2.5 >= guard for guard in guards.values()):
        return "UNKNOWN"
    expected = NODES if mode.startswith("host-") else {"A.broker", "A.worker"}
    exits = record.get("exits", {})
    if not set(exits) <= NODES:
        return "UNKNOWN"
    if set(exits) != expected:
        return "FAIL"
    if not mode.startswith("host-") and record.get("survivorConfirmed") is not True:
        return "FAIL"
    for node, event in exits.items():
        when, status = event.get("time"), event.get("status")
        if type(status) is not int or type(when) not in (int, float) or not math.isfinite(when):
            return "UNKNOWN"
        if when < trigger:
            return "UNKNOWN"
        if when > trigger + 2 or when >= guards[node] - .5:
            return "FAIL"
        accepted = {0} if mode == "stop" and node == "A.broker" else {9, 15}
        if mode == "broker-crash" and node == "A.broker":
            accepted = {9}
        if status not in accepted:
            return "FAIL"
    return "PASS"
