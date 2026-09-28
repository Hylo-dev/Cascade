from pathlib import Path
import json,os,subprocess,sys,time
base=Path('/private/tmp/cascade-addon-vm')
ip=sys.argv[1];label=sys.argv[2];script=Path(sys.argv[3])
assert label.replace('-','').isalnum()
env=dict(os.environ,SSH_ASKPASS=str(base/'guest-askpass'),SSH_ASKPASS_REQUIRE='force',DISPLAY='cascade-vm-bootstrap')
command=['/usr/bin/ssh','-F','/dev/null','-o','ForwardAgent=no','-o','IdentityAgent=none','-o','GlobalKnownHostsFile=/dev/null','-i',str(base/'guest-access'),'-o','IdentitiesOnly=yes','-o','UserKnownHostsFile='+str(base/'known_hosts'),'-o','StrictHostKeyChecking=accept-new','-o','ConnectTimeout=5','-o','ConnectionAttempts=1','-o','NumberOfPasswordPrompts=1','admin@'+ip,'/bin/sh -s']
start=time.time()
r=subprocess.run(command,input=script.read_bytes(),capture_output=True,env=env,timeout=60)
record=dict(started=start,finished=time.time(),exitCode=r.returncode,stdout=r.stdout.decode(errors='replace'),stderr=r.stderr.decode(errors='replace'))
(base/(label+'.json')).write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record))
raise SystemExit(r.returncode)
