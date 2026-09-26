import json
import os
from pathlib import Path
import plistlib
import select
import socket
import subprocess
import sys
import time
import uuid
import tempfile
from evidence import cleanup_check

products = Path(sys.argv[1]).resolve()
logs = Path(tempfile.mkdtemp(prefix='cascade-direct-v1-logs.', dir='/private/tmp'))
print('Logs: ' + str(logs), flush=True)
records = []
for mode in ['same-group', 'setsid', 'setpgid', 'helper-joins-worker']:
    started = time.monotonic(); deadline = started + 5
    label = 'hylo.Cascade.DirectV1.' + uuid.uuid4().hex
    log = logs / (mode + '.jsonl')
    err = logs / (mode + '.stderr')
    plist = products / (mode + '.plist')
    sentinel = Path('/Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/CODE_STYLE.md')
    with sentinel.open('rb'): pass  # Positive open control, no contents accessed.
    listener = socket.socket(); listener.bind(('127.0.0.1', 0)); listener.listen(1)
    port = listener.getsockname()[1]
    with socket.create_connection(('127.0.0.1', port), timeout=.5):
        peer, _ = listener.accept(); peer.close()
    job = dict(Label=label, ProgramArguments=[str(products/'GroupHelper'), 'helper',
        str(products/'GroupWorker'), mode], RunAtLoad=True, AbandonProcessGroup=False,
        EnvironmentVariables={'CASCADE_SENTINEL': str(sentinel), 'CASCADE_PORT': str(port)},
        StandardOutPath=str(log), StandardErrorPath=str(err))
    plist.write_bytes(plistlib.dumps(job)); plist.chmod(0o600)
    domain = 'gui/' + str(os.getuid())
    observation = {'mode': mode, 'workerReady': False, 'sandboxVerified': False,
                   'helperKilled': False, 'helperExitObserved': False, 'exitObserved': False, 'exitAfterKillSeconds': None}
    queue = select.kqueue(); registered = False; events = []
    try:
        boot = subprocess.run(['/bin/launchctl', 'bootstrap', domain, str(plist)], capture_output=True, text=True, timeout=max(.01, deadline-time.monotonic()))
        observation['bootstrapReturnCode'] = boot.returncode; observation['bootstrapStderr'] = boot.stderr
        if boot.returncode == 0:
            while time.monotonic() < deadline - 1:
                try: events = [json.loads(line) for line in log.read_text().splitlines()]
                except (FileNotFoundError, ValueError): time.sleep(.01); continue
                helper = next((e for e in events if e['event'] == 'helper-ready'), None)
                worker = next((e for e in events if e['event'] == 'worker-ready'), None)
                crash = next((e for e in events if e['event'] == 'helper-kill'), None)
                if helper and worker and not registered:
                    observation['workerReady'] = helper['ready'] is True
                    observation['sandboxVerified'] = worker['fileResult'] == -1 and worker['fileErrno'] == 1 and worker['socketResult'] == -1 and worker['socketErrno'] == 1 and worker['hardNproc'] == 0 and worker['raiseResult'] == -1
                    # Diagnostic PID comes from trusted helper's retained direct-child handle.
                    # No signalling uses this number. Registration failure remains unknown.
                    queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
                        flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT, fflags=select.KQ_NOTE_EXIT)
                        for pid in [helper['workerPID'], helper['pid']]], 0, 0)
                    registered = True
                if crash:
                    observation['helperKilled'] = True
                    observation['helperKillTime'] = crash['time']
                guard = next((e for e in events if e['event'] == 'guard-armed'
                              and helper and e.get('workerPID') == helper['workerPID']), None)
                if guard:
                    observation['guardDeadlineLowerBound'] = guard['deadlineLowerBound']
                if registered:
                    exits = queue.control(None, 2, .01)
                    for event in exits:
                        if event.flags & select.KQ_EV_ERROR: raise OSError(event.data, 'kqueue event error')
                        if not event.fflags & select.KQ_NOTE_EXIT: continue
                        if event.ident == helper['pid']: observation['helperExitObserved'] = True
                        if event.ident == helper['workerPID']:
                            observation['exitObserved'] = True
                            observation['exitAfterKillSeconds'] = time.clock_gettime(time.CLOCK_MONOTONIC) - crash['time'] if crash else None
                    if observation['exitObserved'] and observation['helperExitObserved']: break
                time.sleep(.005)
    except (OSError, subprocess.TimeoutExpired) as error:
        observation['observationError'] = str(error)
    finally:
        queue.close(); listener.close()
        try:
            cleanup = subprocess.run(['/bin/launchctl', 'bootout', domain+'/'+label], capture_output=True, text=True, timeout=max(.01, deadline-time.monotonic()))
            observation['bootoutReturnCode'] = cleanup.returncode
        except subprocess.TimeoutExpired: observation['cleanupError'] = 'bootout timeout'
    observation['events'] = events
    observation['elapsedSeconds'] = time.monotonic()-started
    observation['supervisorDeathStopsWorker'] = cleanup_check(observation)
    print(json.dumps(observation), flush=True)

    records.append(observation)
    (logs / 'results.json').write_text(json.dumps(records, indent=2))
