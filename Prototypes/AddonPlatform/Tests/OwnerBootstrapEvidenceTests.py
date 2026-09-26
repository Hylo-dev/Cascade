#
# OwnerBootstrapEvidenceTests.py
# Cascade
#
"""Offline finite-owner evidence tests replace native endpoints, never the observer."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch

TRACING = Path(__file__).resolve().parents[1] / 'Tracing'
sys.path.insert(0, str(TRACING))
import owner_run as owner


def manifest_at(products):
    prefix = 'hylo.Cascade.OwnerFixture.' + 'a' * 32
    manifest = dict(schema='owner-bootstrap-build-v1', prefix=prefix, runID='a' * 32,
                    userHome=str(products), team='TEAM', products={})
    for key in ['Supervisor', 'A.Stub', 'A.Worker', 'B.Stub', 'B.Worker']:
        identity = prefix + '.' + key
        name = 'Owner' + key.replace('.', '')
        (products / name).write_bytes(key.encode())
        manifest['products'][key] = dict(path=str(products / name), identity=identity,
            infoIdentifier=identity, hash=__import__('hashlib').sha256(key.encode()).hexdigest(),
            cdhash=('1' if key == 'Supervisor' else '2' if key.startswith('A') else '3') * 40,
            entitlements={} if key == 'Supervisor' else dict({'com.apple.security.app-sandbox': True},
                **({'com.apple.security.inherit': True} if key.endswith('Worker') else {})),
            flags=65536, runtime=1769472, team='TEAM', strictVerified=True)
    (products / 'manifest.json').write_text(json.dumps(manifest))
    return manifest


def specimen(manifest, who):
    home = manifest['userHome'] + '/Library/Containers/' + manifest['prefix'] + '.' + who + '.Stub/Data'
    return dict(kind='storageOwn', role='Worker', home=home,
                path=home + '/CascadeOwner-' + manifest['runID'] + '/specimen',
                size=64, device=1, inode=10 if who == 'A' else 20, contentEqual=True,
                regular=True, canonical=True, result=0, errno=0)


def native_records(manifest, phase, supervisor, child):
    who = 'B' if phase == 'O2' else 'A'
    traced = phase == 'O4'
    records = []
    def add(kind, role, **fields):
        records.append(dict(kind=kind, role=role, **fields))
    def snapshot(role, stage, guest=False):
        key = 'Supervisor' if role == 'Supervisor' and not guest else who + '.' + ('Worker' if guest else role)
        product = manifest['products'][key]
        add('snapshot', role, stage=stage, subjectRole='Worker' if guest else role,
            subjectPID=child if guest or role != 'Supervisor' else supervisor,
            source='guest' if guest else 'self', copyGuestStatus=0 if guest else -1,
            copySelfStatus=-1 if guest else 0, requirementStatus=0, informationStatus=0,
            fieldsAvailable=True, baselineMatched=True, api=0, validity=0,
            status=1644237585, flags=65536, runtime=1769472, identity=product['identity'],
            hash=product['cdhash'], team='TEAM', entitlements='none' if key == 'Supervisor' else
            'inherit' if key.endswith('Worker') else 'sandbox', valid=True, hard=True,
            kill=True, debugged=False, platform=False)
    def controls(role, inherited):
        add('controls', role, inherited=inherited, hardNproc=0, softNproc=0,
            fileDenied=True, fileErrno=1, socketDenied=True, socketResult=-1, socketErrno=1,
            setResult=0, setErrno=0, raiseDenied=True, raiseErrno=1)
    add('guard', 'Supervisor', seconds=3, lowerBound=103.0)
    snapshot('Supervisor', 'S0')
    add('spawn', 'Supervisor', result=0, childPID=child)
    add('guard', 'Stub', seconds=2, lowerBound=102.0)
    snapshot('Stub', 'S0')
    controls('Stub', False)
    snapshot('Stub', 'S1')
    snapshot('Supervisor', 'S1')
    if traced:
        add('ptrace', 'Stub', result=0, errno=0)
    snapshot('Stub', 'S2')
    snapshot('Supervisor', 'S2')
    add('execGrant', 'Supervisor', childPID=child)
    add('execIntent', 'Stub', targetRole='Worker')
    if traced:
        add('execStop', 'Supervisor', childPID=child, waitStatus=1407, signal=5, observed=True)
        snapshot('Supervisor', 'S3', guest=True)
        add('continueIntent', 'Supervisor', childPID=child)
        add('continue', 'Supervisor', childPID=child, result=0, errno=0)
    add('workerProgress', 'Worker', point='mainEntry', boundary='reached')
    snapshot('Worker', 'S4')
    add('guardInherited', 'Worker', lowerBound=102.0, remainingSeconds=1.5,
        armed=True, defaultSignal=True, unblocked=True)
    controls('Worker', True)
    records.append(dict(specimen(manifest, who), created=phase in ['O1', 'O2']))
    if phase != 'O1':
        other = specimen(manifest, 'A' if who == 'B' else 'B')
        add('storageCross', 'Worker', path=other['path'], readResult=-1, readErrno=1,
            writeResult=-1, writeErrno=13, denied=True)
    add('childExit', 'Supervisor', childPID=child, waitStatus=0, observed=True)
    for index, record in enumerate(records):
        record.update(clock='CLOCK_MONOTONIC', time=100 + index * .01, owner=who)
        if record['kind'] == 'continue':
            record['requestTime'] = record['time']
    return records


def observe(mutation=None, waitcode=0, scenario=None):
    """observe exercises the actual four-case dispatcher, parser, waits and reducers."""
    calls, active = [], {}
    endpoint_trace = dict(killRequests=0, waits=[], queueReads=0, clock=1000.0)
    original_open = owner.os.open
    with tempfile.TemporaryDirectory(prefix='cascade-owner-offline-') as directory, contextlib.ExitStack() as stack:
        products = Path(directory).resolve()
        (products / 'Library/Application Support').mkdir(parents=True)
        manifest = manifest_at(products)
        def spawn(arguments, **kwargs):
            index = len(calls)
            endpoint_trace['queueReads'] = 0
            calls.append(arguments)
            if index >= 4:
                raise AssertionError('fifth native dispatch')
            pid, child = 100 + index, 200 + index
            records = native_records(manifest, arguments[1], pid, child)
            if scenario == 'blocked':
                records = records[:next(i for i, event in enumerate(records) if event['kind'] == 'storageOwn')]
            elif scenario == 'missing-child-exit':
                records = [event for event in records if event['kind'] != 'childExit']
            sequences = {}
            for event in records:
                event_pid = pid if event['role'] == 'Supervisor' else child
                sequences[event_pid] = sequences.get(event_pid, 0) + 1
                event.update(pid=event_pid, sequence=sequences[event_pid], nonce=arguments[2], phase=arguments[1])
            if mutation:
                mutation(index, records)
            stream = tempfile.TemporaryFile()
            stream.write(b''.join(json.dumps(event).encode() + b'\n' for event in records))
            length = stream.tell()
            stream.seek(0)
            active.update(pid=pid, child=child, descriptor=stream.fileno(), stream=stream, length=length)
            def kill():
                endpoint_trace['killRequests'] += 1
            def wait(timeout):
                endpoint_trace['waits'].append(timeout)
                if scenario == 'supervisor-wait-timeout' or scenario == 'blocked':
                    raise subprocess.TimeoutExpired('owned offline Supervisor', timeout)
                return waitcode
            return SimpleNamespace(pid=pid, stdin=io.BytesIO(), stdout=stream, kill=kill, wait=wait)
        class Queue:
            def control(self, changes, maximum, timeout=None):
                if changes is not None:
                    return []
                endpoint_trace['queueReads'] += 1
                if endpoint_trace['queueReads'] > 12:
                    raise AssertionError('offline endpoint script exhausted')
                if scenario == 'blocked':
                    if active['stream'].tell() >= active['length']:
                        endpoint_trace['clock'] = 1004.1 if endpoint_trace['clock'] < 1004 else 1005.1
                        return []
                    endpoint_trace['clock'] += .01
                    return [SimpleNamespace(filter=owner.tracing.select.KQ_FILTER_READ, ident=active['descriptor'])]
                notifications = [SimpleNamespace(filter=owner.tracing.select.KQ_FILTER_PROC, ident=active['pid'])]
                if scenario != 'missing-child-exit':
                    notifications.append(SimpleNamespace(filter=owner.tracing.select.KQ_FILTER_PROC, ident=active['child']))
                notifications.append(SimpleNamespace(filter=owner.tracing.select.KQ_FILTER_READ, ident=active['descriptor']))
                return notifications
            def close(self):
                pass
        listener = MagicMock()
        listener.__enter__.return_value = listener
        listener.getsockname.return_value = ('127.0.0.1', 12345)
        listener.accept.return_value = (MagicMock(), ('127.0.0.1', 12345))
        if scenario == 'positive-accept':
            listener.accept.side_effect = OSError('scripted positive accept failure')
        def open_control(path, flags, *args, **kwargs):
            if scenario == 'positive-file' and str(path).endswith('/control') and not flags & owner.os.O_CREAT:
                raise PermissionError('scripted positive file failure')
            return original_open(path, flags, *args, **kwargs)
        if scenario is not None:
            stack.enter_context(patch.object(owner.os, 'open', side_effect=open_control))
            stack.enter_context(patch.object(owner.tracing.time, 'monotonic', side_effect=lambda: endpoint_trace['clock']))

        stack.enter_context(patch.object(owner.tracing.subprocess, 'Popen', side_effect=spawn))
        stack.enter_context(patch.object(owner.tracing.select, 'kqueue', side_effect=Queue))
        stack.enter_context(patch.object(owner.tracing.socket, 'socket', return_value=listener))
        stack.enter_context(patch.object(owner.tracing.socket, 'create_connection',
            side_effect=ConnectionRefusedError('scripted positive connect failure') if scenario == 'positive-connect' else None,
            return_value=contextlib.nullcontext()))
        stack.enter_context(patch.object(Path, 'home', return_value=products))
        stack.enter_context(patch.object(sys, 'argv', ['owner_run.py', str(products)]))
        stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        result = owner.main()
        report = json.loads((products / 'owner-report.json').read_text())
        report['_offlineEndpoints'] = dict(endpoint_trace, rawLogs={case['phase']: Path(case['rawLog']).read_text()
            for case in report['cases']})
        return report, calls, result


def driver_arguments(option):
    """driver_arguments executes only the actual command line with a local shell stand-in."""
    script = (TRACING.parents[2] / 'scripts/test-addon-owner-bootstrap.sh').read_text()
    command = next(line.strip() for line in script.splitlines() if line.strip().startswith('codesign ') and option in line)
    shell = '\n'.join([
        'codesign() { printf "%s\\0" "$@"; }',
        'products=$1; key=$2; executable=$3; identifier=$4; identity=$5', command])
    product_dir = '/private/tmp/offline owner products'
    key = 'A.Stub'
    executable = product_dir + '/OwnerAStub'
    identifier = 'hylo.Cascade.OwnerFixture.' + 'a' * 32 + '.A.Stub'
    identity = '4A857D842A5406C2D3071776FDE7B27B3098FE63'
    completed = subprocess.run(['zsh', '-f', '-c', shell, 'owner-offline-arguments', product_dir,
        key, executable, identifier, identity], capture_output=True, check=True)
    return completed.stdout.decode().rstrip('\0').split('\0'), product_dir, key, executable, identifier, identity


class OwnerBootstrapEvidenceTests(unittest.TestCase):
    def assertStops(self, change, case_index=0):
        def mutate(index, records):
            if index == case_index:
                change(records)
        report, calls, code = observe(mutate)
        self.assertEqual(len(calls), case_index + 1)
        self.assertEqual(code, 1)
        self.assertFalse(report['complete'])
        return report

    def test_driver_passes_literal_requirement_to_strict_verification(self):
        arguments, _, _, executable, identifier, identity = driver_arguments('--verify')
        self.assertEqual(arguments, ['--verify', '--strict', '--all-architectures', '-R',
            '=anchor apple generic and identifier "' + identifier + '" and certificate leaf = H"' + identity + '"', executable])

    def test_driver_binds_certificate_prefix_to_optional_argument(self):
        arguments, products, key, executable, _, _ = driver_arguments('--extract-certificates')
        self.assertEqual(arguments, ['-d', '--extract-certificates=' + products + '/' + key + '-certificate-', executable])

    def test_independent_failed_validity_survives_information_and_cleanup_failure(self):
        for guest in [False, True]:
            target = 3 if guest else 0
            def mutate(index, records):
                if index == target:
                    next(event for event in records if event.get('stage') == ('S3' if guest else 'S4')).update(
                        api=-1, informationStatus=-1, fieldsAvailable=False, validity=-67050)
            report, calls, code = observe(mutate, scenario='missing-child-exit' if not guest else None)
            self.assertEqual((len(calls), code), (target + 1, 1))
            case = report['cases'][-1]
            self.assertTrue(case['assessment']['regressions'])
            self.assertEqual(case['assessment']['result'], 'weakened')
            self.assertTrue(case['assessment']['unavailableEvidence'])
            if not guest:
                self.assertFalse(case['cleanupObserved'])
                self.assertEqual(case['childTermination']['kind'], 'unknown')

    def test_unhashable_snapshot_source_retains_case_exits_and_raw_evidence(self):
        for stage, target in [('S4', 0), ('S3', 3)]:
            for malformed_source in [[], {}]:
                with self.subTest(stage=stage, source=malformed_source):
                    def mutate(index, records):
                        if index == target:
                            next(event for event in records if event.get('stage') == stage)['source'] = malformed_source
                    report, calls, code = observe(mutate)
                    self.assertEqual((len(calls), code), (target + 1, 1))
                    self.assertEqual(len(report['cases']), target + 1)
                    self.assertEqual(report['stoppedAt'], 'O1' if target == 0 else 'O4')
                    self.assertFalse(report['complete'])
                    self.assertNotIn('error', report)
                    case = report['cases'][-1]
                    self.assertFalse(case['assessment']['accepted'])
                    self.assertTrue(case['assessment']['unavailableEvidence'])
                    self.assertEqual(case['assessment']['regressions'], [])
                    self.assertTrue(case['cleanupObserved'])
                    self.assertTrue(case['supervisorWaitObserved'])
                    self.assertTrue(case['childWaitObserved'])
                    self.assertTrue(case['childKqueueExitObserved'])
                    self.assertFalse(case['guardrailUsed'])
                    self.assertEqual(case['supervisorTermination'], dict(kind='exited', exitCode=0, rawReturncode=0))
                    self.assertEqual(case['childTermination'], dict(kind='exited', exitCode=0, rawWaitStatus=0))
                    self.assertEqual(len(report['terminations']), target + 1)
                    self.assertTrue(report['terminations'][-1]['normalCompletionObserved'])
                    raw_events = [json.loads(line) for line in report['_offlineEndpoints']['rawLogs'][case['phase']].splitlines()]
                    self.assertEqual(raw_events, case['events'])
                    self.assertEqual(next(event for event in raw_events if event.get('stage') == stage)['source'], malformed_source)

    def test_independent_validity_regression_keeps_observed_refusal(self):
        def mutate(index, records):
            if index == 3:
                next(event for event in records if event.get('kind') == 'ptrace').update(result=-1, errno=1)
                next(event for event in records if event.get('stage') == 'S3').update(
                    api=-1, informationStatus=-1, fieldsAvailable=False, validity=-67050)
        report, calls, code = observe(mutate)
        self.assertEqual((len(calls), code), (4, 1))
        assessment = report['cases'][-1]['assessment']
        self.assertEqual(assessment['refusals'], [dict(kind='ptrace', errno=1)])
        self.assertEqual(assessment['regressions'], [dict(kind='publicProtection', stage='S3', field='validity', value=-67050)])
        self.assertEqual(assessment['result'], 'weakened')
        self.assertFalse(assessment['accepted'])

    def test_missing_mistyped_or_unobserved_validity_is_unknown_not_regression(self):
        for validity in [None, True, 'invalid', -67050]:
            def mutate(index, records):
                if index == 0:
                    event = next(event for event in records if event.get('stage') == 'S4')
                    if validity is None:
                        del event['validity']
                    else:
                        event['validity'] = validity
                    if validity == -67050:
                        event.update(copySelfStatus=-1, requirementStatus=-1, api=-1, informationStatus=-1)
            report, calls, code = observe(mutate)
            self.assertEqual((len(calls), code), (1, 1))
            self.assertEqual(report['cases'][0]['assessment']['regressions'], [])
            self.assertTrue(report['cases'][0]['assessment']['unavailableEvidence'])

    def test_observer_blocked_stream_reaches_guard_and_keeps_exit_unknown(self):
        report, calls, code = observe(scenario='blocked')
        self.assertEqual((len(calls), code, report['stoppedAt']), (1, 1, 'O1'))
        case = report['cases'][0]
        self.assertTrue(case['guardrailUsed'])
        self.assertFalse(case['guardTerminationObserved'])
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(case['supervisorWaitObserved'])
        self.assertFalse(case['childWaitObserved'])
        self.assertFalse(case['childKqueueExitObserved'])
        self.assertEqual(case['supervisorTermination']['kind'], 'unknown')
        self.assertEqual(case['childTermination']['kind'], 'unknown')
        self.assertGreaterEqual(report['_offlineEndpoints']['killRequests'], 1)
        self.assertEqual(len(report['_offlineEndpoints']['waits']), 1)
        self.assertLessEqual(report['_offlineEndpoints']['queueReads'], 12)
        self.assertAlmostEqual(case['elapsedSeconds'], 5.1)
        self.assertTrue(any('exit observation failed' in error for error in case['errors']))
        self.assertEqual([json.loads(line) for line in report['_offlineEndpoints']['rawLogs']['O1'].splitlines()], case['events'])
        self.assertTrue(case['events'])
        self.assertFalse(any(event['kind'] in ['storageOwn', 'childExit'] for event in case['events']))

    def test_missing_native_wait_and_child_notice_keeps_cleanup_unknown(self):
        report, calls, code = observe(scenario='missing-child-exit')
        self.assertEqual((len(calls), code), (1, 1))
        case = report['cases'][0]
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(case['guardrailUsed'])
        self.assertTrue(case['supervisorWaitObserved'])
        self.assertFalse(case['childWaitObserved'])
        self.assertFalse(case['childKqueueExitObserved'])
        self.assertEqual(case['supervisorTermination']['kind'], 'exited')
        self.assertEqual(case['childTermination']['kind'], 'unknown')
        self.assertEqual(report['_offlineEndpoints']['killRequests'], 0)
        self.assertTrue(report['_offlineEndpoints']['rawLogs']['O1'])

    def test_supervisor_wait_timeout_does_not_erase_known_child_exit(self):
        report, calls, code = observe(scenario='supervisor-wait-timeout')
        self.assertEqual((len(calls), code), (1, 1))
        case = report['cases'][0]
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(case['guardrailUsed'])
        self.assertFalse(case['supervisorWaitObserved'])
        self.assertTrue(case['childWaitObserved'])
        self.assertTrue(case['childKqueueExitObserved'])
        self.assertEqual(case['supervisorTermination']['kind'], 'unknown')
        self.assertEqual(case['childTermination'], dict(kind='exited', rawWaitStatus=0, exitCode=0))
        self.assertEqual(len(report['_offlineEndpoints']['waits']), 1)
        self.assertEqual(report['_offlineEndpoints']['killRequests'], 0)
        self.assertTrue(report['_offlineEndpoints']['rawLogs']['O1'])

    def test_positive_file_connect_and_accept_failures_prevent_launch(self):
        for scenario in ['positive-file', 'positive-connect', 'positive-accept']:
            report, calls, code = observe(scenario=scenario)
            self.assertEqual((len(calls), code, len(report['cases'])), (0, 1, 1))
            case = report['cases'][0]
            self.assertFalse(case['positiveControls'])
            self.assertFalse(case['processCreated'])
            self.assertFalse(case['cleanupObserved'])
            self.assertFalse(case['guardrailUsed'])
            self.assertEqual(case['supervisorTermination']['kind'], 'unknown')
            self.assertEqual(case['childTermination']['kind'], 'unknown')
            self.assertEqual(report['_offlineEndpoints']['rawLogs']['O1'], '')
            self.assertEqual(report['_offlineEndpoints']['killRequests'], 0)
            self.assertEqual(report['_offlineEndpoints']['waits'], [])
            self.assertTrue(case['errors'])

    def test_complete_four_cases_and_frozen_identity_selection(self):
        report, calls, code = observe()
        self.assertEqual([call[1] for call in calls], ['O1', 'O2', 'O3', 'O4'])
        self.assertEqual(code, 0)
        self.assertTrue(report['complete'])
        self.assertTrue(report['sameOwnerContinuityObserved'])
        self.assertTrue(report['crossOwnerDenialObserved'])
        self.assertTrue(report['tracedCompatibilityObserved'])
        self.assertFalse(report['nativeLauncherAdmitted'])
        self.assertFalse(report['productionTemplateVerifierQualified'])
        self.assertEqual(len(set(call[0] for call in calls)), 1)
        self.assertEqual(calls[2][3], calls[3][3])
        self.assertEqual(calls[2][6:], calls[3][6:])
        self.assertEqual(len({case['rawLog'] for case in report['cases']}), 4)

    def test_wrong_owner_nonce_sequence_pid_and_clock(self):
        for change in [dict(owner='B'), dict(nonce='b' * 32), dict(sequence=0), dict(pid=999),
                       dict(time=float('nan')), dict(clock='other')]:
            with self.subTest(change=change):
                self.assertStops(lambda records: next(e for e in records if e['kind'] == 'storageOwn').update(change))

    def test_worker_profile_and_same_signer_wrong_identity(self):
        for change in [dict(entitlements='sandbox'), dict(identity='wrong.B.Worker'), dict(hash='f' * 40),
                       dict(subjectPID=999), dict(source='guest'), dict(baselineMatched=False),
                       dict(fieldsAvailable=False), dict(copySelfStatus=False), dict(valid=False), dict(hard=False)]:
            with self.subTest(change=change):
                self.assertStops(lambda records: next(e for e in records if e.get('stage') == 'S4').update(change))

    def test_missing_main_snapshot_storage(self):
        for kind in ['workerProgress', 'storageOwn']:
            self.assertStops(lambda records: records.__setitem__(slice(None), [e for e in records if e['kind'] != kind]))
        self.assertStops(lambda records: records.__setitem__(slice(None), [e for e in records if e.get('stage') != 'S4']))

    def test_cross_denial_requires_positive_path_and_exact_errno(self):
        for change in [dict(path='/missing'), dict(readErrno=2), dict(writeErrno=2),
                       dict(readResult=0), dict(writeResult=0), dict(denied=False)]:
            with self.subTest(change=change):
                self.assertStops(lambda records: next(e for e in records if e['kind'] == 'storageCross').update(change), 1)

    def test_own_storage_content_inode_and_home(self):
        for change in [dict(contentEqual=False), dict(size=63), dict(canonical=False),
                       dict(inode=999), dict(home='/tmp'), dict(created=True)]:
            self.assertStops(lambda records: next(e for e in records if e['kind'] == 'storageOwn').update(change), 2)

    def test_wrong_s3_subject_and_profile(self):
        for change in [dict(subjectPID=999), dict(subjectRole='Stub'), dict(source='self'),
                       dict(entitlements='sandbox'), dict(identity='same-signer.B.Worker'), dict(hash='e' * 40)]:
            self.assertStops(lambda records: next(e for e in records if e.get('stage') == 'S3').update(change), 3)

    def test_premature_duplicate_grants_and_continues(self):
        for kind, case_index in [('execGrant', 0), ('continue', 3), ('continueIntent', 3)]:
            self.assertStops(lambda records: records.append(copy.deepcopy(next(e for e in records if e['kind'] == kind))), case_index)
        self.assertStops(lambda records: next(e for e in records if e['kind'] == 'execGrant').update(time=99.0))
        self.assertStops(lambda records: next(e for e in records if e['kind'] == 'continue').update(requestTime=99.0), 3)

    def test_continue_return_may_follow_worker_record(self):
        def mutate(index, records):
            if index == 3:
                continued = next(e for e in records if e['kind'] == 'continue')
                continued['time'] = next(e for e in records if e['kind'] == 'storageOwn')['time'] + .001
        report, _, code = observe(mutate)
        self.assertEqual(code, 0)
        self.assertTrue(report['complete'])

    def test_guard_signaled_failed_and_unknown_exits(self):
        for status in [256, int(signal.SIGALRM), int(signal.SIGTRAP), 0x7f]:
            self.assertStops(lambda records: next(e for e in records if e['kind'] == 'childExit').update(waitStatus=status))
        self.assertStops(lambda records: records.__setitem__(slice(None), [e for e in records if e['kind'] != 'childExit']))
        report, calls, code = observe(waitcode=25)
        self.assertEqual((len(calls), code, report['complete']), (1, 1, False))

    def test_prompt_timeout_controls_and_inherited_guard(self):
        for kind, change in [('controls', dict(fileDenied=False)), ('guardInherited', dict(armed=False)),
                             ('guardInherited', dict(lowerBound=103.0)), ('storageOwn', dict(promptObserved=True)),
                             ('storageOwn', dict(result=-1, errno=60))]:
            self.assertStops(lambda records: next(e for e in records if e['kind'] == kind and e['role'] == 'Worker').update(change))

    def test_untraced_has_no_stop_or_continue(self):
        self.assertStops(lambda records: next(e for e in records if e['kind'] == 'workerProgress').update(kind='continue', result=0, errno=0))

    def test_static_exact_profile_rejects_extra_false_missing_or_mistyped(self):
        with tempfile.TemporaryDirectory() as directory:
            products = Path(directory).resolve()
            baseline = manifest_at(products)
            for entitlements in [{'com.apple.security.app-sandbox': True},
                    {'com.apple.security.app-sandbox': True, 'com.apple.security.inherit': 1},
                    {'com.apple.security.app-sandbox': True, 'com.apple.security.inherit': True, 'extra': False}]:
                changed = copy.deepcopy(baseline)
                changed['products']['A.Worker']['entitlements'] = entitlements
                self.assertFalse(owner.manifest_valid(changed, products))

    def test_fifth_case_is_never_accepted_and_bytes_are_pinned(self):
        report, _, _ = observe()
        last = report['cases'][-1]
        assessment = owner.assess_case(last, report['cases'], report['build'], last['matchedArtifacts'])
        self.assertFalse(assessment['accepted'])
        with tempfile.TemporaryDirectory() as directory:
            products = Path(directory).resolve()
            manifest = manifest_at(products)
            self.assertTrue(owner.manifest_valid(manifest, products))
            Path(manifest['products']['A.Worker']['path']).write_bytes(b'changed same-owner bytes')
            self.assertFalse(owner.manifest_valid(manifest, products))

    def test_collision_control_is_never_removed_without_owned_creation(self):
        # Inject an EXCL failure after directory creation and record every unlink.
        original_open = owner.os.open
        removed = []
        def fail_control(path, flags, *args, **kwargs):
            if str(path).endswith('/control') and flags & owner.os.O_EXCL:
                raise FileExistsError('injected control collision')
            return original_open(path, flags, *args, **kwargs)
        original_unlink = Path.unlink
        def track_unlink(path, *args, **kwargs):
            removed.append(str(path))
            return original_unlink(path, *args, **kwargs)
        with patch.object(owner.os, 'open', side_effect=fail_control), patch.object(Path, 'unlink', track_unlink):
            report, calls, code = observe()
        self.assertEqual(calls, [])
        self.assertEqual(code, 1)
        self.assertFalse(any(path.endswith('/control') for path in removed))

    def test_old_reducer_still_rejects_inherited_worker(self):
        from TracingUntracedEvidenceTests import untraced_evidence, tracing
        cases = untraced_evidence()
        for event in cases[-1]['events']:
            if event.get('stage') == 'S4':
                event['entitlements'] = 'inherit'
        self.assertFalse(tracing.reduce_evidence(cases)['untracedExecCompatibilityObserved'])


if __name__ == '__main__':
    unittest.main()
