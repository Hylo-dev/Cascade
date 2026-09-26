"""Run one qualified guest case, retain evidence and stop this VM on any failure."""
from pathlib import Path
import argparse,hashlib,json,os,shlex,subprocess,time
base=Path('/private/tmp/cascade-addon-vm')
a=argparse.ArgumentParser();a.add_argument('--ip',required=True);a.add_argument('--manager',required=True);a.add_argument('--mode',choices=['release-control','broker-stop','broker-crash','root-quit','root-crash'],required=True);a.add_argument('--label',required=True);args=a.parse_args()
assert all(x.replace('-','').isalnum() for x in (args.manager,args.label))
manager=base/args.manager
assert (manager/'started.json').is_file() and not (manager/'result.json').exists() and not (manager/'stop').exists()
q=json.loads((base/'cleanup-qualified.json').read_text());evidence=base/'cleanup-evidence.json'
assert q['managerCleanupQualified'] is True and hashlib.sha256(evidence.read_bytes()).hexdigest()==q['stopEvidenceSHA256']
out=base/('case-'+args.label);out.mkdir(exist_ok=False)
ssh=['/usr/bin/ssh','-F','/dev/null','-o','ForwardAgent=no','-o','IdentityAgent=none','-o','GlobalKnownHostsFile=/dev/null','-i',str(base/'guest-access'),'-o','IdentitiesOnly=yes','-o','BatchMode=yes','-o','UserKnownHostsFile='+str(base/'known_hosts'),'-o','StrictHostKeyChecking=yes','-o','ConnectTimeout=5','-o','ConnectionAttempts=1','admin@'+args.ip]
remote='/Users/admin/results/'+args.label
command=['/Users/admin/CascadeProbe/python/bin/python3.12','-I','-B','/Users/admin/CascadeProbe/run_vm_suspended_arm64.py','--mode',args.mode,'--manifest','/Users/admin/CascadeProbe/products/build.json','--products','/Users/admin/CascadeProbe/products','--output',remote,'--cleanup-qualification','/Users/admin/cleanup-qualified.json','--vm-identifier',q['vmIdentifier']]
record=dict(started=time.time(),mode=args.mode,label=args.label,qualification=q,hostStopRequired=True)
try:
    # Fail before fixture launch if DHCP restored any Internet default route.
    record['routeChecks']=[]
    for family in ('inet','inet6'):
        check=subprocess.run(ssh+['/usr/sbin/netstat -rn -f '+family],capture_output=True,text=True,timeout=8)
        record['routeChecks'].append(dict(family=family,exitCode=check.returncode,stdout=check.stdout,stderr=check.stderr))
        if check.returncode!=0 or any(line.split() and line.split()[0]=='default' for line in check.stdout.splitlines()):
            raise RuntimeError('Missing or unsafe route evidence: '+family)
    with (out/'events.jsonl').open('wb') as log,(out/'ssh.stderr').open('wb') as error:
        result=subprocess.run(ssh+['CASCADE_DISPOSABLE_VM=1 '+shlex.join(command)],stdout=log,stderr=error,timeout=65)
    record['exitCode']=result.returncode
    events=[]
    for line in (out/'events.jsonl').read_text().splitlines():
        events.append(json.loads(line))
    measured=[e['payload'] for e in events if e.get('event')=='measurement-result']
    assert len(measured)==1
    record['classification']=measured[0]['classification']
    record['hostStopRequired']=result.returncode!=0 or measured[0].get('hostStopRequired') is not False or measured[0]['classification']!='PASS'
except BaseException as error:
    record['error']=repr(error)
    record['hostStopRequired']=True
finally:
    try:
        # Copy a small diagnostic directory before the mandatory whole-VM stop.
        try:
            with (out/'guest-results.tar.gz').open('wb') as archive:
                copied=subprocess.run(ssh+['/usr/bin/tar -czf - -C /Users/admin/results '+shlex.quote(args.label)],stdout=archive,stderr=subprocess.PIPE,timeout=8)
            record['copy']=dict(exitCode=copied.returncode,stderr=copied.stderr.decode(errors='replace'))
            if copied.returncode!=0:
                record['hostStopRequired']=True
        except BaseException as error:
            record['copyError']=repr(error);record['hostStopRequired']=True
    finally:
        if record['hostStopRequired']:
            (manager/'stop').touch()
            record['hostStopRequested']=time.time()
        record['finished']=time.time()
        (out/'host-result.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record),flush=True)
raise SystemExit(2 if record['hostStopRequired'] else 0)
