"""Own exactly one disposable Tart process; stop it before consuming host reserve."""
from pathlib import Path
import json,os,shutil,signal,subprocess,sys,time
base=Path('/private/tmp/cascade-addon-vm')
label=sys.argv[1]
assert len(sys.argv)==2 or sys.argv[2:]==['--recovery']
assert label.replace('-','').isalnum()
output=base/label;output.mkdir(exist_ok=False)
state=base/'state';runtime=base/'tart.app/Contents/MacOS/tart'
env=dict(os.environ,TART_HOME=str(state),TART_NO_AUTO_PRUNE='1')
command=[str(runtime),'run','cascade-addon-small','--no-audio','--no-clipboard','--no-usb-accessories','--dir='+str('probe:'+str(base/'share')+':ro')]
if sys.argv[2:]:command.append('--recovery')
record=dict(command=command,started=time.time(),minimumFreeBytes=3*2**30,timeoutSeconds=1800)
assert shutil.disk_usage(base).free>record['minimumFreeBytes']
start=time.monotonic();last=start-30
with (output/'manager.log').open('wb') as log:
    child=subprocess.Popen(command,env=env,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
    record['pid']=child.pid
    (output/'started.json').write_text(json.dumps(record,indent=2)+'\n')
    while child.poll() is None:
        free=shutil.disk_usage(base).free
        if free<record['minimumFreeBytes'] or time.monotonic()-start>record['timeoutSeconds'] or (output/'stop').exists():
            record['stopReason']='space-floor' if free<record['minimumFreeBytes'] else 'timeout' if time.monotonic()-start>record['timeoutSeconds'] else 'requested'
            record['stopRequested']=time.time()
            child.send_signal(signal.SIGINT)
            try: child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                record['managerKillFallback']=True
                child.kill();child.wait(timeout=5)
            break
        if time.monotonic()-last>=30:
            print(json.dumps(dict(event='vm-alive',label=label,pid=child.pid,elapsedSeconds=round(time.monotonic()-start),freeGiB=round(free/2**30,2))),flush=True);last=time.monotonic()
        time.sleep(.25)
    record.update(exitCode=child.returncode,exitObserved=time.time(),elapsedSeconds=round(time.monotonic()-start,3),freeAfterStop=shutil.disk_usage(base).free)
record['stopMessagePresent']='Stopping VM...' in (output/'manager.log').read_text(errors='replace')
status=subprocess.run([str(runtime),'list','--format','json'],env=env,capture_output=True,text=True,timeout=5)
record['listAfterExit']=dict(status=status.returncode,stdout=status.stdout,stderr=status.stderr)
(output/'result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(dict(event='vm-ended',**record)),flush=True)
raise SystemExit(0 if child.returncode==0 else 2)
