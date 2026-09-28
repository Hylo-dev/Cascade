"""Build and measure fixed signed XPC chains. No production admission or PID killing."""
import copy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import select
import subprocess
import sys
import tempfile
import time

from chain_evidence import classify

SOURCE = Path(__file__).resolve().parent
PREVIOUS = SOURCE.parent / "XPCLifetime"
sys.path.append(str(PREVIOUS))
from run_probe import Output, native_time, EV_RECEIPT, NOTE_EXITSTATUS, SIGNER

ROOT_ID = "hylo.Cascade.XPCBrokerProbe"


def build(layout):
    base = Path.home() / "Library/Developer/Xcode/DerivedData/CascadeXPCBrokerProbe"
    base.mkdir(parents=True, exist_ok=True)
    products = Path(tempfile.mkdtemp(prefix=layout+"-", dir=base))
    app = products / "XPCBrokerProbe.app"
    environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
    entitlement = products / "Service.entitlements"
    entitlement.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
    commands, binaries = [], []
    bundles = []
    for chain in "AB":
        broker = app / ("Contents/XPCServices/Broker" + chain + ".xpc")
        worker_parent = broker if layout == "nested" else app
        worker = worker_parent / ("Contents/XPCServices/Worker" + chain + ".xpc")
        bundles.extend([(worker, "Worker"+chain, 2, chain), (broker, "Broker"+chain, 1, chain)])
    bundles.append((app, "XPCBrokerProbe", 0, "A"))
    with (products / "build.log").open("w") as log:
        def command(args):
            commands.append(args)
            subprocess.run(args,env=environment,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
        for bundle, name, role, chain in bundles:
            (bundle / "Contents/MacOS").mkdir(parents=True)
            identifier = ROOT_ID + ("."+name if role else "")
            info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=name,
                        CFBundlePackageType="XPC!" if role else "APPL",
                        CFBundleVersion="1",CFBundleShortVersionString="1.0",LSMinimumSystemVersion="14.0")
            if role: info["XPCService"]={"ServiceType":"Application"}
            else: info["LSUIElement"]=True
            plist=bundle/"Contents/Info.plist"
            plist.write_bytes(plistlib.dumps(info))
            binary=bundle/"Contents/MacOS"/name
            command(["xcrun","clang","-Wall","-Wextra","-Werror","-O2","-fblocks",
                     "-mmacosx-version-min=14.0",f"-DROLE={role}",f'-DCHAIN="{chain}"',
                     f'-DPROBE_SIGNER_HASH="{SIGNER}"',str(SOURCE/"Probe.c"),
                     "-framework","Security","-framework","CoreFoundation",
                     "-Wl,-sectcreate,__TEXT,__info_plist,"+str(plist),"-o",str(binary)])
            command(["codesign","--force","--timestamp=none","--options","runtime","--sign",SIGNER,
                     *(["--entitlements",str(entitlement)] if role else []),str(bundle)])
            command(["codesign","--verify","--strict","--deep","-R",
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf = H"{SIGNER}"',str(bundle)])
            command(["codesign","-d","--entitlements","-","--xml",str(bundle)])
            binaries.append(binary)
        command(["sw_vers"])
        command(["xcrun","--show-sdk-version"])
        command(["xcrun","clang","--version"])
    files=[p for p in SOURCE.iterdir() if p.suffix in {".py",".c"}]
    files.extend([PREVIOUS/"run_probe.py",PREVIOUS/"evidence.py"])
    (products/"build.json").write_text(json.dumps(dict(layout=layout,commands=commands,signer=SIGNER,
        sourceHashes={str(p.relative_to(SOURCE.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
        binaries={str(p.relative_to(products)):hashlib.sha256(p.read_bytes()).hexdigest() for p in binaries}),indent=2)+"\n")
    return products


def run_case(products, mode):
    record=dict(mode=mode,events=[],nodes={},guards={},exits={},windowComplete=False)
    host_dies=mode in {"host-normal","host-crash","blocked-host-crash"}
    queue=select.kqueue()
    registered={}
    process=None
    with (products/(mode+".stderr")).open("wb") as errors:
        process=subprocess.Popen([str(products/"XPCBrokerProbe.app/Contents/MacOS/XPCBrokerProbe")],
                                 stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=errors,bufsize=0)
        output=Output(process,record)
        record["hostPID"]=process.pid

        def observe(timeout):
            for event in queue.control(None,4,timeout):
                if event.flags & select.KQ_EV_ERROR: raise OSError(event.data,"process observation failed")
                if event.ident not in registered or not event.fflags & select.KQ_NOTE_EXIT:
                    raise RuntimeError("unexpected process event")
                record["exits"][registered[event.ident]]=dict(time=native_time(),
                    status=int(event.data) if event.fflags & NOTE_EXITSTATUS else None)

        def identify(chain, operation, allow_terminal=False):
            output.command(chain+" "+operation)
            reply=output.expect(chain+"-"+operation,allow_terminal=allow_terminal)
            if reply.get("authenticated") is not True or reply.get("workerAuthenticated") is not True:
                raise RuntimeError("unauthenticated chain")
            return {chain+"."+role:reply[role] for role in ("broker","worker")}

        try:
            output.expect("client-ready")
            for chain in "AB":
                nodes=identify(chain,"hello")
                for name, identity in nodes.items():
                    pid=identity["pid"]
                    if type(pid) is not int or pid<=1 or pid==process.pid or pid in registered:
                        raise RuntimeError("invalid/duplicate fixture PID")
                    receipt=queue.control([select.kevent(pid,filter=select.KQ_FILTER_PROC,
                        flags=select.KQ_EV_ADD|select.KQ_EV_ONESHOT|EV_RECEIPT,
                        fflags=select.KQ_NOTE_EXIT|NOTE_EXITSTATUS)],1,0)
                    if len(receipt)!=1 or receipt[0].data!=0 or not receipt[0].flags & select.KQ_EV_ERROR:
                        raise RuntimeError("exit observation registration refused")
                    registered[pid]=name
                    record["nodes"][name]=identity
                    record["guards"][name]=identity["guardDeadline"]
                operation="hold" if chain=="A" or host_dies else "ping"
                if chain=="A" and mode.startswith("blocked-"):
                    operation="hold-both"
                if identify(chain,operation)!=nodes: raise RuntimeError("chain incarnation changed")
                if operation=="hold-both": record["blockedControlConfirmed"]=True
            record.update(authenticated=True,registered=True,sameInstances=True)
            observe(0)
            if record["exits"] or any(native_time()+2.5>=g for g in record["guards"].values()):
                raise RuntimeError("early exit or insufficient guard margin")
            record["trigger"]=native_time()
            command={"stop":"A exit","broker-crash":"A crash","host-normal":"quit","host-crash":"crash",
                     "blocked-stop":"A exit","blocked-cancel":"A cancel","blocked-host-crash":"crash"}[mode]
            output.command(command)
            marker=output.expect(command if host_dies else "action-sent",allow_terminal=True)
            record.update(actionConfirmed=True,actionTime=marker["time"])
            end=time.monotonic()+max(0,record["trigger"]+2-native_time())
            while time.monotonic()<end: observe(max(0,end-time.monotonic()))
            record.update(windowComplete=True,hostStatus=process.poll())
            if not host_dies:
                # Prove B remains the same responsive chain, not just a PID that exists.
                survivor=identify("B","ping",allow_terminal=True)
                record["survivorConfirmed"]=(survivor=={k:v for k,v in record["nodes"].items() if k.startswith("B.")})
                observe(0)
            record["verdict"]=classify(record)
        except (OSError,ValueError,KeyError,RuntimeError,TimeoutError) as error:
            record.update(observationError=repr(error),verdict="UNKNOWN")
        finally:
            measurement=copy.deepcopy(record["exits"])
            if process.poll() is None:
                try:
                    output.command("quit"); process.wait(timeout=1)
                except (OSError,subprocess.TimeoutExpired):
                    process.kill(); process.wait(timeout=1)
                    record["hostCleanupForced"]=True
            until=time.monotonic()+max(0,max(record["guards"].values(),default=native_time())-native_time())+1
            try:
                while len(record["exits"])<len(registered) and time.monotonic()<until:
                    observe(min(.2,max(0,until-time.monotonic())))
            except (OSError,RuntimeError) as error:
                record["cleanupError"]=repr(error)
            record["cleanup"]=dict(hostStatus=process.returncode,exits=copy.deepcopy(record["exits"]),
                allKnownExited=bool(registered) and len(record["exits"])==len(registered),
                allFourTracked=len(registered)==4)
            record["exits"]=measurement
            queue.close(); process.stdin.close(); process.stdout.close()
    (products/(mode+".json")).write_text(json.dumps(record,indent=2)+"\n")
    return record


def main():
    if len(sys.argv)==3 and sys.argv[1]=="--build-only" and sys.argv[2] in {"nested","siblings"}:
        print(build(sys.argv[2]),flush=True); return 0
    if len(sys.argv)!=3 or sys.argv[1] not in {"--run","--run-blocked"}:
        raise SystemExit("usage: run_broker_probe.py --build-only nested|siblings | --run[-blocked] PRODUCTS")
    products=Path(sys.argv[2]).resolve()
    manifest=json.loads((products/"build.json").read_text())
    for relative,digest in manifest["binaries"].items():
        if hashlib.sha256((products/relative).read_bytes()).hexdigest()!=digest:
            raise RuntimeError("binary changed: "+relative)
    for relative,digest in manifest["sourceHashes"].items():
        if hashlib.sha256((SOURCE.parent/relative).read_bytes()).hexdigest()!=digest:
            raise RuntimeError("source changed: "+relative)
    records=[]
    modes=("blocked-stop","blocked-cancel","blocked-host-crash") if sys.argv[1]=="--run-blocked" else (
        "stop","broker-crash","host-normal","host-crash")
    for mode in modes:
        record=run_case(products,mode); records.append(record)
        (products/"results.json").write_text(json.dumps(dict(schema="xpc-broker-probe-v1",
            layout=manifest["layout"],launcherAdmitted=False,cases=records),indent=2)+"\n")
        print(json.dumps(dict(mode=mode,verdict=record["verdict"],error=record.get("observationError"),
                             cleanup=record["cleanup"])),flush=True)
        if record["verdict"]=="UNKNOWN" or not record["cleanup"]["allKnownExited"]: return 2
    return 0 if all(r["verdict"]=="PASS" for r in records) else 1


if __name__=="__main__": raise SystemExit(main())
