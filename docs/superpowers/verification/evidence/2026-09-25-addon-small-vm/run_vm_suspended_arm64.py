"""One bounded suspended-launch diagnostic, exclusively inside a disposable VM.

Existing signed images are reused without rebuilding or changing entitlements.
The host must qualify whole-VM stop first and collect this script's JSONL output.
launchctl print is diagnostic setup, never an identity or production discovery API.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import time

EV_RECEIPT = 0x0040
EV_ERROR = 0x4000
NOTE_EXITSTATUS = 0x04000000
NOTE_EXIT = 0x80000000
PROVIDER_ID = 'hylo.Cascade.AddonProbeContainer.Provider'
MODES = ('release-control', 'broker-stop', 'broker-crash', 'root-quit', 'root-crash')


def now():
    return time.clock_gettime(time.CLOCK_MONOTONIC)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def guest_allowed(flag, model, uid):
    return flag == '1' and bool(re.fullmatch(r'VirtualMac\d+,\d+', model)) and uid != 0


def classify(r):
    """Only observed exits before all live guards can qualify; cleanup cannot repair a result."""
    try:
        if r.get('error') or r['mode'] not in MODES:
            return 'FAIL'
        for key in ('guestVerified', 'inputsVerified', 'cleanupQualified', 'cleanupComplete', 'observerAlive'):
            if r.get(key) is not True:
                return 'UNKNOWN'
        identity, receipt = r['identity'], r['registration']
        pid, audit, trigger = identity['pid'], identity['audit'], r['trigger']
        if (len(audit) != 8 or audit[5] != pid or audit == r['firstAudit'] or
                r['helloBeforeTrigger'] or r['firstExit']['status'] != 0 or
                r['firstExit']['time'] >= r['firstGuard']):
            return 'FAIL'
        for event in (identity, r['confirmed'], r['beforeTrigger']):
            if (event['authenticated'] is not True or event['audit'] != audit or event['pid'] != pid or
                    event['basicInfoStatus'] != 0 or event['suspendCount'] <= 0):
                return 'FAIL'
        if (receipt['pid'] != pid or receipt['data'] != 0 or not receipt['flags'] & EV_ERROR or
                not r['firstExit']['time'] <= r['debugArmed'] < r['secondHelloRequested'] <= identity['time']
                <= receipt['time'] <= r['confirmed']['time'] <= r['beforeTrigger']['time'] < trigger):
            return 'FAIL'
        deadline = min(r['brokerGuard'], r['rootGuard'], identity['guardDeadline'])
        if trigger + 9 >= deadline:
            return 'FAIL'
        provider, broker = r['providerExit'], r['brokerExit']
        for event in (provider, broker):
            if (not event['fflags'] & NOTE_EXIT or not event['fflags'] & NOTE_EXITSTATUS or
                    not trigger <= event['time'] < deadline or event['status'] not in (0, 9, 15)):
                return 'FAIL'
        if provider['pid'] != pid or not trigger <= r['rootExitObserved'] < r['rootGuard']:
            return 'FAIL'
        expected_root = -9 if r['mode'] == 'root-crash' else 0
        if r['rootStatus'] != expected_root:
            return 'FAIL'
        if r['mode'] in ('broker-stop', 'broker-crash'):
            if broker['status'] != (0 if r['mode'] == 'broker-stop' else 9) or r.get('rootSurvivedFault') is not True:
                return 'FAIL'
        if r['mode'] == 'release-control':
            hello, resumed = r['resumedHello'], r['resumed']
            if (hello['authenticated'] is not True or hello['provider']['authenticated'] is not True or
                    hello['provider']['pid'] != pid or hello['provider']['instance'] == r['firstInstance'] or
                    resumed['audit'] != audit or resumed['authenticated'] is not True or
                    resumed['basicInfoStatus'] != 0 or resumed['suspendCount'] != 0 or
                    not trigger <= resumed['time'] <= r['providerStop'] <= provider['time'] or
                    provider['time'] >= hello['provider']['guardDeadline'] or provider['status'] != 0):
                return 'FAIL'
        return 'PASS'
    except (KeyError, TypeError, ValueError):
        return 'UNKNOWN'


def emit(event, **fields):
    print(json.dumps(dict(event=event, observed=now(), **fields), sort_keys=True), flush=True)


class Stream:
    def __init__(self, process, role, record):
        self.process, self.role, self.record, self.buffer = process, role, record, b''

    def command(self, name):
        emit('command', role=self.role, command=name)
        self.process.stdin.write((name + '\n').encode())
        self.process.stdin.flush()

    def read(self, timeout):
        if b'\n' not in self.buffer:
            readable, _, _ = select.select([self.process.stdout], [], [], timeout)
            if not readable:
                return None
            data = os.read(self.process.stdout.fileno(), 16384)
            if not data:
                raise RuntimeError(self.role + ' output ended')
            self.buffer += data
            if len(self.buffer) > 65536:
                raise RuntimeError('output bound exceeded')
            if b'\n' not in self.buffer:
                return None
        line, self.buffer = self.buffer.split(b'\n', 1)
        event = json.loads(line)
        self.record.append(dict(role=self.role, received=now(), payload=event))
        emit('fixture-event', role=self.role, payload=event)
        return event

    def expect(self, name, timeout=3, reject=(), ignore_errors=False):
        deadline = now() + timeout
        while now() < deadline:
            event = self.read(max(0, deadline - now()))
            if event is None:
                continue
            if event.get('event') in reject or (not ignore_errors and event.get('event', '').endswith('error')):
                raise RuntimeError(str(event))
            if event.get('event') == name:
                return event
        raise TimeoutError(self.role + ': ' + name)

    def drain(self):
        while True:
            event = self.read(0)
            if event is None:
                return
            if event.get('event', '').endswith('error'):
                raise RuntimeError(str(event))


def run(args):
    model = subprocess.run(['/usr/sbin/sysctl', '-n', 'hw.model'], capture_output=True,
                           text=True, check=True, timeout=2).stdout.strip()
    if not guest_allowed(os.environ.get('CASCADE_DISPOSABLE_VM'), model, os.getuid()):
        raise RuntimeError('Refusing: explicit disposable VirtualMac guest and nonroot user required')
    qualification = json.loads(args.cleanup_qualification.read_text())
    if (qualification.get('managerCleanupQualified') is not True or
            qualification.get('vmIdentifier') != args.vm_identifier or
            not re.fullmatch('[a-f0-9]{64}', qualification.get('stopEvidenceSHA256', ''))):
        raise RuntimeError('Refusing: matching external whole-VM cleanup qualification required')
    args.output.mkdir(parents=True, exist_ok=False)
    r = dict(mode=args.mode, guestVerified=True, cleanupQualified=True, model=model,
             vmIdentifier=args.vm_identifier, qualification=qualification,
             qualificationSHA256=sha(args.cleanup_qualification), runnerSHA256=sha(__file__),
             events=[], commands=[], launcherAdmitted=False,
             scope='diagnostic suspended second EF launch; no xpcproxy or first-launch claim')
    (args.output / 'runner.py').write_bytes(Path(__file__).read_bytes())
    original = json.loads(args.manifest.read_text())
    r['manifestSHA256'] = sha(args.manifest)
    (args.output / 'build.json').write_bytes(args.manifest.read_bytes())
    # The immutable manifest contains host paths. Rebase only known path fields.
    old_products = Path(original['taskObserver']).parent
    manifest = dict(original)
    for key in ('host', 'container', 'provider', 'brokerHost', 'taskObserver'):
        manifest[key] = str(args.products / Path(original[key]).relative_to(old_products))
    r['rebasedPaths'] = {key: manifest[key] for key in ('container', 'provider', 'brokerHost', 'taskObserver')}
    children, files, queue, root, output = [], [], None, None, None

    def command(argv, timeout=3, check=True, record_stdout=True):
        item = dict(argv=argv, started=now())
        result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        item.update(status=result.returncode, stdout=result.stdout if record_stdout else '[discovery listing omitted]',
                    stderr=result.stderr, finished=now())
        r['commands'].append(item); emit('subprocess', **item)
        if check:
            result.check_returncode()
        return result

    def child(argv, role):
        error = (args.output / (role + '.stderr')).open('wb'); files.append(error)
        process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=error,
            bufsize=0, env=dict(os.environ, CASCADE_RECOVERY_PROVIDER_BUNDLE=manifest['provider']))
        children.append(process)
        return process, Stream(process, role, r['events'])

    def observe(pid, role):
        process, stream = child([manifest['taskObserver'], str(pid), manifest['providerRequirement'],
                                 manifest['provider']], role)
        identity = stream.expect('external-identity')
        receipt = stream.expect('registered')
        confirmed = stream.expect('external-confirmed')
        if (identity.get('authenticated') is not True or identity['pid'] != pid or
                identity['audit'] != confirmed['audit'] or receipt['pid'] != pid or
                receipt['data'] or not receipt['flags'] & EV_ERROR):
            raise RuntimeError('external binding failed')
        return process, stream, identity, receipt, confirmed

    def same_broker(value):
        if value.get('authenticated') is not True or any(value.get(key) != r['broker'].get(key)
                for key in ('brokerPID', 'brokerInstance', 'brokerGuard', 'brokerPath')):
            raise RuntimeError('broker changed across observation')

    def broker_exit(timeout=3):
        events = queue.control(None, 1, timeout)
        if len(events) != 1:
            raise TimeoutError('broker kernel exit missing')
        event = events[0]
        if (event.ident != r['broker']['brokerPID'] or event.filter != select.KQ_FILTER_PROC or
                event.flags & EV_ERROR or not event.fflags & NOTE_EXIT or not event.fflags & NOTE_EXITSTATUS):
            raise RuntimeError('unexpected broker kernel event')
        r['brokerExit'] = dict(time=now(), pid=int(event.ident), flags=event.flags,
                               fflags=event.fflags, status=int(event.data))
        emit('broker-exit', payload=r['brokerExit'])

    try:
        for directory, key in ((args.products / 'Sources', 'sourceHashes'), (args.products, 'binaries')):
            for relative, digest in original[key].items():
                path = (directory / relative).resolve()
                if not path.is_relative_to(directory.resolve()) or sha(path) != digest:
                    raise RuntimeError('changed input: ' + relative)
        for path in (manifest['container'], str(Path(manifest['brokerHost']).parents[2]), manifest['taskObserver']):
            command(['/usr/bin/codesign', '--verify', '--strict', '--deep', path])
        command(['/usr/bin/codesign', '--verify', '--strict', '--arch', 'arm64', '-R', '=' + manifest['providerRequirement'], manifest['provider']])
        r['inputsVerified'] = True
        r['guestVersion'] = command(['/usr/bin/sw_vers']).stdout
        r['guestKernel'] = command(['/usr/bin/uname', '-a']).stdout
        command(['/usr/bin/sudo', '-n', '/bin/launchctl', 'help', 'debug'])
        command(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                 '-f', manifest['container']])
        command(['/usr/bin/open', '-g', manifest['container']])
        r['rootStarted'] = now(); r['rootGuard'] = r['rootStarted'] + 45
        root, output = child([manifest['brokerHost']], 'root')
        r['rootPID'] = root.pid
        output.expect('client-ready')
        output.command('broker-info'); r['broker'] = output.expect('broker-info')
        same_broker(r['broker']); r['brokerGuard'] = r['broker']['brokerGuard']
        queue = select.kqueue()
        receipt = queue.control([select.kevent(r['broker']['brokerPID'], filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT | EV_RECEIPT,
            fflags=NOTE_EXIT | NOTE_EXITSTATUS)], 1, 0)
        if (len(receipt) != 1 or receipt[0].ident != r['broker']['brokerPID'] or receipt[0].data or
                receipt[0].filter != select.KQ_FILTER_PROC or not receipt[0].flags & EV_ERROR):
            raise RuntimeError('broker registration rejected')
        r['brokerRegistration'] = dict(time=now(), pid=int(receipt[0].ident), flags=receipt[0].flags, data=int(receipt[0].data))
        output.command('broker-info'); same_broker(output.expect('broker-info'))
        output.command('hello'); first = output.expect('hello', timeout=10); same_broker(first)
        r.update(firstHello=first, firstPID=first['provider']['pid'], firstGuard=first['provider']['guardDeadline'],
                 firstInstance=first['provider']['instance'])
        _, old, identity, _, _ = observe(r['firstPID'], 'old-observer'); r['firstAudit'] = identity['audit']
        old.command('confirm'); old.expect('external-reconfirmed')
        output.command('finish-provider'); output.expect('finish-provider')
        old.command('watch'); r['firstExit'] = old.expect('kernel-exit', timeout=9)
        if r['firstExit']['status'] != 0 or r['firstExit']['time'] >= r['firstGuard']:
            raise RuntimeError('first provider did not exit cooperatively before guard')
        old.command('quit')
        output.command('release'); output.expect('release')
        target = 'pid/' + str(r['broker']['brokerPID']) + '/' + PROVIDER_ID
        r['jobTarget'] = target
        inactive = command(['/bin/launchctl', 'print', target])
        # The label is derived only from our authenticated broker and fixed fixture.
        # Diagnostic formatting is intentionally fail-closed, never a production API.
        if (not re.search(r'^\s*state = not running\s*$', inactive.stdout, re.M) or
                not re.search(r'^\s*path = ' + re.escape(manifest['provider']) + r'\s*$', inactive.stdout, re.M)):
            raise RuntimeError('exact inactive fixture job not established')
        output.command('broker-info'); same_broker(output.expect('broker-info'))
        if now() + 14 >= min(r['brokerGuard'], r['rootGuard']):
            raise RuntimeError('insufficient guard budget before arming')
        command(['/usr/bin/sudo', '-n', '/bin/launchctl', 'debug', target, '--start-suspended'])
        r['debugArmed'] = now()
        r['secondHelloRequested'] = now(); output.command('hello')  # Remains pending while provider is parked.
        executable = str(Path(manifest['provider']) / 'Contents/MacOS/ProbeProvider')
        deadline = now() + 4
        while now() < deadline:
            listing = command(['/bin/ps', '-ax', '-o', 'pid=,comm='], record_stdout=False)
            candidates = [int(parts[0]) for line in listing.stdout.splitlines()
                          if len(parts := line.strip().split(None, 1)) == 2 and parts[1] == executable]
            if len(candidates) == 1:
                r['candidateDiscovery'] = dict(time=now(), pid=candidates[0], executable=executable)
                break
            if len(candidates) > 1:
                raise RuntimeError('multiple provider candidates')
            time.sleep(.025)
        else:
            raise TimeoutError('parked provider image not discovered')
        observer, parked, r['identity'], r['registration'], r['confirmed'] = observe(candidates[0], 'parked-observer')
        output.command('broker-info'); r['parkedBroker'] = output.expect('broker-info', reject=('hello',))
        same_broker(r['parkedBroker'])
        parked.command('confirm'); r['beforeTrigger'] = parked.expect('external-reconfirmed')
        output.drain()
        r['helloBeforeTrigger'] = any(item['role'] == 'root' and item['received'] >= r['secondHelloRequested']
            and item['payload'].get('event') == 'hello' for item in r['events'])
        if (r['helloBeforeTrigger'] or any(item['basicInfoStatus'] or item['suspendCount'] <= 0
                for item in (r['identity'], r['confirmed'], r['beforeTrigger'])) or
                now() + 9 >= min(r['brokerGuard'], r['rootGuard'], r['identity']['guardDeadline'])):
            raise RuntimeError('suspension or guard precondition failed')
        if queue.control(None, 1, 0):
            raise RuntimeError('broker event before trigger')
        r['trigger'] = now(); emit('fault-trigger', mode=args.mode, time=r['trigger'])
        if args.mode == 'release-control':
            command(['/usr/bin/sudo', '-n', '/bin/launchctl', 'kill', 'SIGCONT', target])
            r['resumedHello'] = output.expect('hello', timeout=4); same_broker(r['resumedHello'])
            parked.command('confirm'); r['resumed'] = parked.expect('external-reconfirmed')
            r['providerStop'] = now(); output.command('finish-provider'); output.expect('finish-provider')
        else:
            output.command({'broker-stop': 'stop-broker', 'broker-crash': 'crash-broker',
                            'root-quit': 'quit', 'root-crash': 'crash'}[args.mode])
        parked.command('watch'); r['providerExit'] = parked.expect('kernel-exit', timeout=9)
        if args.mode == 'release-control':
            output.command('quit')
        if args.mode in ('broker-stop', 'broker-crash'):
            broker_exit()
            # Root must stay responsive after the observed selective broker failure.
            output.command('ping'); ping = output.expect('ping', ignore_errors=True)
            r['rootSurvivedFault'] = ping.get('pid') == root.pid and root.poll() is None
            output.command('quit')
        r['rootStatus'] = root.wait(timeout=3); r['rootExitObserved'] = now()
        if 'brokerExit' not in r:
            broker_exit()
        parked.command('ping'); ping = parked.expect('observer-ping')
        r['observerAlive'] = ping.get('pid') == observer.pid and observer.poll() is None
        r['cleanupComplete'] = True
    except (OSError, RuntimeError, ValueError, KeyError, TimeoutError, subprocess.SubprocessError) as error:
        r['error'] = repr(error)
    finally:
        # Freeze the measured result BEFORE cleanup: later root quit or VM stop cannot manufacture PASS.
        r['classification'] = classify(r)
        r['hostStopRequired'] = r['classification'] != 'PASS'
        (args.output / 'result.json').write_text(json.dumps(r, indent=2) + '\n')
        emit('measurement-result', payload=r)
        cleanup = []
        for process in children:
            if process.poll() is None:
                try:
                    process.stdin.write(b'quit\n'); process.stdin.flush(); process.wait(timeout=.5)
                except (OSError, subprocess.TimeoutExpired):
                    pass  # The host's qualified whole-VM stop is the final containment boundary.
            cleanup.append(dict(pid=process.pid, status=process.poll()))
            process.stdin.close(); process.stdout.close()
        for file in files:
            file.close()
        if queue is not None:
            queue.close()
        (args.output / 'post-measurement-cleanup.json').write_text(json.dumps(cleanup, indent=2) + '\n')
        emit('post-measurement-cleanup', children=cleanup, hostStopRequired=r['hostStopRequired'])
    return 0 if r['classification'] == 'PASS' else 2


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=MODES, required=True)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--products', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cleanup-qualification', type=Path, required=True)
    parser.add_argument('--vm-identifier', required=True)
    arguments = parser.parse_args()
    for field in ('manifest', 'products', 'output', 'cleanup_qualification'):
        setattr(arguments, field, getattr(arguments, field).resolve())
    try:
        raise SystemExit(run(arguments))
    except (OSError, RuntimeError, ValueError, KeyError, subprocess.SubprocessError) as error:
        emit('runner-refused', error=repr(error)); raise SystemExit(78)
