import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time

products = Path(sys.argv[1]).resolve(); label = sys.argv[2]
logs = Path(tempfile.mkdtemp(prefix='cascade-direct-v1-audit-logs.', dir='/private/tmp'))
print('Logs: ' + str(logs), flush=True)
requirement = 'anchor apple generic and identifier "hylo.Cascade.DirectV1.AuditWorker" and certificate leaf[subject.OU] = "A6A5HQL6K4"'
job = dict(Label=label, ProgramArguments=[str(products/'AuditServer'), 'server', label, requirement, 'unused'],
           MachServices={label: True}, RunAtLoad=True,
           StandardOutPath=str(logs/'server.jsonl'), StandardErrorPath=str(logs/'server.stderr'))
plist = products/'audit.plist'; plist.write_bytes(plistlib.dumps(job)); plist.chmod(0o600)
domain = 'gui/' + str(os.getuid()); deadline = time.monotonic()+5
result = {'bootstrapReturnCode': None, 'workerReturnCode': None, 'bootoutReturnCode': None,
          'serverEvents': [], 'workerEvents': [], 'cleanupErrors': []}
process = None
try:
    boot = subprocess.run(['/bin/launchctl', 'bootstrap', domain, str(plist)], capture_output=True, text=True, timeout=1)
    result['bootstrapReturnCode'] = boot.returncode; result['bootstrapStderr'] = boot.stderr
    if boot.returncode == 0:
        sentinel = '/Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/CODE_STYLE.md'
        with open(sentinel, 'rb'): pass
        process = subprocess.Popen([str(products/'AuditWorker'), 'original', label, str(products/'AuditReplacement'), sentinel], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        output, error = process.communicate(timeout=max(.01, deadline-time.monotonic()-1))
        result['workerReturnCode'] = process.returncode; result['workerStderr'] = error
        result['workerEvents'] = [json.loads(line) for line in output.splitlines()]
        result['serverEvents'] = [json.loads(line) for line in (logs/'server.jsonl').read_text().splitlines()]
except (OSError, ValueError, subprocess.TimeoutExpired) as error: result['error'] = str(error)
finally:
    # Each cleanup step is independent; a blocked pipe must not leave the launchd
    # label registered or prevent the structured unknown/error result from surviving.
    try:
        if process and process.poll() is None:
            process.kill()
            process.communicate(timeout=max(.01, deadline-time.monotonic()))
    except (OSError, subprocess.TimeoutExpired) as error:
        result['cleanupErrors'].append('worker cleanup: ' + str(error))
    try:
        cleanup = subprocess.run(['/bin/launchctl', 'bootout', domain+'/'+label],
            capture_output=True, text=True, timeout=max(.01, deadline-time.monotonic()))
        result['bootoutReturnCode'] = cleanup.returncode
        result['bootoutStderr'] = cleanup.stderr
    except (OSError, subprocess.TimeoutExpired) as error:
        result['cleanupErrors'].append('launchd cleanup: ' + str(error))
    finally:
        print(json.dumps(result), flush=True)
        (logs/'results.json').write_text(json.dumps(result, indent=2))
