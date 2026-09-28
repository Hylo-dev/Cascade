"""Bounded signed external-extension recovery. No production admission or PID killing."""
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time

from recovery_evidence import classify

SOURCE = Path(__file__).resolve().parent
PLATFORM = SOURCE.parent
sys.path.append(str(PLATFORM/"XPCLifetime"))
from run_probe import Output, native_time, EV_RECEIPT, NOTE_EXITSTATUS, SIGNER


def build():
    base = Path.home()/"Library/Developer/Xcode/DerivedData/CascadeAddonRecoveryProbe"
    base.mkdir(parents=True, exist_ok=True)
    products = Path(tempfile.mkdtemp(prefix="probe-",dir=base))
    sources = products/"Sources"
    for directory in ("Host","Provider","Shared","Container","AddonPlatform.xcodeproj"):
        shutil.copytree(PLATFORM/directory,sources/directory,
                        ignore=shutil.ignore_patterns("xcuserdata","*.xcuserstate"))
    environment = dict(os.environ,DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
    commands=[]
    with (products/"build.log").open("w") as log:
        def command(args,timeout=90):
            commands.append(args)
            subprocess.run(args,env=environment,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=timeout)
        command(["xcrun","xcodebuild","-project",str(sources/"AddonPlatform.xcodeproj"),
                 "-scheme","AddonPlatform","-configuration","Debug","-derivedDataPath",str(products/"Build"),
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG RECOVERY_PROBE",
                 "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO","build"],180)
        built=products/"Build/Build/Products/Debug"
        container=built/"CascadeAddonProbeContainer.app"
        provider=container/"Contents/Extensions/CascadeProbeProvider.appex"
        host=built/"CascadeAddonProbe.app"
        for bundle,identifier,entitlements in [
            (provider,"hylo.Cascade.AddonProbeContainer.Provider",sources/"Provider/Provider.entitlements"),
            (container,"hylo.Cascade.AddonProbeContainer",None),(host,"hylo.Cascade.AddonProbe",None)]:
            command(["codesign","--force","--timestamp=none","--options","runtime","--sign",SIGNER,
                     *(["--entitlements",str(entitlements)] if entitlements else []),str(bundle)])
            command(["codesign","--verify","--strict","--deep","-R",
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf = H"{SIGNER}"',str(bundle)])
            command(["codesign","-d","--entitlements","-","--xml",str(bundle)])
        command(["sw_vers"]); command(["xcrun","--show-sdk-version"])
    files=[p for p in sources.rglob("*") if p.is_file()]
    source_hashes={str(p.relative_to(sources)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    runner_files=[SOURCE/"run_recovery.py",SOURCE/"recovery_evidence.py",SOURCE/"test_recovery_evidence.py",
                  PLATFORM/"XPCLifetime/run_probe.py",PLATFORM/"XPCLifetime/evidence.py"]
    binaries=[host/"Contents/MacOS/ProbeHost",provider/"Contents/MacOS/ProbeProvider",container/"Contents/MacOS/ProbeContainer"]
    manifest=dict(commands=commands,signer=SIGNER,host=str(host),provider=str(provider),container=str(container),
                  sourceHashes=source_hashes,runnerHashes={str(p.relative_to(PLATFORM)):hashlib.sha256(p.read_bytes()).hexdigest() for p in runner_files},
                  binaries={str(p.relative_to(products)):hashlib.sha256(p.read_bytes()).hexdigest() for p in binaries})
    (products/"build.json").write_text(json.dumps(manifest,indent=2)+"\n")
    return products


class Participant:
    def __init__(self,manifest,products,label):
        self.record={"events":[],"label":label}
        self.queue=select.kqueue()
        self.identity=None
        self.exit=None
        self.errors=(products/(label+".stderr")).open("wb")
        environment=dict(os.environ,CASCADE_RECOVERY_PROVIDER_BUNDLE=manifest["provider"])
        self.process=subprocess.Popen([str(Path(manifest["host"])/"Contents/MacOS/ProbeHost"),"recovery"],
            stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.errors,env=environment,bufsize=0)
        self.output=Output(self.process,self.record)
        self.record["hostPID"]=self.process.pid

    def bind(self):
        self.output.expect("client-ready")
        self.output.command("hello")
        hello=self.output.expect("hello")
        if hello.get("authenticated") is not True: raise RuntimeError("unauthenticated provider")
        identity={key:hello[key] for key in ("pid","instance","guardDeadline","bundlePath")}
        pid=identity["pid"]
        if type(pid) is not int or pid<=1 or pid==self.process.pid: raise RuntimeError("invalid PID")
        receipts=self.queue.control([select.kevent(pid,filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD|select.KQ_EV_ONESHOT|EV_RECEIPT,
            fflags=select.KQ_NOTE_EXIT|NOTE_EXITSTATUS)],1,0)
        if len(receipts)!=1 or receipts[0].data!=0 or not receipts[0].flags & select.KQ_EV_ERROR:
            raise RuntimeError("exit registration refused")
        self.identity=identity
        self.record.update(identity=identity,authenticated=True,registered=True)
        self.output.command("hold")
        second=self.output.expect("hold")
        same=second.get("authenticated") is True and all(second.get(k)==v for k,v in identity.items())
        self.record["sameInstance"]=same
        if not same: raise RuntimeError("provider incarnation changed")
        self.observe(0)
        if self.exit or native_time()+10.5>=identity["guardDeadline"]: raise RuntimeError("early exit or insufficient guard")

    def observe(self,timeout):
        for event in self.queue.control(None,1,timeout):
            if event.flags & select.KQ_EV_ERROR or not event.fflags & select.KQ_NOTE_EXIT:
                raise RuntimeError("invalid exit event")
            if self.identity is None or event.ident!=self.identity["pid"]: raise RuntimeError("unexpected PID event")
            self.exit=dict(time=native_time(),status=int(event.data) if event.fflags & NOTE_EXITSTATUS else None)
            self.record["exit"]=self.exit.copy()

    def wait_exit(self,deadline):
        while self.exit is None and native_time()<deadline:
            self.observe(max(0,deadline-native_time()))

    def stop(self,command):
        trigger=native_time()
        self.output.command(command)
        self.output.expect(command,allow_terminal=True)
        self.process.wait(timeout=1)
        self.record.update(trigger=trigger,hostStatus=self.process.returncode,hostExitObserved=native_time())
        self.wait_exit(trigger+8)
        return trigger

    def cleanup(self):
        measurement=self.exit.copy() if self.exit else None
        try:
            if self.process.poll() is None:
                try:
                    self.output.command("quit"); self.process.wait(timeout=1)
                except (OSError,subprocess.TimeoutExpired):
                    self.process.kill(); self.process.wait(timeout=1)
                    self.record["hostCleanupForced"]=True
            if self.identity:
                self.wait_exit(self.identity["guardDeadline"]+1)
            self.record["cleanup"]=dict(exit=self.exit,hostStatus=self.process.returncode,
                                         knownProviderExited=self.identity is not None and self.exit is not None)
        finally:
            self.record["exit"]=measurement
            self.queue.close(); self.process.stdin.close(); self.process.stdout.close(); self.errors.close()


def run_case(manifest,products,mode):
    r=dict(mode=mode,launcherAdmitted=False)
    participants=[]
    try:
        first=Participant(manifest,products,mode+"-first"); participants.append(first)
        first.bind()
        r.update(authenticated=True,registered=True,sameInstance=True,guardDeadline=first.identity["guardDeadline"])
        first.output.command("invalidate")
        first.output.expect("invalidated")
        r["invalidationObserved"]=True
        first.observe(2)
        first.output.command("ping"); first.output.expect("ping")
        first.observe(0)
        r["stillAliveAfterInvalidation"]=first.exit is None and first.process.poll() is None
        if not r["stillAliveAfterInvalidation"]: raise RuntimeError("fixture did not require fallback after invalidation")
        trigger=first.stop("quit" if mode=="normal" else "crash")
        r.update(trigger=trigger,hostStatus=first.process.returncode,hostExitObserved=first.record["hostExitObserved"],
                 serviceExit=first.exit["time"] if first.exit else None,serviceStatus=first.exit["status"] if first.exit else None)
        # Never restart until both retained host and exact registered provider have exited.
        if (first.exit is None or first.exit["status"] not in (9,15) or
            first.exit["time"]>trigger+8 or trigger+8.5>=first.identity["guardDeadline"] or
            first.process.returncode!=(0 if mode=="normal" else -9)):
            raise RuntimeError("no qualified old-chain exit; restart withheld")
        r["restartStarted"]=native_time()
        fresh=Participant(manifest,products,mode+"-fresh"); participants.append(fresh)
        fresh.bind()
        r.update(freshAuthenticated=True,freshRegistered=True,freshConfirmed=True,
                 freshInstance=fresh.identity["instance"]!=first.identity["instance"],
                 freshGuardDeadline=fresh.identity["guardDeadline"])
        r["freshStopTrigger"]=fresh.stop("quit")
        r.update(freshHostStatus=fresh.process.returncode,freshExit=fresh.exit["time"] if fresh.exit else None,
                 freshStatus=fresh.exit["status"] if fresh.exit else None)
    except (OSError,RuntimeError,TimeoutError,ValueError,KeyError,subprocess.TimeoutExpired) as error:
        r["observationError"]=repr(error)
    finally:
        r["verdict"]=classify(r)
        for participant in participants:
            try: participant.cleanup()
            except (OSError,RuntimeError,TimeoutError,subprocess.TimeoutExpired) as error:
                participant.record["cleanupError"]=repr(error)
        r["participants"]=[p.record for p in participants]
        r["cleanupComplete"]=bool(participants) and all(p.record.get("cleanup",{}).get("knownProviderExited") is True
                                                       and not p.record.get("cleanupError") for p in participants)
    (products/(mode+".json")).write_text(json.dumps(r,indent=2)+"\n")
    return r


def run(products):
    manifest=json.loads((products/"build.json").read_text())
    for root,key in [(products/"Sources","sourceHashes"),(PLATFORM,"runnerHashes"),(products,"binaries")]:
        for relative,digest in manifest[key].items():
            if hashlib.sha256((root/relative).read_bytes()).hexdigest()!=digest: raise RuntimeError("changed input: "+relative)
    # The guard-only mode creates no extension. Its retained direct child is bounded externally too.
    old_mask=signal.pthread_sigmask(signal.SIG_BLOCK,{signal.SIGALRM})
    try:
        child=subprocess.Popen([str(Path(manifest["host"])/"Contents/MacOS/ProbeHost"),"recovery-guard-check"],
                               stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    finally:
        signal.pthread_sigmask(signal.SIG_SETMASK,old_mask)
    try: stdout,stderr=child.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        child.kill(); stdout,stderr=child.communicate(timeout=1)
        raise RuntimeError("guard did not terminate retained direct child")
    guard=dict(status=child.returncode,stdout=stdout.decode(),stderr=stderr.decode())
    (products/"guard-check.json").write_text(json.dumps(guard,indent=2)+"\n")
    if child.returncode!=-signal.SIGALRM or json.loads(stdout).get("inheritedAlarmBlocked") is not True:
        raise RuntimeError("inherited-signal guard check failed")
    subprocess.run(["open","-g",manifest["container"]],check=True,timeout=10)
    results=[]
    for mode in ("normal","crash"):
        record=run_case(manifest,products,mode); results.append(record)
        (products/"results.json").write_text(json.dumps(dict(cases=results,launcherAdmitted=False),indent=2)+"\n")
        print(json.dumps({key:record.get(key) for key in ("mode","verdict","observationError","cleanupComplete")}),flush=True)
        if record["verdict"]=="UNKNOWN" or not record["cleanupComplete"]: return 2
    return 0 if all(r["verdict"]=="PASS" for r in results) else 1


if __name__=="__main__":
    if sys.argv[1:]==["--build-only"]: print(build(),flush=True)
    elif len(sys.argv)==3 and sys.argv[1]=="--run": raise SystemExit(run(Path(sys.argv[2]).resolve()))
    else: raise SystemExit("usage: run_recovery.py --build-only | --run PRODUCTS")
