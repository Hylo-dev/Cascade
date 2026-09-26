"""Same-host broker restart and concurrent-host isolation; no launcher admission."""
import copy
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import sys

from run_broker_recovery import build, PLATFORM
from run_recovery import register_container
from run_probe import Output, native_time, EV_RECEIPT, NOTE_EXITSTATUS
from session_evidence import classify, chain_exit


class Host:
    def __init__(self, manifest, products, label):
        self.record = dict(label=label, events=[], chains=[])
        self.chains = []
        self.errors = (products / (label + ".stderr")).open("wb")
        self.process = subprocess.Popen([manifest["brokerHost"]], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=self.errors, bufsize=0,
            env=dict(os.environ, CASCADE_RECOVERY_PROVIDER_BUNDLE=manifest["provider"]))
        self.output = Output(self.process, self.record)
        self.record["pid"] = self.process.pid

    def ping(self):
        self.output.command("ping")
        return self.output.expect("ping", allow_terminal=True).get("pid") == self.process.pid and self.process.poll() is None

    def bind(self):
        if not self.chains: self.output.expect("client-ready")
        chain = Chain(self)
        self.chains.append(chain)
        self.record["chains"].append(chain.record)
        chain.bind()
        return chain

    def cleanup(self):
        try:
            if self.process.poll() is None:
                try:
                    self.output.command("quit")
                    self.process.wait(timeout=1)
                except (OSError, subprocess.TimeoutExpired):
                    self.process.kill(); self.process.wait(timeout=1)
                    self.record["forcedRootCleanup"] = True
            for chain in self.chains:
                if chain.identities:
                    chain.wait(max(i["guardDeadline"] for i in chain.identities.values()) + 1)
                chain.record["cleanupExits"] = copy.deepcopy(chain.exits)
            self.record["cleanupComplete"] = bool(self.chains) and all(
                len(c.identities) == len(c.pids) == len(c.exits) == 2 for c in self.chains)
            self.record["rootStatus"] = self.process.returncode
        finally:
            for chain in self.chains: chain.queue.close()
            self.process.stdin.close(); self.process.stdout.close(); self.errors.close()


class Chain:
    def __init__(self, host):
        self.host = host
        self.queue = select.kqueue()
        self.identities = {}
        self.pids = {}
        self.exits = {}
        self.record = {}

    def hello(self):
        self.host.output.command("hello")
        value = self.host.output.expect("hello")
        if value.get("authenticated") is not True: raise RuntimeError("unauthenticated broker")
        return dict(broker=dict(pid=value["brokerPID"], instance=value["brokerInstance"],
                                guardDeadline=value["brokerGuard"], bundlePath=value["brokerPath"]),
                    provider=value["provider"])

    def bind(self):
        self.identities = self.hello()
        self.record["identities"] = self.identities
        for name, identity in self.identities.items():
            pid = identity["pid"]
            if type(pid) is not int or pid <= 1 or pid == self.host.process.pid or pid in self.pids:
                raise RuntimeError("invalid participant PID")
            receipts = self.queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT | EV_RECEIPT,
                fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)], 1, 0)
            if len(receipts) != 1 or receipts[0].data != 0 or not receipts[0].flags & select.KQ_EV_ERROR:
                raise RuntimeError("exit registration refused")
            self.pids[pid] = name
        if self.hello() != self.identities: raise RuntimeError("incarnation changed across registration")
        self.observe(0)
        if self.exits or native_time() + 10.5 >= self.guard:
            raise RuntimeError("early exit or insufficient guard margin")
        self.record.update(authenticated=True, registered=True, confirmed=True)

    @property
    def guard(self):
        return min(i["guardDeadline"] for i in self.identities.values())

    def observe(self, timeout):
        for event in self.queue.control(None, 2, timeout):
            if (event.flags & select.KQ_EV_ERROR or not event.fflags & select.KQ_NOTE_EXIT
                    or event.ident not in self.pids):
                raise RuntimeError("invalid exit event")
            self.exits[self.pids[event.ident]] = dict(time=native_time(),
                status=int(event.data) if event.fflags & NOTE_EXITSTATUS else None)

    def wait(self, deadline):
        while len(self.exits) < len(self.pids) and native_time() < deadline:
            self.observe(max(0, deadline - native_time()))

    def stop(self):
        self.host.output.command("hold"); self.host.output.expect("hold")
        self.observe(0)
        if self.exits or native_time() + 8.5 >= self.guard:
            raise RuntimeError("unsafe stop observation window")
        trigger = native_time()
        self.host.output.command("stop-broker")
        self.host.output.expect("stop-broker", allow_terminal=True)
        self.wait(trigger + 8)
        self.record.update(trigger=trigger, exits=copy.deepcopy(self.exits))
        return trigger


def run_case(manifest, products, mode):
    record = dict(mode=mode, launcherAdmitted=False)
    hosts = []
    try:
        first = Host(manifest, products, mode + "-first"); hosts.append(first)
        old = first.bind()
        record.update(authenticated=True, registered=True, confirmed=True, guardDeadline=old.guard)
        if mode == "two-hosts":
            other = Host(manifest, products, mode + "-other"); hosts.append(other)
            other_chain = other.bind()
            record.update(distinctBrokers=old.identities["broker"]["pid"] != other_chain.identities["broker"]["pid"],
                          distinctProviders=old.identities["provider"]["pid"] != other_chain.identities["provider"]["pid"])
            # Known sharing is a negative result; never pretend an independent stop is available.
            if not record["distinctBrokers"] or not record["distinctProviders"]:
                record["verdict"] = classify(record)
                return record
        record["trigger"] = old.stop()
        record["exits"] = copy.deepcopy(old.exits)
        record["rootAlive"] = first.ping()
        if chain_exit(record["exits"], record["trigger"], old.guard) != "PASS":
            raise RuntimeError("no qualified old-chain exit; restart withheld")
        if mode == "restart":
            record["restartStarted"] = native_time()
            first.output.command("restart"); first.output.expect("restart", allow_terminal=True)
            fresh = first.bind()
            record.update(freshAuthenticated=True, freshRegistered=True, freshConfirmed=True,
                freshBroker=fresh.identities["broker"]["instance"] != old.identities["broker"]["instance"],
                freshProvider=fresh.identities["provider"]["instance"] != old.identities["provider"]["instance"],
                freshGuard=fresh.guard)
            record["freshStop"] = fresh.stop()
            record["freshExits"] = copy.deepcopy(fresh.exits)
            record["rootAlive"] = first.ping()
        else:
            record["otherConfirmed"] = other_chain.hello() == other_chain.identities
            other_chain.observe(0)
            record["otherAlive"] = other.ping() and not other_chain.exits
            record["otherObservedUntil"] = native_time()
    except (OSError, RuntimeError, ValueError, KeyError, TimeoutError, subprocess.TimeoutExpired) as error:
        record["observationError"] = repr(error)
    finally:
        record["verdict"] = classify(record)
        # Close every root before waiting: a shared provider could belong to either root.
        for host in hosts:
            if host.process.poll() is None:
                try: host.output.command("quit")
                except OSError: pass
        for host in hosts:
            try: host.cleanup()
            except (OSError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as error:
                host.record["cleanupError"] = repr(error)
        record["hosts"] = [h.record for h in hosts]
        record["cleanupComplete"] = bool(hosts) and all(
            h.record.get("cleanupComplete") is True and not h.record.get("cleanupError") for h in hosts)
        (products / ("sessions-" + mode + ".json")).write_text(json.dumps(record, indent=2) + "\n")
    return record


def run(products):
    manifest = json.loads((products / "build.json").read_text())
    for root, key in ((products / "Sources", "sourceHashes"), (PLATFORM, "runnerHashes"), (products, "binaries")):
        for relative, digest in manifest[key].items():
            if hashlib.sha256((root / relative).read_bytes()).hexdigest() != digest:
                raise RuntimeError("changed input: " + relative)
    register_container(manifest, products)
    results = []
    for mode in ("restart", "two-hosts"):
        record = run_case(manifest, products, mode); results.append(record)
        (products / "session-results.json").write_text(json.dumps(dict(cases=results, launcherAdmitted=False), indent=2) + "\n")
        print(json.dumps({k: record.get(k) for k in ("mode", "verdict", "observationError", "cleanupComplete")}), flush=True)
        if record["verdict"] == "UNKNOWN" or not record["cleanupComplete"]: return 2
    return 0 if all(r["verdict"] == "PASS" for r in results) else 1


if __name__ == "__main__":
    if sys.argv[1:] == ["--build-only"]: print(build(), flush=True)
    elif len(sys.argv) == 3 and sys.argv[1] == "--run": raise SystemExit(run(Path(sys.argv[2]).resolve()))
    else: raise SystemExit("usage: run_sessions.py --build-only | --run PRODUCTS")
