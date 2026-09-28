"""Observe a fixed, signed external provider while AppExtension.init is parked."""
import copy
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import socket
import stat
import subprocess
import sys

SOURCE = Path(__file__).resolve().parent
PLATFORM = SOURCE.parent
sys.path.insert(0, str(PLATFORM / 'BrokerRecovery'))
from run_broker_recovery import build as build_broker
from run_recovery import register_container
from run_probe import Output, native_time, EV_RECEIPT, NOTE_EXITSTATUS, SIGNER
from startup_evidence import classify


def build():
    products = build_broker(compilation_conditions=('STARTUP_PROBE',))
    manifest = json.loads((products / 'build.json').read_text())
    sources = products / 'Sources'
    shutil.copytree(SOURCE, sources / 'StartupObservation', ignore=shutil.ignore_patterns('__pycache__'))
    socket_path = Path.home() / 'Library/Containers/hylo.Cascade.AddonProbeContainer.Provider/Data/tmp' / ('cs-' + products.name[-8:])
    if not socket_path.parent.is_dir() or len(os.fsencode(socket_path)) >= 104 or os.path.lexists(socket_path):
        raise RuntimeError('missing fixture container or unavailable short socket path')
    configuration = sources / 'StartupObservation/SocketConfig.h'
    configuration.write_text('#define STARTUP_SOCKET_PATH ' + json.dumps(str(socket_path)) + '\n'
        + '#define STARTUP_PROVIDER_BUNDLE ' + json.dumps(manifest['provider']) + '\n')
    environment = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode-beta.app/Contents/Developer')
    provider = Path(manifest['provider']); container = Path(manifest['container'])
    observer = products / 'StartupObserver'
    with (products / 'startup-build.log').open('w') as log:
        def command(args):
            manifest['commands'].append(args)
            subprocess.run(args, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
        common = ['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-O2', '-mmacosx-version-min=14.0',
                  '-I', str(configuration.parent), str(configuration.parent / 'Observer.c')]
        command(common + ['-DSTARTUP_PROVIDER', '-c', '-o', str(products / 'StartupProvider.o')])
        command(common + ['-framework', 'Security', '-framework', 'CoreFoundation', '-lbsm', '-o', str(observer)])
        binary = provider / 'Contents/MacOS/ProbeProvider'
        command(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-O', '-target', 'arm64-apple-macos14.0',
                 '-D', 'RECOVERY_PROBE', '-D', 'BROKER_PROVIDER', '-D', 'STARTUP_PROBE',
                 str(sources / 'Provider/ProbeProvider.swift'), str(sources / 'Shared/ProbeMessage.swift'),
                 str(products / 'StartupProvider.o'), '-framework', 'Foundation', '-framework', 'ExtensionFoundation',
                 '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__info_plist',
                 '-Xlinker', str(provider / 'Contents/Info.plist'), '-o', str(binary)])
        for target, identifier, entitlements in (
                (provider, 'hylo.Cascade.AddonProbeContainer.Provider', sources / 'Provider/Provider.entitlements'),
                (container, 'hylo.Cascade.AddonProbeContainer', None),
                (observer, 'hylo.Cascade.AddonProbe.StartupObserver', None)):
            command(['codesign', '--force', '--timestamp=none', '--options', 'runtime', '--sign', SIGNER,
                     '--identifier', identifier, *(['--entitlements', str(entitlements)] if entitlements else []), str(target)])
            command(['codesign', '--verify', '--strict', '--deep', '-R',
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf = H"{SIGNER}"', str(target)])
            command(['codesign', '-d', '--entitlements', '-', '--xml', str(target)])
    manifest.update(observer=str(observer), socketPath=str(socket_path))
    manifest['sourceHashes'] = {str(p.relative_to(sources)): hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in sources.rglob('*') if p.is_file()}
    for p in SOURCE.glob('*.py'):
        manifest['runnerHashes'][str(p.relative_to(PLATFORM))] = hashlib.sha256(p.read_bytes()).hexdigest()
    for relative in list(manifest['binaries']) + ['StartupObserver']:
        manifest['binaries'][relative] = hashlib.sha256((products / relative).read_bytes()).hexdigest()
    (products / 'build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return products


class Observer:
    def __init__(self, manifest, products, label):
        self.record = dict(events=[])
        self.ready = None
        self.socket_path = Path(manifest['socketPath'])
        self.errors = (products / (label + '-observer.stderr')).open('wb')
        self.process = subprocess.Popen([manifest['observer']], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=self.errors, bufsize=0)
        self.output = Output(self.process, self.record)

    def start(self):
        self.ready = self.output.expect('observer-ready')
        if self.ready['pid'] != self.process.pid: raise RuntimeError('wrong observer PID')

    def ping(self):
        self.output.command('ping')
        return self.output.expect('observer-ping').get('pid') == self.process.pid and self.process.poll() is None

    def cleanup(self):
        try:
            if self.process.poll() is None:
                try:
                    self.output.command('quit'); self.process.wait(timeout=1)
                except (OSError, subprocess.TimeoutExpired):
                    self.process.kill(); self.process.wait(timeout=1)
            self.record['cleanupStatus'] = self.process.returncode
        finally:
            self.process.stdin.close(); self.process.stdout.close(); self.errors.close()
            if self.ready and os.path.lexists(self.socket_path):
                info = self.socket_path.lstat()
                if not stat.S_ISSOCK(info.st_mode) or (info.st_dev, info.st_ino) != (self.ready['device'], self.ready['inode']):
                    raise RuntimeError('socket pathname replaced; cleanup withheld')
                self.socket_path.unlink()


def reject_untrusted_peer(manifest, products):
    observer = Observer(manifest, products, 'negative')
    record = dict(launcherAdmitted=False)
    try:
        observer.start()
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
            peer.connect(manifest['socketPath'])
            # The Python runner is deliberately not the signed extension.
            observer.output.expect('authentication-error')
            observer.process.wait(timeout=2)
            record['rejected'] = observer.process.returncode == 91
    finally:
        observer.cleanup(); record['observer'] = observer.record
        (products / 'startup-negative.json').write_text(json.dumps(record, indent=2) + '\n')
    if record.get('rejected') is not True: raise RuntimeError('untrusted peer was not rejected')


def run_case(manifest, products, mode):
    record = dict(mode=mode, events=[], launcherAdmitted=False)
    observer = Observer(manifest, products, mode)
    root = None; errors = None; queue = select.kqueue(); pids = {}; exits = {}; identities = {}

    def register(name, identity):
        pid = identity['pid']
        if type(pid) is not int or pid <= 1 or pid in pids or pid in (root.pid, observer.process.pid):
            raise RuntimeError('invalid participant PID')
        receipts = queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE | EV_RECEIPT,
            fflags=select.KQ_NOTE_EXIT | select.KQ_NOTE_EXEC | NOTE_EXITSTATUS)], 1, 0)
        if len(receipts) != 1 or not receipts[0].flags & select.KQ_EV_ERROR or receipts[0].data != 0:
            raise RuntimeError('exit registration refused')
        identities[name] = identity; pids[pid] = name

    def observe(timeout):
        for event in queue.control(None, 4, timeout):
            if event.flags & select.KQ_EV_ERROR or event.ident not in pids: raise RuntimeError('invalid kernel event')
            if event.fflags & select.KQ_NOTE_EXEC: raise RuntimeError('fixture unexpectedly executed a different image')
            if not event.fflags & select.KQ_NOTE_EXIT: raise RuntimeError('missing exit flag')
            exits[pids[event.ident]] = dict(time=native_time(), status=int(event.data) if event.fflags & NOTE_EXITSTATUS else None)

    def wait_exits(deadline):
        while len(exits) < len(pids) and native_time() < deadline:
            observe(max(0, deadline - native_time()))

    def broker_info():
        output.command('broker-info'); info = output.expect('broker-info')
        if info.get('authenticated') is not True: raise RuntimeError('unauthenticated broker')
        return info

    try:
        observer.start()
        errors = (products / (mode + '-root.stderr')).open('wb')
        root = subprocess.Popen([manifest['brokerHost']], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=errors, bufsize=0, env=dict(os.environ, CASCADE_RECOVERY_PROVIDER_BUNDLE=manifest['provider']))
        output = Output(root, record); record['rootPID'] = root.pid
        output.expect('client-ready'); first = broker_info()
        broker = dict(pid=first['brokerPID'], instance=first['brokerInstance'],
                      guardDeadline=first['brokerGuard'], bundlePath=first['brokerPath'])
        register('broker', broker)
        second = broker_info()
        if any(second[k] != first[k] for k in ('brokerPID', 'brokerInstance', 'brokerGuard', 'brokerPath')):
            raise RuntimeError('broker incarnation changed')
        output.command('begin-startup'); output.expect('begin-startup')
        hello = observer.output.expect('initializer-observed', timeout=5)
        if hello.get('authenticated') is not True or hello.get('pathVerified') is not True or hello.get('sequence') != 0:
            raise RuntimeError('unverified initial provider observation')
        register('provider', {k: hello[k] for k in ('pid', 'instance', 'guardDeadline', 'audit')})
        observer.output.command('confirm')
        confirmed = observer.output.expect('initializer-confirmed')
        if (confirmed.get('authenticated') is not True or confirmed.get('pathVerified') is not True
                or confirmed.get('sequence') != 1 or any(confirmed[k] != hello[k]
                    for k in ('pid', 'instance', 'guardDeadline', 'audit'))):
            raise RuntimeError('provider incarnation changed across registration')
        before = broker_info(); after = broker_info()
        for info in (before, after):
            if any(info[k] != first[k] for k in ('brokerPID', 'brokerInstance', 'brokerGuard', 'brokerPath')):
                raise RuntimeError('startup broker changed')
        record.update(authenticated=True, registered=True, confirmed=True, phaseBefore=before['startupPhase'],
                      phaseAfter=after['startupPhase'], brokerGuard=broker['guardDeadline'],
                      providerGuard=hello['guardDeadline'], observerGuard=observer.ready['guardDeadline'])
        observe(0)
        if exits or native_time() + 8.5 >= min(record[k] for k in ('brokerGuard', 'providerGuard', 'observerGuard')):
            raise RuntimeError('early exit or insufficient guard margin')
        if mode == 'release-control':
            if record['phaseAfter'] not in ('initializer-pending', 'process-ready'):
                raise RuntimeError('provider was not holding startup')
            observer.output.command('release'); observer.output.expect('initializer-released')
            # Wait for this one startup task, without launching another provider.
            deadline = native_time() + 3
            while True:
                info = broker_info()
                if info['startupPhase'] == 'channel-ready': break
                if native_time() >= deadline or info['startupPhase'].startswith('failed'):
                    raise RuntimeError('released initializer did not complete startup')
                select.select([], [], [], 0.02)
            output.command('hello'); response = output.expect('hello')
            provider = response['provider']
            record['ordinaryChannelSameProvider'] = all(provider[k] == hello[k] for k in ('pid', 'instance', 'guardDeadline'))
            if not record['ordinaryChannelSameProvider']: raise RuntimeError('ordinary channel belongs to another provider')
            record['phaseAfterRelease'] = info['startupPhase']
        command = {'broker-stop':'stop-broker', 'broker-crash':'crash-broker', 'root-quit':'quit',
                   'root-crash':'crash', 'release-control':'stop-broker'}[mode]
        record['trigger'] = native_time()
        output.command(command); output.expect(command, allow_terminal=True)
        if mode.startswith('root-'):
            root.wait(timeout=1); record.update(rootStatus=root.returncode, rootExit=native_time())
        wait_exits(record['trigger'] + 8)
        record['windowEnd'] = native_time(); record['exits'] = copy.deepcopy(exits)
        record['observerAlive'] = observer.ping()
        if not mode.startswith('root-'):
            output.command('ping')
            record['rootAlive'] = output.expect('ping', allow_terminal=True).get('pid') == root.pid and root.poll() is None
    except (OSError, RuntimeError, ValueError, KeyError, TimeoutError, subprocess.TimeoutExpired) as error:
        record['observationError'] = repr(error)
    finally:
        candidate = dict(record, mode='broker-stop') if mode == 'release-control' else record
        record['verdict'] = classify(candidate)
        if mode == 'release-control' and record.get('ordinaryChannelSameProvider') is not True: record['verdict'] = 'UNKNOWN'
        try:
            if root and root.poll() is None:
                try: output.command('quit'); root.wait(timeout=1)
                except (OSError, subprocess.TimeoutExpired): root.kill(); root.wait(timeout=1)
            if identities: wait_exits(max(i['guardDeadline'] for i in identities.values()) + 1)
            record['cleanup'] = dict(rootStatus=root.returncode if root else None, exits=copy.deepcopy(exits),
                                     complete=len(pids) == len(exits) == 2 and root is not None and root.poll() is not None)
        except (OSError, RuntimeError, subprocess.TimeoutExpired) as error: record['cleanupError'] = repr(error)
        finally:
            observer.cleanup(); queue.close()
            if root: root.stdin.close(); root.stdout.close()
            if errors: errors.close()
            record['identities'] = identities; record['observer'] = observer.record
            (products / ('startup-' + mode + '.json')).write_text(json.dumps(record, indent=2) + '\n')
    return record


def run(products):
    manifest = json.loads((products / 'build.json').read_text())
    for root, key in ((products/'Sources','sourceHashes'), (PLATFORM,'runnerHashes'), (products,'binaries')):
        for relative, digest in manifest[key].items():
            if hashlib.sha256((root/relative).read_bytes()).hexdigest() != digest: raise RuntimeError('changed input: '+relative)
    reject_untrusted_peer(manifest, products)
    register_container(manifest, products)
    results = []
    for mode in ('release-control', 'broker-stop', 'broker-crash', 'root-quit', 'root-crash'):
        record = run_case(manifest, products, mode); results.append(record)
        (products/'startup-results.json').write_text(json.dumps(dict(cases=results, launcherAdmitted=False), indent=2)+'\n')
        print(json.dumps({k:record.get(k) for k in ('mode','verdict','phaseBefore','phaseAfter','observationError','cleanup')}), flush=True)
        if record['verdict'] != 'PASS' or not record.get('cleanup',{}).get('complete'): return 2
    return 0


if __name__ == '__main__':
    if sys.argv[1:] == ['--build-only']: print(build(), flush=True)
    elif len(sys.argv) == 3 and sys.argv[1] == '--run': raise SystemExit(run(Path(sys.argv[2]).resolve()))
    else: raise SystemExit('usage: run_startup.py --build-only | --run PRODUCTS')
