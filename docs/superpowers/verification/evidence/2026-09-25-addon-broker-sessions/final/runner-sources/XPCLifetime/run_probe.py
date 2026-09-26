"""Build/run a fixed, signed XPC fixture. No product registration or PID-based killing."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import select
import signal
import subprocess
import sys
import tempfile
import time

from evidence import classify

SOURCE = Path(__file__).resolve().parent
HOST_ID = "hylo.Cascade.XPCLifetimeProbe"
SIGNER = "4A857D842A5406C2D3071776FDE7B27B3098FE63"
NOTE_EXITSTATUS = 0x04000000  # Public sys/event.h; Python does not expose this flag.
EV_RECEIPT = 0x0040  # Public sys/event.h; also absent from Python's select module.


def native_time():
    return time.clock_gettime(time.CLOCK_MONOTONIC)


def build():
    base = Path.home() / "Library/Developer/Xcode/DerivedData/CascadeXPCLifetimeProbe"
    base.mkdir(parents=True, exist_ok=True)
    products = Path(tempfile.mkdtemp(prefix="probe-", dir=base))
    host = products / "XPCLifetimeProbe.app"
    service = host / "Contents/XPCServices/LifetimeService.xpc"
    environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
    entitlement = products / "Service.entitlements"
    entitlement.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
    commands = []
    with (products / "build.log").open("w") as log:
        def command(args):
            commands.append(args)
            subprocess.run(args, env=environment, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=60)
        for bundle, identifier, name, is_service in [
                (service, HOST_ID + ".Service", "LifetimeService", True),
                (host, HOST_ID, "XPCLifetimeProbe", False)]:
            (bundle / "Contents/MacOS").mkdir(parents=True)
            info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=name,
                        CFBundlePackageType="XPC!" if is_service else "APPL",
                        CFBundleVersion="1", CFBundleShortVersionString="1.0",
                        LSMinimumSystemVersion="14.0")
            if is_service:
                info["XPCService"] = {"ServiceType": "Application"}
            else:
                info["LSUIElement"] = True
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            command(["xcrun", "clang", "-Wall", "-Wextra", "-Werror", "-O2", "-fblocks",
                     "-mmacosx-version-min=14.0", '-DPROBE_SIGNER_HASH="' + SIGNER + '"',
                     *(["-DPROBE_SERVICE"] if is_service else []), str(SOURCE / "Probe.c"),
                     "-framework", "Security", "-framework", "CoreFoundation",
                     "-Wl,-sectcreate,__TEXT,__info_plist," + str(bundle / "Contents/Info.plist"),
                     "-o", str(bundle / "Contents/MacOS" / name)])
            command(["codesign", "--force", "--timestamp=none", "--options", "runtime",
                     "--sign", SIGNER, *(["--entitlements", str(entitlement)] if is_service else []),
                     str(bundle)])
            command(["codesign", "--verify", "--strict", "--deep", "-R",
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf = H"{SIGNER}"',
                     str(bundle)])
            command(["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)])
        command(["sw_vers"])
        command(["xcrun", "--show-sdk-version"])
        command(["xcrun", "clang", "--version"])
    (products / "build.json").write_text(json.dumps({
        "commands": commands, "sourceHashes": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in SOURCE.iterdir() if p.is_file()}, "signer": SIGNER,
        "binaries": {str(p.relative_to(products)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [host / "Contents/MacOS/XPCLifetimeProbe", service / "Contents/MacOS/LifetimeService"]}
    }, indent=2) + "\n")
    return products


class Output:
    def __init__(self, process, record):
        self.process, self.record, self.pending = process, record, b""

    def command(self, command):
        self.process.stdin.write((command + "\n").encode())
        self.process.stdin.flush()

    def expect(self, name, allow_terminal=False, timeout=2):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if b"\n" not in self.pending:
                ready, _, _ = select.select([self.process.stdout], [], [], max(0, deadline-time.monotonic()))
                if not ready:
                    break
                data = os.read(self.process.stdout.fileno(), 4096)
                if not data:
                    raise RuntimeError("client ended before " + name)
                self.pending += data
                if len(self.pending) > 16384:
                    raise RuntimeError("fixture output exceeded bound")
                continue
            line, self.pending = self.pending.split(b"\n", 1)
            event = json.loads(line)
            self.record["events"].append(event)
            if event.get("event") == name:
                return event
            if event.get("event", "").endswith("error"):
                raise RuntimeError(str(event))
            if event.get("event") in {"connection-invalid", "connection-interrupted"} and not allow_terminal:
                raise RuntimeError(str(event))
        raise TimeoutError("waiting for " + name)


def run_case(products, mode):
    record = {"mode": mode, "events": [], "registered": False, "serviceExit": None,
              "serviceStatus": None, "windowComplete": False}
    executable = products / "XPCLifetimeProbe.app/Contents/MacOS/XPCLifetimeProbe"
    queue = select.kqueue()
    service_pid = None
    with (products / (mode + ".stderr")).open("wb") as errors:
        process = subprocess.Popen([str(executable)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, bufsize=0)
        output = Output(process, record)
        record["hostPID"] = process.pid

        def observe(timeout):
            for event in queue.control(None, 1, timeout):
                if event.flags & select.KQ_EV_ERROR:
                    raise OSError(event.data, "process event failed")
                if event.ident != service_pid or not event.fflags & select.KQ_NOTE_EXIT:
                    raise RuntimeError("unexpected process event")
                record["serviceExit"] = native_time()
                record["serviceStatus"] = int(event.data) if event.fflags & NOTE_EXITSTATUS else None

        try:
            output.expect("client-ready")
            output.command("hello")
            hello = output.expect("hello")
            service_pid = hello["pid"]
            if type(service_pid) is not int or service_pid <= 1 or service_pid == process.pid:
                raise RuntimeError("invalid synthetic peer identity")
            record.update(servicePID=service_pid, authenticated=hello.get("authenticated") is True,
                          guardDeadline=hello["guardDeadline"], instance=hello["instance"])
            receipt = queue.control([select.kevent(service_pid, filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT | EV_RECEIPT,
                fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)], 1, 0)
            if len(receipt) != 1 or receipt[0].data != 0 or not receipt[0].flags & select.KQ_EV_ERROR:
                raise RuntimeError("exit observation registration refused")
            record["registered"] = True
            # A second authenticated reply binds registration to the same still-live fixture.
            output.command("hello" if mode == "cooperate" else "hold")
            confirmed = output.expect("hello" if mode == "cooperate" else "hold")
            record["sameInstance"] = (confirmed.get("authenticated") is True and
                all(confirmed[key] == hello[key] for key in ("pid", "instance", "guardDeadline")))
            if not record["sameInstance"] or native_time() + 2.5 >= hello["guardDeadline"]:
                raise RuntimeError("instance changed or insufficient guard margin")
            observe(0)
            if record["serviceExit"] is not None:
                raise RuntimeError("service exited before requested action")
            record["trigger"] = native_time()
            output.command({"cooperate": "cooperate", "cancel": "cancel",
                            "normal": "quit", "crash": "crash"}[mode])
            action = output.expect({"cooperate": "cooperate-sent", "cancel": "cancelled",
                                    "normal": "quitting", "crash": "crashing"}[mode], allow_terminal=True)
            record["actionConfirmed"] = True
            record["actionTime"] = action["time"]
            if mode == "cancel":
                record["trigger"] = action["time"]
            end = time.monotonic() + 2
            while time.monotonic() < end:
                observe(max(0, end - time.monotonic()))
            record.update(windowComplete=True, hostStatus=process.poll(),
                          hostAliveAtWindowEnd=process.poll() is None)
            record["verdict"] = classify(record)
            # Freeze the measurement before cleanup can create a later exit.
            record["measurement"] = {key: record[key] for key in ("serviceExit", "serviceStatus")}
        except (OSError, ValueError, KeyError, RuntimeError, TimeoutError) as error:
            record["observationError"] = repr(error)
            record["verdict"] = "UNKNOWN"
        finally:
            if process.poll() is None:
                try:
                    output.command("quit")
                    process.wait(timeout=1)
                except (OSError, subprocess.TimeoutExpired):
                    # Only our retained direct child, never the service PID or a process group.
                    process.kill()
                    process.wait(timeout=1)
                    record["hostCleanupForced"] = True
            if record["registered"] and record["serviceExit"] is None:
                until = time.monotonic() + max(0, record["guardDeadline"] - native_time()) + 1
                try:
                    while record["serviceExit"] is None and time.monotonic() < until:
                        observe(min(.2, max(0, until - time.monotonic())))
                except (OSError, RuntimeError) as error:
                    record["cleanupError"] = repr(error)
            record["cleanup"] = dict(hostStatus=process.returncode,
                serviceExitObserved=record["serviceExit"] is not None,
                serviceExit=record["serviceExit"], serviceStatus=record["serviceStatus"])
            if "measurement" in record:
                record.update(record["measurement"])
            queue.close()
            process.stdin.close()
            process.stdout.close()
    (products / (mode + ".json")).write_text(json.dumps(record, indent=2) + "\n")
    return record


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--run":
        products = Path(sys.argv[2]).resolve()
    elif len(sys.argv) == 2 and sys.argv[1] == "--build-only":
        print(build(), flush=True)
        return 0
    else:
        raise SystemExit("usage: run_probe.py --build-only | --run PRODUCTS")
    manifest = json.loads((products / "build.json").read_text())
    for relative, digest in manifest["binaries"].items():
        if hashlib.sha256((products / relative).read_bytes()).hexdigest() != digest:
            raise RuntimeError("fixture binary changed: " + relative)
    records = []
    for mode in ["cooperate", "cancel", "normal", "crash"]:
        record = run_case(products, mode)
        records.append(record)
        print(json.dumps({"mode": mode, "verdict": record["verdict"], "cleanup": record["cleanup"]}), flush=True)
        (products / "results.json").write_text(json.dumps({
            "schema": "xpc-lifetime-probe-v1", "launcherAdmitted": False, "cases": records
        }, indent=2) + "\n")
        if record["verdict"] == "UNKNOWN" or not record["cleanup"]["serviceExitObserved"]:
            return 2
    return 0 if all(r["verdict"] == "PASS" for r in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
