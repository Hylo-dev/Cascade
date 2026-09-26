"""Diagnostic preflight: authenticate a normal EF provider without a provider HELLO.

PID/path discovery only supplies a candidate. TaskObserver binds the kernel audit
token to the pinned signature before the runner uses the external observation.
No suspended launch, signal, debugger attach, or launcher admission here.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import sys
import time

SOURCE = Path(__file__).resolve().parent
PLATFORM = SOURCE.parent
sys.path.insert(0, str(PLATFORM / 'BrokerRecovery'))
from run_broker_recovery import build as build_broker
from run_recovery import register_container
from run_probe import Output, native_time, SIGNER, EV_RECEIPT, NOTE_EXITSTATUS


def build():
    products = build_broker(compilation_conditions=('STARTUP_PROBE',))
    manifest = json.loads((products / 'build.json').read_text())
    sources = products / 'Sources'
    shutil.copytree(SOURCE, sources / 'ExternalIdentity', ignore=shutil.ignore_patterns('__pycache__'))
    observer = products / 'TaskObserver'
    environment = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer')
    with (products / 'external-build.log').open('w') as log:
        for args in [
            ['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-O2', '-mmacosx-version-min=14.0',
             str(sources / 'ExternalIdentity/TaskObserver.c'), '-framework', 'Security',
             '-framework', 'CoreFoundation', '-lbsm', '-o', str(observer)],
            ['codesign', '--force', '--timestamp=none', '--options', 'runtime', '--sign', SIGNER,
             '--identifier', 'hylo.Cascade.AddonProbe.TaskObserver', str(observer)],
            ['codesign', '--verify', '--strict', str(observer)],
            ['codesign', '-d', '--entitlements', '-', '--xml', str(observer)],
        ]:
            manifest['commands'].append(args)
            subprocess.run(args, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
    signature = subprocess.run(['codesign', '--arch', 'arm64', '-dvvv', manifest['provider']],
                               capture_output=True, text=True, check=True)
    digest = re.search(r'^CDHash=([0-9a-fA-F]{40})$', signature.stderr, re.MULTILINE)
    if not digest: raise RuntimeError('missing provider CDHash')
    (products / 'external-provider-signature.txt').write_text(signature.stderr)
    requirement = (f'anchor apple generic and identifier "hylo.Cascade.AddonProbeContainer.Provider" '
                   f'and certificate leaf = H"{SIGNER}" and cdhash H"{digest[1]}"')
    manifest.update(taskObserver=str(observer), providerRequirement=requirement, providerCDHash=digest[1])
    manifest['sourceHashes'] = {str(p.relative_to(sources)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sources.rglob('*') if p.is_file()}
    manifest['runnerHashes']['ExternalIdentity/run_identity.py'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    manifest['binaries']['TaskObserver'] = hashlib.sha256(observer.read_bytes()).hexdigest()
    (products / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return products


def snapshot(products, label, pids):
    record = []
    for role, pid in pids.items():
        command = ['launchctl', 'print', f'pid/{pid}']
        result = subprocess.run(command, capture_output=True, text=True, timeout=2)
        path = products / f'external-{label}-{role}-launchctl.txt'
        path.write_text(result.stdout + result.stderr)
        record.append(dict(command=command, status=result.returncode, path=path.name))
    return record


def run(products, debug_preflight=False):
    manifest = json.loads((products / 'build.json').read_text())
    for root, key in ((products / 'Sources', 'sourceHashes'), (PLATFORM, 'runnerHashes'), (products, 'binaries')):
        for relative, digest in manifest[key].items():
            if hashlib.sha256((root / relative).read_bytes()).hexdigest() != digest:
                raise RuntimeError('changed input: ' + relative)
    register_container(manifest, products)
    record = dict(events=[], observer=dict(events=[]), launcherAdmitted=False,
                  purpose='external identity and diagnostic job persistence; no preinstruction claim')
    observers = []
    broker_queue = select.kqueue()
    errors = (products / 'external-root.stderr').open('wb')
    root = subprocess.Popen([manifest['brokerHost']], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=errors, bufsize=0, env=dict(os.environ, CASCADE_RECOVERY_PROVIDER_BUNDLE=manifest['provider']))
    output = Output(root, record)
    record['rootPID'] = root.pid
    try:
        output.expect('client-ready')
        output.command('begin-startup'); broker = output.expect('begin-startup')
        if broker.get('authenticated') is not True: raise RuntimeError('broker not authenticated')
        record['broker'] = broker
        receipts = broker_queue.control([select.kevent(broker['brokerPID'], filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT | EV_RECEIPT,
            fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)], 1, 0)
        if len(receipts) != 1 or receipts[0].data != 0 or not receipts[0].flags & select.KQ_EV_ERROR:
            raise RuntimeError('broker receipt rejected')
        output.command('broker-info'); after_receipt = output.expect('broker-info')
        if any(after_receipt.get(k) != broker.get(k) for k in ('brokerPID', 'brokerInstance', 'brokerGuard', 'brokerPath')):
            raise RuntimeError('broker changed across registration')
        deadline = native_time() + 4
        executable = str(Path(manifest['provider']) / 'Contents/MacOS/ProbeProvider')
        candidates = []
        while native_time() < deadline:
            listing = subprocess.run(['ps', '-ax', '-o', 'pid=,comm='], capture_output=True, text=True, check=True)
            candidates = [int(line.strip().split(None, 1)[0]) for line in listing.stdout.splitlines()
                          if len(line.strip().split(None, 1)) == 2 and line.strip().split(None, 1)[1] == executable]
            if candidates: break
            time.sleep(.025)
        if len(candidates) != 1: raise RuntimeError('no unique provider candidate')
        record['candidatePID'] = candidates[0]
        # Negative control: exact same observer must reject the retained root,
        # which is signed by the same leaf but has the wrong bundle identifier.
        negative = subprocess.run([manifest['taskObserver'], str(root.pid), manifest['providerRequirement'],
                                   manifest['provider']], input='quit\n', capture_output=True, text=True, timeout=3)
        record['negative'] = dict(status=negative.returncode, stdout=negative.stdout, stderr=negative.stderr)
        if negative.returncode != 90 or '"stage":"signature-or-path"' not in negative.stdout:
            raise RuntimeError('negative signature control did not reject at authentication')
        observer = subprocess.Popen([manifest['taskObserver'], str(candidates[0]), manifest['providerRequirement'],
                                     manifest['provider']], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=(products / 'external-observer.stderr').open('wb'), bufsize=0)
        observers.append(observer)
        observed = Output(observer, record['observer'])
        record['identity'] = observed.expect('external-identity')
        record['registration'] = observed.expect('registered')
        record['confirmed'] = observed.expect('external-confirmed')
        if record['identity']['audit'] != record['confirmed']['audit']: raise RuntimeError('changed audit')
        # begin-startup is asynchronous. HELLO must not start a second launch.
        ready_deadline = native_time() + 3
        while True:
            output.command('broker-info'); phase = output.expect('broker-info')
            if phase.get('startupPhase') == 'channel-ready': break
            if native_time() >= ready_deadline: raise RuntimeError('channel not ready')
            time.sleep(.025)
        record['firstHelloRequested'] = native_time()
        output.command('hello'); hello = output.expect('hello')
        record['hello'] = hello
        if hello.get('authenticated') is not True or hello['provider']['pid'] != candidates[0]:
            raise RuntimeError('HELLO does not match external binding')
        observed.command('confirm'); record['reconfirmed'] = observed.expect('external-reconfirmed')
        if record['confirmed']['audit'] != record['reconfirmed']['audit']: raise RuntimeError('changed audit')
        record['externalIdentityVerified'] = True
        observed.command('control-check'); record['controlCheck'] = observed.expect('control-check', timeout=3)
        pids = dict(root=root.pid, broker=broker['brokerPID'], provider=candidates[0])
        record['liveSnapshots'] = snapshot(products, 'live', pids)
        observed.command('confirm'); record['beforeStop'] = observed.expect('external-reconfirmed')
        record['stopRequested'] = native_time()
        output.command('finish-provider'); output.expect('finish-provider')
        observed.command('watch'); record['exit'] = observed.expect('kernel-exit', timeout=9)
        if record['exit']['time'] >= hello['provider']['guardDeadline']:
            raise RuntimeError('exit not observed before provider guard')
        record['inactiveSnapshots'] = snapshot(products, 'inactive', dict(root=root.pid, broker=broker['brokerPID']))
        if debug_preflight:
            # This exact label was observed in the prior native preflight. Only
            # configure an unused diagnostic variable, never suspension here.
            target = f"pid/{broker['brokerPID']}/hylo.Cascade.AddonProbeContainer.Provider"
            before = subprocess.run(['launchctl', 'print', target], capture_output=True, text=True, timeout=2)
            (products / 'external-inactive-service.txt').write_text(before.stdout + before.stderr)
            if before.returncode or 'state = not running' not in before.stdout:
                raise RuntimeError('inactive service target not established')
            command = ['launchctl', 'debug', target, '--environment', 'CASCADE_PROBE_DEBUG_PREFLIGHT=1']
            result = subprocess.run(command, capture_output=True, text=True, timeout=2)
            record['debugPreflight'] = dict(command=command, status=result.returncode,
                                            stdout=result.stdout, stderr=result.stderr)
        output.command('release'); output.expect('release', allow_terminal=True)
        output.command('hello'); fresh = output.expect('hello', timeout=12)
        record['replacementHello'] = fresh
        if fresh['brokerInstance'] != broker['brokerInstance'] or fresh['provider']['instance'] == hello['provider']['instance']:
            raise RuntimeError('replacement changed broker or reused provider instance')
        record['replacementSnapshots'] = snapshot(products, 'replacement', dict(root=root.pid, broker=broker['brokerPID'], provider=fresh['provider']['pid']))
        replacement = subprocess.Popen([manifest['taskObserver'], str(fresh['provider']['pid']),
            manifest['providerRequirement'], manifest['provider']], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        observers.append(replacement)
        record['replacementObserver'] = dict(events=[])
        fresh_output = Output(replacement, record['replacementObserver'])
        fresh_output.expect('external-identity'); fresh_output.expect('registered')
        fresh_output.expect('external-confirmed')
        output.command('quit'); output.expect('quit', allow_terminal=True); root.wait(timeout=2)
        record['rootStatus'] = root.returncode
        fresh_output.command('watch'); record['replacementExit'] = fresh_output.expect('kernel-exit', timeout=9)
        broker_events = broker_queue.control(None, 1, 8)
        if (len(broker_events) != 1 or broker_events[0].ident != broker['brokerPID']
                or broker_events[0].flags & select.KQ_EV_ERROR or not broker_events[0].fflags & select.KQ_NOTE_EXIT):
            raise RuntimeError('missing broker exit')
        record['brokerExit'] = dict(time=native_time(), status=int(broker_events[0].data))
        record['cleanupComplete'] = True
    except (OSError, RuntimeError, ValueError, KeyError, TimeoutError, subprocess.TimeoutExpired) as error:
        record['error'] = repr(error)
    finally:
        if root.poll() is None:
            try: output.command('quit'); root.wait(timeout=2)
            except (OSError, subprocess.TimeoutExpired): root.kill(); root.wait(timeout=1)
        record['cleanupRootStatus'] = root.returncode
        for observer in observers:
            if observer.poll() is None:
                try: observer.stdin.write(b'quit\n'); observer.stdin.flush(); observer.wait(timeout=1)
                except (OSError, subprocess.TimeoutExpired): observer.kill(); observer.wait(timeout=1)
            observer.stdin.close(); observer.stdout.close()
        root.stdin.close(); root.stdout.close(); errors.close()
        broker_queue.close()
        (products / 'external-results.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({key: record.get(key) for key in ('externalIdentityVerified', 'controlCheck', 'error', 'rootStatus')}), flush=True)
    return 2 if record.get('error') else 0


if __name__ == '__main__':
    if sys.argv[1:] == ['--build-only']: print(build(), flush=True)
    elif len(sys.argv) == 3 and sys.argv[1] in ('--run', '--debug-preflight'):
        raise SystemExit(run(Path(sys.argv[2]).resolve(), debug_preflight=sys.argv[1] == '--debug-preflight'))
    else: raise SystemExit('usage: run_identity.py --build-only | --run PRODUCTS | --debug-preflight PRODUCTS')
