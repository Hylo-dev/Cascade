"""Evidence for restarting a broker and separating two host sessions."""
import math


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def chain_exit(exits, trigger, guard):
    if not finite(trigger) or not finite(guard) or trigger + 8.5 >= guard:
        return "UNKNOWN"
    if not isinstance(exits, dict): return "UNKNOWN"
    for name, statuses in (("broker", (0,)), ("provider", (9, 15))):
        event = exits.get(name, {})
        if not isinstance(event, dict) or not finite(event.get("time")) or type(event.get("status")) is not int:
            return "UNKNOWN"
        if event["time"] < trigger: return "UNKNOWN"
        if event["time"] > trigger + 8 or event["status"] not in statuses: return "FAIL"
    return "PASS"


def provider_exit(exits, trigger, guard):
    if not finite(trigger) or not finite(guard) or trigger + 8.5 >= guard: return "UNKNOWN"
    if not isinstance(exits, dict): return "UNKNOWN"
    if "broker" in exits: return "FAIL"
    event = exits.get("provider", {})
    if not isinstance(event, dict) or not finite(event.get("time")) or type(event.get("status")) is not int:
        return "UNKNOWN"
    if event["time"] < trigger: return "UNKNOWN"
    return "PASS" if event["time"] <= trigger + 8 and event["status"] == 0 else "FAIL"


def classify(record):
    if record.get("mode") not in ("restart", "two-hosts", "provider-cycle") or record.get("observationError"):
        return "UNKNOWN"
    if any(record.get(key) is not True for key in ("authenticated", "registered", "confirmed")):
        return "UNKNOWN"
    if record["mode"] == "two-hosts":
        for key in ("distinctBrokers", "distinctProviders"):
            if record.get(key) is False: return "FAIL"
            if record.get(key) is not True: return "UNKNOWN"
    check_exit = provider_exit if record["mode"] == "provider-cycle" else chain_exit
    result = check_exit(record.get("exits"), record.get("trigger"), record.get("guardDeadline"))
    if result != "PASS": return result
    if record.get("rootAlive") is not True: return "FAIL"
    last_exit = max(event["time"] for event in record["exits"].values())
    if record["mode"] == "two-hosts":
        if record.get("otherAlive") is not True or record.get("otherConfirmed") is not True: return "FAIL"
        if not finite(record.get("otherObservedUntil")) or record["otherObservedUntil"] < last_exit:
            return "UNKNOWN"
        return "PASS"
    if not finite(record.get("restartStarted")) or record["restartStarted"] <= last_exit: return "UNKNOWN"
    freshness = ("sameBroker", "brokerAlive") if record["mode"] == "provider-cycle" else ("freshBroker",)
    if any(record.get(key) is not True for key in
           ("freshAuthenticated", "freshRegistered", "freshConfirmed", "freshProvider", *freshness)):
        return "FAIL"
    if not finite(record.get("freshStop")) or record["freshStop"] < record["restartStarted"]: return "UNKNOWN"
    return check_exit(record.get("freshExits"), record["freshStop"], record.get("freshGuard"))
