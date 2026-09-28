#!/usr/bin/env python3
"""Real external deadlines. Only the native supervisor signals its unreaped worker."""
import errno
import json
import os
import pathlib
import selectors
import socket
import subprocess
import sys
import time
from evidence import exec_checks

products = pathlib.Path(sys.argv[1]).resolve()
sentinel = products.parent / 'ForeignDirectChildFixture/sentinel.txt'
sentinel.parent.mkdir(parents=True, exist_ok=True)
sentinel.write_text('Nonsensitive native sandbox test sentinel.')
# An unrestricted positive control distinguishes the worker restriction from ambient policy.
positive = subprocess.run(['/usr/bin/true'], timeout=1).returncode == 0
launch_marker = products / 'launch-observed.json'
launch_fixture = products / 'DirectWorker.app/Contents/Resources/LaunchFixture.app'
launch_marker.unlink(missing_ok=True)
launch_control = subprocess.run(['/usr/bin/open', '-W', '-g', str(launch_fixture)], timeout=3).returncode == 0
launch_control = launch_control and launch_marker.exists() and json.loads(launch_marker.read_text()).get('bundlePath') == str(launch_fixture)
launch_marker.unlink(missing_ok=True)
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen(1)
port = listener.getsockname()[1]
with socket.create_connection(('127.0.0.1', port), timeout=1):
    peer, _ = listener.accept()
    peer.close()
print(json.dumps({'event': 'positive-control', 'spawnAllowed': positive, 'launchServicesAllowed': launch_control,
                  'foreignFileReadable': sentinel.read_text().startswith('Nonsensitive'),
                  'loopbackConnectAllowed': True}), flush=True)
all_passed = positive and launch_control

results = []
benchmark_costs = {'benchmark-immediate': [], 'benchmark-reuse': []}
cases = ['explicit-stop', 'host-exit', 'host-crash', 'supervisor-crash', 'exec-replacement']
cases += ['repeat-stop'] * 20 + ['benchmark-immediate'] * 20 + ['benchmark-reuse']
for iteration, case in enumerate(cases):
    if case == 'benchmark-immediate' and benchmark_costs[case]:
        time.sleep(.020)  # Same nominal 20 ms quiet interval as the reuse observation loop.
    mode = case if case in ('supervisor-crash', 'exec-replacement', 'benchmark-immediate', 'benchmark-reuse') else ''
    benchmark = case.startswith('benchmark-')
    host_case = case if case in ('host-exit', 'host-crash') else 'explicit-stop' 
    command = [str(products / 'DirectHost'), str(products / 'DirectSupervisor'),
               str(products / 'DirectWorker.app/Contents/MacOS/DirectWorker'), host_case, str(sentinel), str(port),
               str(launch_fixture)]
    launch_marker.unlink(missing_ok=True)
    started = time.monotonic()
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True,
                               env=dict(os.environ, CASCADE_DIRECT_MODE=mode))
    events, buffered, errors = [], b'', b''
    deadline, ready_at, triggered = started + 5, None, False
    orphan_sampled = False
    exec_sampled = False
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, 'stdout')
    selector.register(process.stderr, selectors.EVENT_READ, 'stderr')
    failure = None
    try:
        while selector.get_map():
            now = time.monotonic()
            if now >= deadline:
                raise TimeoutError('External five-second deadline expired')
            if ready_at is not None and not triggered and now - ready_at >= (0 if benchmark else 0.30):
                process.stdin.write(b'S')
                process.stdin.flush()
                triggered = True
            if case == 'exec-replacement' and ready_at is not None and not exec_sampled and now - ready_at >= .15:
                pid = next(event['pid'] for event in events if event['event'] == 'worker-ready')
                observed = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'comm='], capture_output=True, text=True, timeout=.5)
                events.append({'event': 'exec-image-observed', 'pid': pid,
                    'replacementMatch': observed.returncode == 0 and observed.stdout.strip() == str(products / 'DirectWorker.app/Contents/MacOS/DirectWorker-replacement'),
                    'psOutput': observed.stdout.strip()})
                exec_sampled = True
            if case == 'supervisor-crash' and triggered and not orphan_sampled and now - ready_at >= .45:
                pid = next(event['pid'] for event in events if event['event'] == 'worker-ready')
                observed = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'ppid=', '-o', 'comm='], capture_output=True, text=True, timeout=.5)
                value = observed.stdout.strip().split(None, 1)
                events.append({'event': 'orphan-observed', 'pid': pid,
                    'fixtureMatch': len(value) == 2 and value[0] == '1' and value[1] == str(products / 'DirectWorker.app/Contents/MacOS/DirectWorker'),
                    'psOutput': observed.stdout.strip()})
                orphan_sampled = True
            for key, _ in selector.select(timeout=min(0.02, deadline - now)):
                chunk = os.read(key.fileobj.fileno(), 4096)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if key.data == 'stderr':
                    errors += chunk
                    if len(errors) > 65536: raise ValueError('Oversized stderr')
                    continue
                buffered += chunk
                if len(buffered) > 65536: raise ValueError('Oversized report')
                while b'\n' in buffered:
                    line, buffered = buffered.split(b'\n', 1)
                    event = json.loads(line)
                    events.append(event)
                    if len(events) > 128: raise ValueError('Too many diagnostic events')
                    print(json.dumps(dict(event, case=case, iteration=iteration), sort_keys=True), flush=True)
                    if event.get('event') == 'worker-ready': ready_at = time.monotonic()
        process.wait(timeout=max(0.001, deadline - time.monotonic()))
    except Exception as error:
        failure = str(error)
        # Killing this owned host closes the lease. The supervisor has its own 3s guard.
        process.kill()
        process.wait(timeout=1)
    finally:
        selector.close()
        process.stdin.close()
        process.stdout.close()
        process.stderr.close()
    host = next((event for event in events if event['event'] == 'host'), {})
    worker = next((event for event in events if event['event'] == 'worker-ready'), {})
    supervisor = next((event for event in events if event['event'] == 'supervisor'), {})
    stopped = next((event for event in events if event['event'] == 'stopped'), {})
    launched = json.loads(launch_marker.read_text()) if launch_marker.exists() else None
    sample_seconds = (stopped.get('userCPURaw', 0) + stopped.get('systemCPURaw', 0)) * stopped.get('timebaseNumerator', 0) / max(1, stopped.get('timebaseDenominator', 0)) / 1e9
    access_errors = [errno.EPERM, errno.EACCES]
    checks = {
        'externalDeadline': failure is None and time.monotonic() < deadline,
        'distinctOwnedChild': worker.get('pid') == supervisor.get('childPID') and
            worker.get('parentPID') == supervisor.get('pid') == host.get('supervisorPID') and
            len({worker.get('pid'), host.get('pid'), supervisor.get('pid')}) == 3,
        'zeroProcessLimit': worker.get('processSoftLimit') == 0 and worker.get('processHardLimit') == 0,
        'trustedParentLimitsUnchanged': host.get('processSoftLimit', 0) > 0 and host.get('processSoftLimit') == supervisor.get('processSoftLimit') and host.get('processHardLimit') == supervisor.get('processHardLimit'),
        'limitCannotBeRaised': worker.get('raiseResult') == -1 and worker.get('raiseErrno') == errno.EPERM,
        'subprocessDenied': worker.get('spawnErrno') in [errno.EAGAIN, errno.EPERM, errno.EACCES],
        'delegatedLaunchDenied': worker.get('launchServicesStatus') not in [None, 0] and launched is None and worker.get('launchFixtureReadable') is True,
        'foreignFileDenied': worker.get('foreignFileResult') == -1 and worker.get('foreignFileErrno') in access_errors,
        'networkDenied': worker.get('networkResult') == -1 and worker.get('networkErrno') in access_errors,
        'cannotSignalSupervisor': worker.get('signalParentResult') == -1 and worker.get('signalParentErrno') == errno.EPERM and not stopped.get('receivedChildSignal'),
        'reapedAfterSIGKILL': stopped.get('reaped') is True and stopped.get('signal') == 9 and stopped.get('stopErrno') == 0,
        'correctStopReason': stopped.get('reason') == ('host-lease-closed' if case in ('host-exit', 'host-crash') else 'explicit-stop'),
        'hostBehavior': any(event['event'] == 'host-alive-after-stop' for event in events) if host_case == 'explicit-stop' else process.returncode == (0 if case == 'host-exit' else -9),
        'cpuMeasured': stopped.get('metricSamples', 0) >= 2 and stopped.get('cpuDeltaRaw', 0) > 0 and stopped.get('metricErrno') == 0,
        'cpuUnitsCrossChecked': stopped.get('wait4CPUSeconds', 0) * 0.5 < sample_seconds <= stopped.get('wait4CPUSeconds', 0) * 1.1,
        'footprintMeasured': stopped.get('footprintBytes', 0) >= 16 * 1024 * 1024,
    }
    cost = next((event for event in events if event['event'] == 'trusted-cost'), {})
    if case == 'supervisor-crash':
        checks['supervisorDeathStopsWorker'] = stopped.get('reaped') is True
        checks['orphanSurvivalObserved'] = any(e['event'] == 'orphan-observed' and e.get('pid') == worker.get('pid') and e.get('fixtureMatch') is True for e in events)
        checks['supervisorCrashInjected'] = any(e['event'] == 'supervisor-crash' for e in events)
    if case == 'exec-replacement':
        checks.update(exec_checks(events, worker.get('pid'), failure))
    unverified = ['authenticated session invalidation after exec'] if case == 'exec-replacement' else []
    if benchmark:
        latencies = [e['milliseconds'] for e in events if e['event'] == 'echo-latency']
        sequences = [e.get('sequence') for e in events if e['event'] == 'echo']
        target = 20 if case == 'benchmark-reuse' else 1
        checks = {'externalDeadline': checks['externalDeadline'], 'reapedAfterSIGKILL': checks['reapedAfterSIGKILL'],
                  'echoSequence': sequences == list(range(1, target + 1)),
                  'latenciesObserved': len(latencies) == target,
                  'trustedMetricsReadable': cost.get('samples', 0) > 0}
        benchmark_costs[case].append(dict(latencies=latencies, workerCPUSeconds=sample_seconds,
            wait4CPUSeconds=stopped.get('wait4CPUSeconds'), cost=cost,
            totalMilliseconds=(time.monotonic() - started) * 1000))
    passed = all(checks.values()) and not unverified
    all_passed &= passed
    record = {'schemaVersion': 1, 'scenario': case, 'case': case, 'iteration': iteration,
              'status': 'PASS' if passed else 'FAIL', 'checks': checks, 'unverified': unverified,
              'observations': {'events': events, 'delegatedLaunchObserved': launched,
                  'sampleCPUSeconds': round(sample_seconds, 6), 'stderr': errors.decode(errors='replace')[-4000:]},
              'elapsedMilliseconds': round((time.monotonic() - started) * 1000, 2), 'failure': failure}
    results.append(record)
    print(json.dumps(record), flush=True)

summary = {}
for mode, runs in benchmark_costs.items():
    latencies = sorted(value for run in runs for value in run['latencies'])
    summary[mode] = {'requests': len(latencies), 'runs': len(runs),
        'p95IPCReplyMilliseconds': latencies[max(0, int(len(latencies) * .95 + .999) - 1)] if latencies else None,
        'totalMilliseconds': sum(run['totalMilliseconds'] for run in runs) + (380 if mode == 'benchmark-immediate' else 0),
        'nominalInterRequestQuietMilliseconds': 20,
        'workerWait4CPUSeconds': sum(run['wait4CPUSeconds'] or 0 for run in runs),
        'supervisorCPUSeconds': sum(run['cost'].get('supervisorCPURaw', 0) * run['cost'].get('timebaseNumerator', 0) / max(1, run['cost'].get('timebaseDenominator', 0)) / 1e9 for run in runs),
        'sampledHostSupervisorCPUSeconds': sum((run['cost'].get('hostCPURaw', 0) + run['cost'].get('supervisorCPURaw', 0)) * run['cost'].get('timebaseNumerator', 0) / max(1, run['cost'].get('timebaseDenominator', 0)) / 1e9 for run in runs),
        'peakHostSupervisorFootprintBytes': max((run['cost'].get('hostSupervisorPeakFootprintBytes', 0) for run in runs), default=0)}
print(json.dumps({'event': 'benchmark-summary', 'observations': summary, 'reuseSelected': False,
                  'unverified': ['launcher admission blocked; benchmark is diagnostic only', 'energy', 'host full-lifetime CPU']}), flush=True)
base = {record['case']: record for record in results[:3]}
admission = {'schemaVersion': 1, 'scenario': 'launcher-admission',
    'checks': {'managedStop': all(base['explicit-stop']['checks'][key] for key in ('reapedAfterSIGKILL', 'correctStopReason', 'hostBehavior', 'externalDeadline')),
        'hostExitCleanup': all(base['host-exit']['checks'][key] for key in ('reapedAfterSIGKILL', 'correctStopReason', 'hostBehavior', 'externalDeadline')),
        'hostCrashCleanup': all(base['host-crash']['checks'][key] for key in ('reapedAfterSIGKILL', 'correctStopReason', 'hostBehavior', 'externalDeadline')),
        # A retained PID is insufficient when exec keeps the old session alive.
        'identitySafe': next(record for record in results if record['case'] == 'exec-replacement')['checks']['sessionInvalidatedAfterExec'],
        'cpuReadable': all(record['checks']['cpuMeasured'] for record in results[:3]),
        'footprintReadable': all(record['checks']['footprintMeasured'] for record in results[:3]),
        'delegatedWorkControlled': all(record['checks']['delegatedLaunchDenied'] for record in results[:3])},
    'observations': {'cases': results, 'benchmarks': summary},
    'unverified': ['cross-publisher admission', 'macOS 14/15/26', 'authenticated session invalidation after exec',
                   'supervisor crash cleanup independent of worker cooperation']}
evidence_path = pathlib.Path(__file__).parent / 'Results/launcher-admission.json'
evidence_path.write_text(json.dumps(admission, indent=2) + '\n')
listener.close()
sys.exit(0 if all_passed else 1)
