"""Signed external-provider composition probe, bounded by independent native guards."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import select
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parent
PLATFORM = SOURCE.parent
# Load the differently named classifiers without polluting run_probe's evidence import.
spec = importlib.util.spec_from_file_location("broker_recovery_evidence", SOURCE/"evidence.py")
evidence = importlib.util.module_from_spec(spec); spec.loader.exec_module(evidence)
sys.path.insert(0, str(PLATFORM/"Recovery"))
from run_recovery import build as build_provider
from run_probe import Output, native_time, EV_RECEIPT, NOTE_EXITSTATUS, SIGNER


def build(compilation_conditions=()):
    products = build_provider(broker_provider=True)
    manifest = json.loads((products/"build.json").read_text())
    app = products/"BrokerRecovery.app"
    service = app/"Contents/XPCServices/DiscoveryBroker.xpc"
    sources = products/"Sources"
    shutil.copytree(SOURCE, sources/"BrokerRecovery", ignore=shutil.ignore_patterns("__pycache__"))
    environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
    with (products/"broker-build.log").open("w") as log:
        def command(args):
            manifest["commands"].append(args)
            subprocess.run(args, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
        for bundle, name, identifier, broker in [
            (service,"DiscoveryBroker","hylo.Cascade.AddonProbe.DiscoveryBroker",True),
            (app,"BrokerRecovery","hylo.Cascade.AddonProbe",False)]:
            (bundle/"Contents/MacOS").mkdir(parents=True)
            info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=name,
                        CFBundlePackageType="XPC!" if broker else "APPL", CFBundleVersion="1",
                        CFBundleShortVersionString="1.0", LSMinimumSystemVersion="14.0")
            if broker: info["XPCService"] = dict(ServiceType="Application",RunLoopType="NSRunLoop")
            else:
                info["LSUIElement"] = True
                (bundle/"Contents/Extensions").mkdir()
                shutil.copyfile(sources/"Host/Probe.appextensionpoint",bundle/"Contents/Extensions/Probe.appextensionpoint")
            plist = bundle/"Contents/Info.plist"; plist.write_bytes(plistlib.dumps(info))
            binary = bundle/"Contents/MacOS"/name
            command(["xcrun","swiftc","-parse-as-library","-swift-version","5","-O",
                     "-target","arm64-apple-macos14.0","-D","RECOVERY_PROBE",*(["-D","BROKER"] if broker else []),
                     *[arg for condition in compilation_conditions for arg in ("-D",condition)],
                     str(sources/"BrokerRecovery/Probe.swift"),str(sources/"Shared/ProbeMessage.swift"),
                     "-framework","AppKit","-framework","ExtensionFoundation",
                     "-Xlinker","-sectcreate","-Xlinker","__TEXT","-Xlinker","__info_plist",
                     "-Xlinker",str(plist),"-o",str(binary)])
            command(["codesign","--force","--timestamp=none","--options","runtime","--sign",SIGNER,
                     *(["--entitlements",str(sources/"Provider/Provider.entitlements")] if broker else []),str(bundle)])
            command(["codesign","--verify","--strict","--deep","-R",
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf = H"{SIGNER}"',str(bundle)])
            command(["codesign","-d","--entitlements","-","--xml",str(bundle)])
            manifest["binaries"][str(binary.relative_to(products))]=hashlib.sha256(binary.read_bytes()).hexdigest()
    manifest["brokerHost"] = str(app/"Contents/MacOS/BrokerRecovery")
    manifest["sourceHashes"]={str(p.relative_to(sources)):hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in sources.rglob("*") if p.is_file()}
    for p in SOURCE.glob("*.py"):
        manifest["runnerHashes"][str(p.relative_to(PLATFORM))]=hashlib.sha256(p.read_bytes()).hexdigest()
    (products/"build.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return products


def run_case(manifest, products, mode):
    record = dict(mode=mode, events=[], exits={}, launcherAdmitted=False)
    queue = select.kqueue(); identities={}; pids={}; cleanup_exits={}
    errors = (products/("broker-"+mode+".stderr")).open("wb")
    process = subprocess.Popen([manifest["brokerHost"]],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
        stderr=errors,bufsize=0,env=dict(os.environ,CASCADE_RECOVERY_PROVIDER_BUNDLE=manifest["provider"]))
    output = Output(process,record); record["rootPID"]=process.pid

    def observe(timeout):
        for event in queue.control(None,2,timeout):
            if event.flags & select.KQ_EV_ERROR or not event.fflags & select.KQ_NOTE_EXIT or event.ident not in pids:
                raise RuntimeError("invalid exit event")
            cleanup_exits[pids[event.ident]]=dict(time=native_time(),status=int(event.data) if event.fflags & NOTE_EXITSTATUS else None)

    def wait_exits(deadline):
        while len(cleanup_exits)<len(pids) and native_time()<deadline:
            observe(max(0,deadline-native_time()))

    try:
        output.expect("client-ready"); output.command("hello"); hello=output.expect("hello")
        if hello.get("authenticated") is not True: raise RuntimeError("unauthenticated broker")
        identities=dict(broker=dict(pid=hello["brokerPID"],instance=hello["brokerInstance"],
                                   guardDeadline=hello["brokerGuard"],bundlePath=hello["brokerPath"]),
                        provider=hello["provider"])
        for name,identity in identities.items():
            pid=identity["pid"]
            if type(pid) is not int or pid<=1 or pid==process.pid or pid in pids: raise RuntimeError("invalid participant PID")
            receipts=queue.control([select.kevent(pid,filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD|select.KQ_EV_ONESHOT|EV_RECEIPT,
                fflags=select.KQ_NOTE_EXIT|NOTE_EXITSTATUS)],1,0)
            if len(receipts)!=1 or receipts[0].data!=0 or not receipts[0].flags & select.KQ_EV_ERROR:
                raise RuntimeError("exit registration refused")
            pids[pid]=name
        record.update(authenticated=True,registered=True,identities=identities,
                      brokerGuard=identities["broker"]["guardDeadline"],providerGuard=identities["provider"]["guardDeadline"])
        output.command("hold"); second=output.expect("hold")
        record["confirmed"]=(second.get("authenticated") is True and
            all(second[k]==hello[k] for k in ("brokerPID","brokerInstance","brokerGuard","brokerPath","provider")))
        if not record["confirmed"]: raise RuntimeError("participant incarnation changed")
        output.command("invalidate"); output.expect("invalidate")
        observe(2); output.command("ping"); output.expect("ping"); observe(0)
        record["survivedInvalidation"]=not cleanup_exits and process.poll() is None
        if not record["survivedInvalidation"]: raise RuntimeError("participants already exited")
        if native_time()+8.5>=min(record["brokerGuard"],record["providerGuard"]): raise RuntimeError("insufficient guard margin")
        record["trigger"]=native_time()
        command = {"broker":"stop-broker","normal":"quit","crash":"crash"}[mode]
        output.command(command); output.expect(command,allow_terminal=True)
        if mode!="broker":
            process.wait(timeout=1); record.update(rootStatus=process.returncode,rootExitObserved=native_time())
        wait_exits(record["trigger"]+8)
        record["exits"]={k:v.copy() for k,v in cleanup_exits.items()}
        if mode=="broker":
            output.command("ping"); ping=output.expect("ping",allow_terminal=True)
            record["rootAlive"]=process.poll() is None and ping.get("pid")==process.pid
    except (OSError,RuntimeError,ValueError,KeyError,TimeoutError,subprocess.TimeoutExpired) as error:
        record["observationError"]=repr(error)
    finally:
        record["verdict"]=evidence.classify(record)
        try:
            if process.poll() is None:
                try: output.command("quit"); process.wait(timeout=1)
                except (OSError,subprocess.TimeoutExpired):
                    process.kill();process.wait(timeout=1);record["forcedRootCleanup"]=True
            if identities: wait_exits(max(i["guardDeadline"] for i in identities.values())+1)
            record["cleanup"]=dict(rootStatus=process.returncode,exits=cleanup_exits,
                complete=len(pids)==2 and len(cleanup_exits)==2)
        except (OSError,RuntimeError,subprocess.TimeoutExpired) as error: record["cleanupError"]=repr(error)
        queue.close();process.stdin.close();process.stdout.close();errors.close()
    (products/("broker-"+mode+".json")).write_text(json.dumps(record,indent=2)+"\n")
    return record


def run(products):
    manifest=json.loads((products/"build.json").read_text())
    for root,key in [(products/"Sources","sourceHashes"),(PLATFORM,"runnerHashes"),(products,"binaries")]:
        for relative,digest in manifest[key].items():
            if hashlib.sha256((root/relative).read_bytes()).hexdigest()!=digest: raise RuntimeError("changed input: "+relative)
    # Limit registration changes to fixture copies with the pinned identity and signer.
    derived=Path.home()/"Library/Developer/Xcode/DerivedData"
    candidates=list((derived/"CascadeAddonRecoveryProbe").glob("probe-*/Build/Build/Products/Debug/CascadeAddonProbeContainer.app"))
    candidates += [derived/f"CascadeAddonPlatform/Build/Products/{c}/CascadeAddonProbeContainer.app" for c in ("Debug","Release")]
    removed=[]
    for candidate in candidates:
        if not candidate.exists() or candidate.resolve()==Path(manifest["container"]).resolve(): continue
        subprocess.run(["codesign","--verify","--strict","--deep","-R",
            f'=anchor apple generic and identifier "hylo.Cascade.AddonProbeContainer" and certificate leaf = H"{SIGNER}"',str(candidate)],
            check=True,timeout=10)
        registration=subprocess.run(["/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                        "-u",str(candidate)],capture_output=True,text=True,timeout=10)
        removed.append(dict(path=str(candidate),status=registration.returncode,
                            stdout=registration.stdout,stderr=registration.stderr))
        if registration.returncode and ": -10814" not in registration.stdout + registration.stderr:
            registration.check_returncode()
    (products/"broker-registration.json").write_text(json.dumps(dict(removed=removed,active=manifest["container"]),indent=2)+"\n")
    subprocess.run(["open","-g",manifest["container"]],check=True,timeout=10)
    results=[]
    for mode in ("broker","normal","crash"):
        record=run_case(manifest,products,mode);results.append(record)
        (products/"broker-results.json").write_text(json.dumps(dict(cases=results,launcherAdmitted=False),indent=2)+"\n")
        print(json.dumps({k:record.get(k) for k in ("mode","verdict","observationError","cleanup")}),flush=True)
        if record["verdict"]=="UNKNOWN" or not record.get("cleanup",{}).get("complete"): return 2
    return 0 if all(r["verdict"]=="PASS" for r in results) else 1


if __name__=="__main__":
    if sys.argv[1:]==["--build-only"]: print(build(),flush=True)
    elif len(sys.argv)==3 and sys.argv[1]=="--run": raise SystemExit(run(Path(sys.argv[2]).resolve()))
    else: raise SystemExit("usage: run_broker_recovery.py --build-only | --run PRODUCTS")
