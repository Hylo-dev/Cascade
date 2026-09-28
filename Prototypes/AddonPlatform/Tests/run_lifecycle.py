#!/usr/bin/env python3
"""Bounded desktop probe harness. Never used by the production runtime."""
import json, os, pathlib, selectors, signal, subprocess, sys, time


def remaining(deadline, maximum=None):
    budget = deadline - time.monotonic()
    if budget <= 0:
        raise TimeoutError('absolute fixture deadline exhausted')
    return min(budget, maximum) if maximum is not None else budget


def identity(pid, deadline):
    # Include our own PID as a positive observation control. Target absence is
    # established only by successful ps output which also contains that control.
    observer = os.getpid()
    try:
        result = subprocess.run(['/bin/ps', '-ww', '-p', f'{pid},{observer}', '-o', 'pid=',
                                 '-o', 'lstart=', '-o', 'comm='], capture_output=True,
                                text=True, timeout=remaining(deadline, 1))
    except (OSError, subprocess.TimeoutExpired, TimeoutError) as error:
        return {'state': 'error', 'reason': str(error)}
    record = {'returncode': result.returncode, 'stderr': result.stderr[:4096]}
    if result.returncode != 0 or result.stderr:
        return dict(record, state='error', reason='process observer failed')
    rows = {}
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2 or not fields[0].isdigit():
            return dict(record, state='error', reason='malformed process observation')
        rows[int(fields[0])] = fields[1]
    if observer not in rows:
        return dict(record, state='error', reason='process observer control missing')
    if pid not in rows:
        return dict(record, state='absent')
    return dict(record, state='present', identity=rows[pid])


def run(case, host):
    host = pathlib.Path(host).resolve()
    provider = host.parents[3] / 'CascadeAddonProbeContainer.app/Contents/Extensions/CascadeProbeProvider.appex/Contents/MacOS/ProbeProvider'
    started = time.monotonic()
    deadline = started + 5
    work_deadline = deadline - 1  # Reserve one second for authenticated cleanup.
    handshake_deadline = min(started + 3, work_deadline)
    process = subprocess.Popen([str(host), case], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
    owned = None; pid = None
    pending = b''; events = []
    evidence = {'schemaVersion': 1, 'scenario': case, 'checks': {},
                'observations': {'processObservations': []}, 'unverified': [], 'case': case,
                'hostPID': process.pid, 'status': 'FAIL', 'providerExecutable': str(provider),
                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}

    def observe(pid, phase_deadline):
        record = identity(pid, phase_deadline)
        evidence['observations']['processObservations'].append(record)
        if record['state'] == 'error':
            evidence['unverified'].append('process observation failed')
            raise RuntimeError(record['reason'])
        return record

    try:
        while time.monotonic() < handshake_deadline:
            if not events:
                if not selector.select(timeout=remaining(handshake_deadline, .1)): continue
                chunk = os.read(process.stdout.fileno(), 8192)
                if not chunk: break
                pending += chunk
                if len(pending) > 65_536: raise RuntimeError('unbounded probe output')
                lines = pending.split(b'\n'); pending = lines.pop()
                events.extend(json.loads(line) for line in lines if line)
            if not events: continue
            event = events.pop(0)
            if event.get('status') == 'FAIL': raise RuntimeError(event['reason'])
            if 'providerPID' in event:
                pid = event['providerPID']
                initial = observe(pid, handshake_deadline)
                if initial['state'] != 'present' or not initial['identity'].endswith(' ' + str(provider)):
                    raise RuntimeError('provider executable did not match fixture')
                owned = (pid, initial['identity'])
                evidence.update(event)
                evidence['status'] = 'FAIL'
                break
        if owned is None: raise RuntimeError('no authenticated provider before external deadline')
        if case == 'crash-host-spin': process.kill()
        exit_deadline = min(work_deadline, time.monotonic() + 2)
        while time.monotonic() < exit_deadline:
            current = observe(pid, exit_deadline)
            if current['state'] == 'absent':
                evidence.update(status='PASS', exitObserved=True)
                break
            if current['identity'] != owned[1]:
                evidence['unverified'].append('provider identity changed without observed absence')
                raise RuntimeError('process identity changed; exit is unverified')
            time.sleep(remaining(exit_deadline, .04))
        else:
            evidence.update(reason=('no verified exit through NSRunningApplication while host stays alive'
                                    if case == 'application-stop-spin' else 'provider remains after host exit/invalidation'),
                            exitObserved=False)
    except Exception as error:
        evidence['reason'] = str(error)
        evidence['status'] = 'FAIL'
    finally:
        selector.close()
        if events: evidence['followingEvents'] = events
        if pending: evidence['partialHostOutput'] = pending[:65_536].decode('utf-8', errors='replace')
        # Cleanup precedes output collection: a communicate timeout cannot skip it.
        if process.poll() is None: process.kill()
        if owned:
            try:
                current = observe(owned[0], deadline)
                if current['state'] == 'present' and current['identity'] == owned[1]:
                    remaining(deadline)
                    # Diagnostic path/start check, not atomic production PID identity.
                    os.kill(owned[0], signal.SIGKILL)
                    evidence['observations']['providerCleanupSignalRequested'] = True
            except (OSError, RuntimeError, TimeoutError) as error:
                evidence['unverified'].append('authenticated provider cleanup unverified')
                evidence['observations']['cleanupError'] = str(error)
        trailing, diagnostic = b'', b''
        try:
            trailing, diagnostic = process.communicate(timeout=remaining(deadline))
        except (subprocess.TimeoutExpired, TimeoutError, OSError) as error:
            evidence['unverified'].append('host output collection incomplete')
            evidence['observations']['communicateError'] = str(error)
        if trailing: evidence['trailingHostOutput'] = trailing[:65_536].decode('utf-8', errors='replace')
        if diagnostic: evidence['hostDiagnostic'] = diagnostic[:4096].decode('utf-8', errors='replace')
        diagnostic_events = list(events)
        for line in trailing.splitlines():
            try: diagnostic_events.append(json.loads(line))
            except (ValueError, TypeError): pass
        evidence['observations']['hostEvents'] = diagnostic_events
        if case == 'application-stop-spin':
            handle_events = [event for event in diagnostic_events if 'applicationHandlePresent' in event]
            if handle_events:
                evidence['observations']['applicationHandlePresent'] = handle_events[-1]['applicationHandlePresent']
                evidence['observations']['forceTerminateInvoked'] = handle_events[-1]['forceTerminateInvoked']
                if not handle_events[-1]['applicationHandlePresent']:
                    evidence['reason'] = 'authenticated headless extension has no NSRunningApplication handle; forceTerminate not invoked'
            else: evidence['unverified'].append('NSRunningApplication handle diagnostic missing')
        if owned is None: evidence['unverified'].append('authenticated provider not observed')
        evidence['checks']['exitObserved'] = evidence.get('exitObserved') is True
        evidence['checks']['externalDeadline'] = time.monotonic() <= deadline
        evidence['elapsedMilliseconds'] = round((time.monotonic() - started) * 1000, 2)
        if evidence['unverified'] or not all(evidence['checks'].values()): evidence['status'] = 'FAIL'
    return evidence


if __name__ == '__main__':
    cases = sys.argv[2:] or ['invalidate-spin','normal-host-spin','crash-host-spin']
    if any(case not in ('invalidate-spin','normal-host-spin','crash-host-spin','application-stop-spin') for case in cases):
        raise SystemExit('Unsupported lifecycle case')
    results = [run(case, sys.argv[1]) for case in cases]
    for result in results: print(json.dumps(result, sort_keys=True))
    sys.exit(0 if all(result['status']=='PASS' for result in results) else 1)
