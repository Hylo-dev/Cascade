"""Describe two independent observations; no callback alone admits a launcher."""
import math


def classify(record):
    if record.get("observationError") or any(record.get(k) is not True for k in
            ("authenticated","registered","confirmed","hostAlive")): return "UNKNOWN"
    for key in ("trigger","windowEnd","guardDeadline"):
        if type(record.get(key)) not in (int,float) or not math.isfinite(record[key]): return "UNKNOWN"
    start,end = record["trigger"],record["windowEnd"]
    if end < start + 5.9 or end + 1 >= record["guardDeadline"]: return "UNKNOWN"
    notes = record.get("notifications")
    if not isinstance(notes,list) or not record.get("launchNonce"): return "UNKNOWN"
    for note in notes:
        if (note.get("nonce")!=record["launchNonce"] or type(note.get("time")) not in (int,float)
            or not math.isfinite(note["time"]) or not start<=note["time"]<=end): return "UNKNOWN"
    event = record.get("exit")
    if event is not None:
        if (type(event.get("time")) not in (int,float) or not math.isfinite(event["time"])
            or not start<=event["time"]<=end or type(event.get("status")) is not int
            or event["status"] not in (0,9,15)): return "UNKNOWN"
        return "EXIT_AND_NOTIFICATION" if notes else "EXIT_WITHOUT_NOTIFICATION"
    return "NOTIFICATION_WITHOUT_CONFIRMED_EXIT" if notes else "NO_EXIT_OR_NOTIFICATION"
