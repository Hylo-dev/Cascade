"""Bounded post-handshake composition evidence; never launcher admission."""
import math


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def classify(record):
    mode = record.get("mode")
    if mode not in {"broker", "normal", "crash"} or record.get("observationError"):
        return "UNKNOWN"
    if any(record.get(k) is not True for k in
           ("authenticated", "registered", "confirmed", "survivedInvalidation")):
        return "UNKNOWN"
    if any(not finite(record.get(k)) for k in ("trigger", "brokerGuard", "providerGuard")):
        return "UNKNOWN"
    trigger = record["trigger"]
    if trigger + 8.5 >= min(record["brokerGuard"], record["providerGuard"]): return "UNKNOWN"
    exits = record.get("exits", {})
    for participant in ("broker", "provider"):
        event = exits.get(participant, {})
        if not finite(event.get("time")) or type(event.get("status")) is not int: return "UNKNOWN"
        if event["time"] < trigger: return "UNKNOWN"
        if event["time"] > trigger + 8: return "FAIL"
        expected = (0,) if participant == "broker" and mode == "broker" else (9, 15)
        if event["status"] not in expected: return "FAIL"
    if mode == "broker":
        if record.get("rootAlive") is not True: return "FAIL"
    elif (record.get("rootStatus") != (0 if mode == "normal" else -9) or
          not finite(record.get("rootExitObserved")) or record["rootExitObserved"] < trigger):
        return "UNKNOWN"
    return "PASS"
