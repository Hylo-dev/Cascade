"""Controller-only regression checks; all SSH calls mocked, no native process."""
from pathlib import Path
from unittest.mock import patch
import contextlib,hashlib,io,json,subprocess,sys,tempfile
base=Path('/private/tmp/cascade-addon-vm')
source=(base/'run-case.py').read_text()
records=[]
for scenario in ('ipv4-error','interrupt-during-copy'):
    with tempfile.TemporaryDirectory(prefix='cascade-controller-test-',dir='/private/tmp') as temp:
        root=Path(temp);manager=root/'manager';manager.mkdir();(manager/'started.json').write_text('{}')
        evidence=b'controller unit test only; never a VM qualification';(root/'cleanup-evidence.json').write_bytes(evidence)
        (root/'cleanup-qualified.json').write_text(json.dumps(dict(managerCleanupQualified=True,vmIdentifier='controller-unit-test',stopEvidenceSHA256=hashlib.sha256(evidence).hexdigest())))
        text=source.replace("base=Path('/private/tmp/cascade-addon-vm')",'base=Path('+repr(str(root))+')')
        calls=[]
        def fake_run(command,**kwargs):
            calls.append(command[-1])
            if command[-1].startswith('/usr/sbin/netstat'):
                return subprocess.CompletedProcess(command,1 if scenario=='ipv4-error' else 0,stdout='Routing tables\nDestination Gateway\n',stderr='test IPv4 failure' if scenario=='ipv4-error' else '')
            if command[-1].startswith('CASCADE_DISPOSABLE_VM=1'):
                kwargs['stdout'].write((json.dumps(dict(event='measurement-result',payload=dict(classification='PASS',hostStopRequired=False)))+'\n').encode())
                return subprocess.CompletedProcess(command,0)
            if command[-1].startswith('/usr/bin/tar'):
                if scenario=='interrupt-during-copy': raise KeyboardInterrupt('simulated controller cancellation')
                return subprocess.CompletedProcess(command,1,stderr=b'no result expected')
            raise AssertionError(command)
        status=None
        with patch.object(sys,'argv',['run-case.py','--ip','test.invalid','--manager','manager','--mode','release-control','--label','test']),patch('subprocess.run',fake_run),contextlib.redirect_stdout(io.StringIO()):
            try: exec(compile(text,'controller-test','exec'),{'__name__':'__main__'})
            except SystemExit as done: status=done.code
        assert status==2 and (manager/'stop').is_file()
        if scenario=='ipv4-error': assert not any(c.startswith('CASCADE_DISPOSABLE_VM=1') for c in calls)
        record=json.loads((root/'case-test/host-result.json').read_text())
        assert record['hostStopRequired'] is True
        records.append(dict(scenario=scenario,pass_=True,fixtureStarted=any(c.startswith('CASCADE_DISPOSABLE_VM=1') for c in calls),stopRequested=True))
report=dict(nativeOperations=False,controllerSHA256=hashlib.sha256(source.encode()).hexdigest(),checks=records)
(base/'host-controller-tests.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
