#!/usr/bin/env python3
"""External deadline and exact classification for the native request probes."""
import json, os, pathlib, subprocess, sys, time
host, case = pathlib.Path(sys.argv[1]).resolve(), sys.argv[2]
environment = dict(os.environ)
if case == 'sandbox':
    fixture = host.parents[6] / 'ForeignAddonFixture/sentinel.txt'
    fixture.parent.mkdir(parents=True, exist_ok=True)
    fixture.write_text('cascade-test-sentinel')
    environment['CASCADE_PROBE_FOREIGN_FILE'] = str(fixture)
started = time.monotonic()
try:
    result = subprocess.run([str(host), case], capture_output=True, env=environment, timeout=2)
    if len(result.stdout) > 65_536: raise RuntimeError('unbounded probe output')
    events = [json.loads(line) for line in result.stdout.splitlines() if line]
    for event in events: print(json.dumps(event, sort_keys=True))
    if case == 'standalone-echo':
        passed = result.returncode == 0 and any(event.get('status') == 'PASS' and event.get('providerPID') != event.get('hostPID') for event in events)
    elif case == 'malformed':
        # A decoding error must be caught; crashing or merely timing out is not PASS.
        passed = result.returncode == 1 and any(event.get('status') == 'FAIL' and 'dataCorrupted' in event.get('reason', '') for event in events)
    else:
        checks = next((event.get('observations') for event in events if event.get('event') == 'sandbox'), None)
        passed = result.returncode == 0 and checks is not None and set(checks) == {'foreignFixtureReadDenied', 'networkDenied', 'subprocessDenied'} and all(checks.values())
    print(json.dumps({'case': case, 'status': 'PASS' if passed else 'FAIL', 'elapsedMilliseconds': round((time.monotonic()-started)*1000, 2), 'hostExecutable': str(host)}))
    sys.exit(0 if passed else 1)
except (subprocess.TimeoutExpired, RuntimeError, ValueError) as error:
    print(json.dumps({'case': case, 'status': 'FAIL', 'reason': str(error)})); sys.exit(1)
