"""Compare ExtensionFoundation's callback against registered kernel exit events."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from interruption_evidence import classify

SOURCE=Path(__file__).resolve().parent
PLATFORM=SOURCE.parent
sys.path.insert(0,str(PLATFORM/"Recovery"))
from run_recovery import build, Participant, register_container, native_time


def run_case(manifest,products,mode):
    record=dict(mode=mode,launcherAdmitted=False)
    participant=None
    try:
        participant=Participant(manifest,products,"interruption-"+mode)
        participant.bind(hold=mode=="invalidate-blocked")
        nonce=participant.record["ready"]["launchNonce"]
        record.update(authenticated=True,registered=True,confirmed=True,launchNonce=nonce,
                      guardDeadline=participant.identity["guardDeadline"])
        participant.output.command("observation")
        before=participant.output.expect("observation")
        if before["notifications"]: raise RuntimeError("interruption before trigger")
        record["before"]=before
        command={"provider-exit":"provider-exit","provider-crash":"provider-crash",
                 "invalidate-cooperative":"invalidate","release-cooperative":"release",
                 "invalidate-blocked":"invalidate"}[mode]
        if native_time()+8>=participant.identity["guardDeadline"]: raise RuntimeError("insufficient guard margin")
        record["trigger"]=native_time()
        participant.output.command(command)
        participant.output.expect("provider-stop-requested" if mode.startswith("provider-") else "invalidated")
        deadline=record["trigger"]+6
        # Keep the observation window open even after an early exit, to collect delayed callbacks.
        while native_time()<deadline: participant.observe(min(.1,max(0,deadline-native_time())))
        participant.output.command("observation")
        after=participant.output.expect("observation")
        record.update(after=after,notifications=after["notifications"],windowEnd=after["time"],
                      exit=participant.exit.copy() if participant.exit else None,
                      hostAlive=participant.process.poll() is None)
        if after["launchNonce"]!=nonce: raise RuntimeError("changed launch identity")
        if command in {"invalidate","release"}:
            record["ownedReferencesReleased"]=not any(after["ownedReferences"].values())
            if not record["ownedReferencesReleased"]: raise RuntimeError("host still owns a reference")
    except (OSError,RuntimeError,TimeoutError,ValueError,KeyError,subprocess.TimeoutExpired) as error:
        record["observationError"]=repr(error)
    finally:
        record["outcome"]=classify(record)
        if participant:
            try: participant.cleanup()
            except (OSError,RuntimeError,TimeoutError,subprocess.TimeoutExpired) as error:
                participant.record["cleanupError"]=repr(error)
            record["participant"]=participant.record
            record["cleanupComplete"]=(participant.record.get("cleanup",{}).get("knownProviderExited") is True
                                       and not participant.record.get("cleanupError"))
    (products/("interruption-"+mode+".json")).write_text(json.dumps(record,indent=2)+"\n")
    return record


def run(products):
    manifest=json.loads((products/"build.json").read_text())
    for root,key in [(products/"Sources","sourceHashes"),(PLATFORM,"runnerHashes"),(products,"binaries")]:
        for relative,digest in manifest[key].items():
            if hashlib.sha256((root/relative).read_bytes()).hexdigest()!=digest: raise RuntimeError("changed input: "+relative)
    register_container(manifest,products)
    records=[]
    for mode in ("provider-exit","provider-crash","invalidate-cooperative","release-cooperative","invalidate-blocked"):
        r=run_case(manifest,products,mode); records.append(r)
        (products/"interruption-results.json").write_text(json.dumps(dict(cases=records,launcherAdmitted=False),indent=2)+"\n")
        print(json.dumps({k:r.get(k) for k in ("mode","outcome","observationError","exit","notifications","cleanupComplete")}),flush=True)
        if r["outcome"]=="UNKNOWN" or not r.get("cleanupComplete"): return 2
    return 0


if __name__=="__main__":
    if sys.argv[1:]==["--build-only"]:
        print(build(additional_runners=sorted(SOURCE.glob("*.py"))),flush=True)
    elif len(sys.argv)==3 and sys.argv[1]=="--run": raise SystemExit(run(Path(sys.argv[2]).resolve()))
    else: raise SystemExit("usage: run_interruption.py --build-only | --run PRODUCTS")
