"""Resume only this task's pinned image, retaining progress on timeout."""
from pathlib import Path
import json,os,shutil,subprocess,time
base=Path('/private/tmp/cascade-addon-vm')
state=base/'state'
record_path=base/'download-resume-result.json'
log_path=base/'download-resume.log'
assert not record_path.exists() and not log_path.exists(), 'Do not start a duplicate download'
reference=(base/'image-reference.txt').read_text().strip()
assert reference=='ghcr.io/cirruslabs/macos-sonoma-vanilla@sha256:a6dc5a325aae43a90244953af0a85091fbe93e8f58583138c5ac96dd707fd700'
command=[str(base/'tart.app/Contents/MacOS/tart'),'clone',reference,'cascade-addon-small','--concurrency','4']
env=dict(os.environ,TART_HOME=str(state),TART_NO_AUTO_PRUNE='1')
record=dict(command=command,started=time.time(),minimumFreeBytes=int(4.5*2**30),timeoutSeconds=7200)
record['initialFreeBytes']=shutil.disk_usage(base).free
assert record['initialFreeBytes']>record['minimumFreeBytes']
start=time.monotonic();last=start-30
with log_path.open('xb') as log:
    child=subprocess.Popen(command,env=env,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
    record['pid']=child.pid
    (base/'download-resume-started.json').write_text(json.dumps(record,indent=2)+'\n')
    while child.poll() is None:
        free=shutil.disk_usage(base).free
        elapsed=time.monotonic()-start
        reason=('space-floor' if free<record['minimumFreeBytes'] else
                'timeout' if elapsed>record['timeoutSeconds'] else
                'requested' if (base/'stop-resume-download').exists() else None)
        if reason:
            record['stopReason']=reason
            child.terminate()
            try: child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                record['killFallback']=True
                child.kill();child.wait(timeout=5)
            break
        if time.monotonic()-last>=30:
            print(json.dumps(dict(stage='download-final-resume',elapsedSeconds=round(elapsed),freeGiB=round(free/2**30,2))),flush=True)
            last=time.monotonic()
        time.sleep(.5)
    record.update(exitCode=child.returncode,ended=time.time(),elapsedSeconds=round(time.monotonic()-start,3),freeBytes=shutil.disk_usage(base).free)
if record.get('stopReason')=='space-floor':
    shutil.rmtree(state)
    record['incompleteStateRemoved']=True
    record['freeBytesAfterRemoval']=shutil.disk_usage(base).free
else:
    record['statePreserved']=state.exists()
record_path.write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
raise SystemExit(0 if record['exitCode']==0 else 2)
