"""Finite pre-attach diagnostic model, with no OS or launcher authority.

Wire format: two-byte unsigned big-endian payload length, then exact ASCII
``1|<32 lowercase hex nonce>|bootstrap|1|advance`` followed, optionally, by
``1|<same nonce>|bootstrap|2|complete``. These are the ONLY accepted records.
Completion requires advance first. No attach, trace, or exec command exists.
Payloads are capped at 96 bytes, lifetime input at 196 bytes and two frames.
The longest incomplete frame retained is 97 bytes (header plus 95 payload).
An incoming batch's total length and its header are checked before copying
its payload. This bounds model storage, not Python allocator behavior or RSS.

begin(nonce, start_ns).observe(now_ns, data=..., eof=...) returns a new frozen
state. Caller time is an integer nanosecond counter, 0..2**63-1; the absolute
deadline is start_ns + 2 seconds (the proposed bootstrap guard, not proof of
physical exit). Supervisor/observer guards of 3/5 seconds remain unmeasured
limitations. Nothing renews the model deadline. EOF must explicitly mean
a modeled zero-byte read; empty data, EINTR and HUP are only notifications.
Earlier terminal states return themselves without examining new arguments.
Within one batch: bad arguments/time (71), deadline at equality (72), local
setup/read failure (73), protocol/truncation (71), boundary EOF (70), then
normal completion (0). A completion with a suffix, including a partial next
header, is malformed. Completion with boundary EOF predicts 70 but cannot
support abort evidence because normal_completion_seen remains true.

Evidence uses a NEW synthetic-only schema (see evaluate_synthetic_fixture).
All records, identities and even model objects are caller-supplied, hence
unauthenticated. Consistency never establishes physical exit, writer liveness,
native observer registration, or the full creation/attach/exec lifetime.
There are no imports from run/death_run/owner_run and no operational adapters.
"""

from dataclasses import dataclass, field, replace

MAX_FRAME_BYTES = 96
MAX_TOTAL_BYTES = 196
MAX_FRAMES = 2
MAX_PARTIAL_BYTES = 97
MAX_TIME_NS = 2**63 - 1
BOOTSTRAP_BUDGET_NS = 2_000_000_000
EVIDENCE_WINDOW_NS = 1_500_000_000
MAX_EVENTS = 16
SYNTHETIC_SCHEMA = "cascade.bootstrap-abort.synthetic.v1"
OBSERVER_CLOCK = "synthetic-observer-monotonic-ns"


def _integer(value, low=0, high=MAX_TIME_NS):
    return type(value) is int and low <= value <= high


def _nonce(value):
    return (type(value) is str and len(value) == 32
            and all(char in "0123456789abcdef" for char in value))


@dataclass(frozen=True)
class BootstrapAbortModel:
    """Immutable predictions. Use begin(), then retain each observe() result."""
    nonce: str
    start_ns: int
    deadline_ns: int = field(default=0, init=False)
    last_ns: int = 0
    phase: str = "waiting"
    total_bytes: int = 0
    frame_count: int = 0
    partial: bytes = b""
    predicted_exit_code: int | None = None
    reason: str = ""
    normal_completion_seen: bool = False
    eof_observed: bool = False

    def __post_init__(self):
        # Derived, never a constructor input: even direct construction cannot
        # request a longer guard. begin() remains the supported initial factory.
        if _integer(self.start_ns, high=MAX_TIME_NS - BOOTSTRAP_BUDGET_NS):
            object.__setattr__(self, "deadline_ns", self.start_ns + BOOTSTRAP_BUDGET_NS)
            if _integer(self.last_ns) and self.last_ns < self.start_ns:
                object.__setattr__(self, "last_ns", self.start_ns)

    @classmethod
    def begin(cls, nonce, start_ns):
        if not _nonce(nonce) or not _integer(start_ns, high=MAX_TIME_NS - BOOTSTRAP_BUDGET_NS):
            return cls("", 0, phase="aborted", predicted_exit_code=71, reason="invalid-initial-input")
        return cls(nonce, start_ns, last_ns=start_ns)

    def _finish(self, code, reason):
        return replace(self, phase="complete" if code == 0 else "aborted",
                       predicted_exit_code=code, reason=reason, partial=b"")

    def observe(self, now_ns, *, data=b"", eof=False, hup=False, eintr=False,
                setup_failed=False, read_failed=False):
        if self.predicted_exit_code is not None:
            return self
        if (not _integer(now_ns) or now_ns < self.last_ns or type(data) is not bytes
                or any(type(flag) is not bool for flag in (eof, hup, eintr, setup_failed, read_failed))):
            return self._finish(71, "invalid-observation")
        current = replace(self, last_ns=now_ns)
        if now_ns >= self.deadline_ns:
            return current._finish(72, "absolute-deadline")
        if setup_failed or read_failed:
            return current._finish(73, "setup-failure" if setup_failed else "read-failure")
        if len(data) > MAX_TOTAL_BYTES - self.total_bytes:
            return current._finish(71, "total-byte-limit")

        # Consume only a bounded header/payload fragment; never join the whole
        # batch to the partial buffer. Header validation precedes payload copy.
        partial = self.partial
        count = self.frame_count
        phase = self.phase
        normal_seen = self.normal_completion_seen
        offset = 0
        current = replace(current, total_bytes=self.total_bytes + len(data))
        while offset < len(data):
            if normal_seen or count >= MAX_FRAMES:
                return replace(current, normal_completion_seen=normal_seen)._finish(71, "extra-frame")
            if len(partial) < 2:
                take = min(2 - len(partial), len(data) - offset)
                partial += data[offset:offset + take]
                offset += take
                if len(partial) < 2:
                    break
            length = int.from_bytes(partial[:2], "big")
            if not 1 <= length <= MAX_FRAME_BYTES:
                return current._finish(71, "frame-length")
            take = min(length + 2 - len(partial), len(data) - offset)
            partial += data[offset:offset + take]
            offset += take
            if len(partial) < length + 2:
                break
            command = "advance" if phase == "waiting" else "complete"
            expected = f"1|{self.nonce}|bootstrap|{count + 1}|{command}".encode("ascii")
            if partial[2:] != expected:
                return current._finish(71, "record-fields")
            count += 1
            phase = "advanced" if command == "advance" else "baseline-pending"
            normal_seen = command == "complete"
            partial = b""

        current = replace(current, partial=partial, frame_count=count, phase=phase,
                          normal_completion_seen=normal_seen, eof_observed=eof)
        if eof:
            return current._finish(71, "truncated-eof") if partial else current._finish(70, "eof-boundary")
        if normal_seen:
            return current._finish(0, "normal-baseline")
        return current


@dataclass(frozen=True)
class SyntheticEvidenceResult:
    """Synthetic consistency only. Native success flags cannot be constructor inputs."""
    modelAbortEvidenceConsistent: bool
    reasons: tuple[str, ...]
    trustedBootstrapAbortObserved: bool = field(default=False, init=False)
    supervisorDeathStopsWorker: bool = field(default=False, init=False)
    nativeLauncherAdmitted: bool = field(default=False, init=False)
    nativeSuccess: bool = field(default=False, init=False)


def _shape(value, keys):
    # Exact built-in containers only; do not call arbitrary mapping protocols.
    return (type(value) is dict and len(value) == len(keys)
            and all(type(key) is str and len(key) <= 32 for key in value)
            and value.keys() == keys)


def _identity(value, role, run):
    return (_shape(value, {"run", "role", "pid", "instance"})
            and _nonce(value["run"]) and value["run"] == run
            and type(value["role"]) is str and value["role"] == role
            and _integer(value["pid"], 1, 2**31 - 1) and _nonce(value["instance"]))


def _status(value):
    if not _shape(value, {"kind", "value"}) or type(value["kind"]) is not str:
        return False
    if value["kind"] == "exit":
        return _integer(value["value"], 0, 255)
    return value["kind"] == "signal" and _integer(value["value"], 1, 127)


def _eof_decision_consistent(decision):
    """Check all fields against the two reachable EOF-only model projections.

    There can be zero frames/zero bytes or one advance/56 bytes. The second
    frame would necessarily be normal completion, which is excluded. This is
    internal consistency, never authentication of how the object was created.
    """
    return (type(decision) is BootstrapAbortModel and _nonce(decision.nonce)
            and _integer(decision.start_ns, high=MAX_TIME_NS - BOOTSTRAP_BUDGET_NS)
            and _integer(decision.deadline_ns)
            and decision.deadline_ns == decision.start_ns + BOOTSTRAP_BUDGET_NS
            and _integer(decision.last_ns, decision.start_ns, decision.deadline_ns - 1)
            and _integer(decision.frame_count, 0, 1)
            and _integer(decision.total_bytes, 0, MAX_TOTAL_BYTES)
            and decision.total_bytes == (56 if decision.frame_count == 1 else 0)
            and _integer(decision.predicted_exit_code) and decision.predicted_exit_code == 70
            and type(decision.reason) is str and decision.reason == "eof-boundary"
            and type(decision.phase) is str and decision.phase == "aborted"
            and decision.eof_observed is True and decision.normal_completion_seen is False
            and type(decision.partial) is bytes and len(decision.partial) == 0)


def evaluate_synthetic_fixture(fixture, decision=None):
    """Evaluate bounded, unauthenticated synthetic observations only.

    Exact root keys: schema=SYNTHETIC_SCHEMA, simulation='simulated', run=nonce,
    clock=OBSERVER_CLOCK, window_start_ns, identities, events. Identities has
    exactly observer/supervisor/child entries: {run, role, pid, instance}; pid
    is a synthetic integer 1..2**31-1, instance/run are 32 lowercase hex.
    All three pids and instances must be distinct; each receipt must exactly
    match its retained subject AND observer. An invented PID grants nothing.

    events is an exact list/tuple of at most 16 closed records with keys kind,
    at_ns, clock, batch (integer 0..15), observer, subject; exit/wait records
    additionally require status={kind:'exit'|'signal', value:int}; injection
    additionally requires action={kind:'signal', value:9}. Exit range
    is 0..255; signal range is 1..127. Bool-as-int/coercion is never accepted.
    Exactly one each of observer-retained, supervisor-retained, child-retained,
    injection, child-exit, model-eof-decision, supervisor-exit and
    supervisor-direct-wait is required. Unknown/adverse kinds, extra fields,
    Field names and event kinds are exact built-in strings, capped at 32
    characters before lookup; only the closed names above are accepted.
    Duplicates and conflicting receipts anywhere in the bounded input reject
    the case, including an adverse record in a successful receipt's batch.

    All timestamps are integer observer receipt times in [window_start_ns,
    window_start_ns+1.5s). All retention must strictly precede injection;
    EOF-decision/exit/direct-wait receipts must not precede injection. No order
    between child and supervisor receipts is required. Model counter values
    are never subtracted from observer receipt times. Native clock fields are
    inadmissible; no historical C0d record decoding or native normalization.
    Caller-created containers already exist: these limits bound inspection,
    not the allocation of arbitrary input before this function is called.

    decision must be the separate frozen model's internally consistent EOF-only
    outcome (70), same nonce, no normal completion: zero frames/zero bytes or
    one advance/56 bytes; start <= last < deadline == start+2s. Both supervisor
    exit and direct wait must be exactly {kind:'signal', value:9}, matching the
    closed injection action. All fields remain caller-supplied/unauthenticated.
    See test fixture() for a minimal complete synthetic record example.
    """
    def reject(reason):
        return SyntheticEvidenceResult(False, (reason,))

    if not _shape(fixture, {"schema", "simulation", "run", "clock", "window_start_ns", "identities", "events"}):
        return reject("fixture-shape")
    if (type(fixture["schema"]) is not str or fixture["schema"] != SYNTHETIC_SCHEMA
            or type(fixture["simulation"]) is not str or fixture["simulation"] != "simulated"
            or type(fixture["clock"]) is not str or fixture["clock"] != OBSERVER_CLOCK
            or not _nonce(fixture["run"])):
        return reject("synthetic-label-or-clock")
    start = fixture["window_start_ns"]
    if not _integer(start, high=MAX_TIME_NS - EVIDENCE_WINDOW_NS):
        return reject("window-start")
    identities = fixture["identities"]
    roles = {"observer", "supervisor", "child"}
    if not _shape(identities, roles) or any(not _identity(identities[role], role, fixture["run"]) for role in roles):
        return reject("retained-identity-shape")
    if (len({identities[role]["pid"] for role in roles}) != 3
            or len({identities[role]["instance"] for role in roles}) != 3):
        return reject("recycled-or-swapped-identity")
    if not _eof_decision_consistent(decision) or decision.nonce != fixture["run"]:
        return reject("missing-eof-only-model-decision")
    events = fixture["events"]
    if type(events) not in (list, tuple) or not 1 <= len(events) <= MAX_EVENTS:
        return reject("event-count-or-container")
    subjects = {"observer-retained": "observer", "supervisor-retained": "supervisor",
                "child-retained": "child", "injection": "supervisor", "child-exit": "child",
                "model-eof-decision": "child", "supervisor-exit": "supervisor",
                "supervisor-direct-wait": "supervisor"}
    status_kinds = {"child-exit", "supervisor-exit", "supervisor-direct-wait"}
    retained = {}
    for event in events:
        if (type(event) is not dict or len(event) not in (6, 7)
                or any(type(key) is not str or len(key) > 32 for key in event)
                or type(event.get("kind")) is not str or len(event["kind"]) > 32):
            return reject("event-shape")
        kind = event["kind"]
        if kind not in subjects:
            return reject("unknown-or-adverse-event")
        keys = {"kind", "at_ns", "clock", "batch", "observer", "subject"}
        if kind in status_kinds:
            keys.add("status")
        if kind == "injection":
            keys.add("action")
        if not _shape(event, keys) or kind in retained:
            return reject("duplicate-or-malformed-event")
        role = subjects[kind]
        if (not _identity(event["observer"], "observer", fixture["run"])
                or not _identity(event["subject"], role, fixture["run"])
                or event["observer"] != identities["observer"] or event["subject"] != identities[role]):
            return reject("receipt-identity-mismatch")
        if (type(event["clock"]) is not str or event["clock"] != OBSERVER_CLOCK
                or not _integer(event["at_ns"], start, start + EVIDENCE_WINDOW_NS - 1)
                or not _integer(event["batch"], 0, MAX_EVENTS - 1)):
            return reject("receipt-clock-time-or-batch")
        if kind in status_kinds and not _status(event["status"]):
            return reject("invalid-exit-status")
        if kind == "injection" and (not _status(event["action"])
                                    or event["action"] != {"kind": "signal", "value": 9}):
            return reject("invalid-injection-action")
        retained[kind] = event
    if retained.keys() != subjects.keys():
        return reject("missing-required-observation")
    injection = retained["injection"]["at_ns"]
    if any(retained[kind]["at_ns"] >= injection for kind in
           ("observer-retained", "supervisor-retained", "child-retained")):
        return reject("identity-not-retained-before-injection")
    if any(retained[kind]["at_ns"] < injection for kind in
           ("child-exit", "model-eof-decision", "supervisor-exit", "supervisor-direct-wait")):
        return reject("receipt-precedes-injection")
    if retained["child-exit"]["status"] != {"kind": "exit", "value": 70}:
        return reject("child-not-exclusive-channel-loss-exit")
    if retained["supervisor-exit"]["status"] != retained["supervisor-direct-wait"]["status"]:
        return reject("supervisor-wait-disagreement")
    if retained["supervisor-exit"]["status"] != {"kind": "signal", "value": 9}:
        return reject("supervisor-not-injected-signal9-death")
    return SyntheticEvidenceResult(True, ())
