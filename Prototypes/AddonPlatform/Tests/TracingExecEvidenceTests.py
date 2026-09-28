#
# TracingExecEvidenceTests.py
# Cascade
#
import copy
import contextlib
import io
import json
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch, MagicMock
import signal
import unittest
from TracingEvidenceTests import evidence, tracing


def exec_evidence():
    """exec_evidence describes one owned process replacing Stub with matched Worker."""
    cases = evidence()
    case = copy.deepcopy(cases[-1])
    case.update(phase='C', supervisorPID=100, childPID=203)
    for event in case['events']:
        if event['kind'] == 'childExit':
            event['childPID'] = 203
    next(e for e in case['events'] if e['kind'] == 'ptrace')['role'] = 'Stub'
    worker = copy.deepcopy(cases[1]['events'][3])
    external = dict(worker, role='Supervisor', subjectRole='Worker', subjectPID=203,
                    stage='S3', source='guest', copyGuestStatus=0, requirementStatus=0,
                    informationStatus=0, fieldsAvailable=True, baselineMatched=True)
    worker.update(stage='S4')
    case['events'] += [dict(kind='execGrant', role='Supervisor', childPID=203),
                       dict(kind='execIntent', role='Stub'),
                       dict(kind='execStop', role='Supervisor', childPID=203,
                            observed=True, waitStatus=(signal.SIGTRAP << 8) | 0x7f, signal=int(signal.SIGTRAP)),
                       external,
                       dict(kind='continueIntent', role='Supervisor', childPID=203),
                       dict(kind='continue', role='Supervisor', childPID=203, result=0, errno=0),
                       worker,
                       dict(kind='guardInherited', role='Worker', lowerBound=102.0,
                            remainingSeconds=1.3, armed=True, defaultSignal=True, unblocked=True),
                       dict(kind='controls', role='Worker', inherited=True, fileDenied=True,
                            socketDenied=True, hardNproc=0, softNproc=0, raiseDenied=True)]
    case['events'].insert(0, dict(kind='guard', role='Stub', lowerBound=102.0, seconds=2))
    # Independent CLOCK_MONOTONIC readings; Python observer may have any epoch.
    case['elapsedSeconds'] = 0.1
    for index, event in enumerate(case['events']):
        event.update(clock='CLOCK_MONOTONIC', time=100.0 + index * 0.01)
        if event['kind'] == 'continue':
            event['requestTime'] = event['time']
    cases.append(case)
    return cases


def progress_evidence():
    """progress_evidence interleaves ancillary milestones before the real S4 snapshot."""
    cases = exec_evidence()
    events = cases[-1]['events']
    start = next(i for i, e in enumerate(events) if e.get('stage') == 'S4')
    markers = [dict(kind='workerProgress', role='Worker', point='mainEntry', boundary='reached')]
    for point in ['CFStringCreateWithFormat', 'SecCodeCopySelf', 'SecRequirementCreateWithString',
                  'SecCodeCheckValidity', 'SecCodeCopySigningInformation', 'extractSigningFields']:
        markers += [dict(kind='workerProgress', role='Worker', point=point, boundary='before'),
                    dict(kind='workerProgress', role='Worker', point=point, boundary='after')]
        if point.startswith('Sec'):
            markers[-1]['apiStatus'] = 0
    events[start:start] = markers
    for index, event in enumerate(events):
        event.update(clock='CLOCK_MONOTONIC', time=100.0 + index * 0.01)
        if event['kind'] == 'continue':
            event['requestTime'] = event['time']
    return cases


def observe_progress(cases, mutation=None):
    """observe_progress exercises real record parsing with only native OS endpoints substituted."""
    nonce, supervisor_pid, child_pid = '1' * 32, 100, 203
    records = [dict(kind='spawn', role='Supervisor', result=0, childPID=child_pid)]
    records += copy.deepcopy(cases[-1]['events'])
    sequences = {}
    for event in records:
        event.setdefault('role', 'Supervisor')
        pid = supervisor_pid if event['role'] == 'Supervisor' else child_pid
        sequences[pid] = sequences.get(pid, 0) + 1
        event.update(pid=pid, sequence=sequences[pid], nonce=nonce, phase='C')
    if mutation:
        mutation(records)
    with tempfile.TemporaryDirectory(prefix='cascade-tracing-localization-offline-') as directory, \
         tempfile.TemporaryFile() as stream:
        products = Path(directory)
        foreign_file = products / 'foreign-existing-file'
        foreign_file.touch()
        stream.write(b''.join(json.dumps(e).encode() + b'\n' for e in records))
        stream.seek(0)
        descriptor = stream.fileno()
        process = SimpleNamespace(pid=supervisor_pid, stdin=io.BytesIO(), stdout=stream,
                                  kill=lambda: None, wait=lambda timeout: 0)
        class Queue:
            def control(self, changes, maximum, timeout=None):
                return [] if changes is not None else [
                    SimpleNamespace(filter=tracing.select.KQ_FILTER_PROC, ident=supervisor_pid),
                    SimpleNamespace(filter=tracing.select.KQ_FILTER_READ, ident=descriptor)]
            def close(self):
                pass
        listener = MagicMock()
        listener.getsockname.return_value = ('127.0.0.1', 12345)
        listener.accept.return_value = (MagicMock(), ('127.0.0.1', 12345))
        with patch.object(tracing.subprocess, 'Popen', return_value=process), \
             patch.object(tracing.select, 'kqueue', side_effect=lambda: Queue()), \
             patch.object(tracing.socket, 'create_connection', return_value=contextlib.nullcontext()), \
             patch.object(tracing.uuid, 'uuid4', return_value=SimpleNamespace(hex=nonce)):
            return tracing.run_case(products, 'C', 'Stub', listener, foreign_file, 'a' * 64, cases[:3])


class TracingExecEvidenceTests(unittest.TestCase):
    # Deleting any stop, identity, ordering, inherited-control or exit gate must
    # turn an accepted C record into incomplete/refused/regressed evidence.
    def assess(self, cases):
        return tracing.reduce_evidence(cases)

    def event(self, cases, kind=None, stage=None):
        return next(e for e in cases[-1]['events'] if
                    (kind is None or e.get('kind') == kind) and
                    (stage is None or e.get('stage') == stage))

    def test_interleaved_progress_survives_real_protocol_and_original_c_gates(self):
        cases = progress_evidence()
        cases[-1] = observe_progress(cases)
        self.assertTrue(cases[-1]['recordProtocolValid'])
        result = self.assess(cases)
        self.assertTrue(result['tracedExecCompatibilityObserved'])
        self.assertFalse(result['nativeLauncherAdmitted'])

    def test_progress_without_s4_never_substitutes_for_security_evidence(self):
        cases = progress_evidence()
        cases[-1]['events'] = [e for e in cases[-1]['events'] if e.get('stage') != 'S4']
        cases[-1] = observe_progress(cases)
        self.assertTrue(cases[-1]['recordProtocolValid'])
        result = self.assess(cases)
        self.assertFalse(result['tracedExecCompatibilityObserved'])
        self.assertFalse(result['nativeLauncherAdmitted'])

    def test_progress_does_not_bypass_existing_role_sequence_or_c_clock_gates(self):
        for changes in [dict(role='Foreign'), dict(sequence=0)]:
            with self.subTest(changes=changes):
                cases = progress_evidence()
                def mutate(records):
                    next(e for e in records if e['kind'] == 'workerProgress').update(changes)
                cases[-1] = observe_progress(cases, mutate)
                self.assertFalse(cases[-1]['recordProtocolValid'])
                self.assertFalse(self.assess(cases)['tracedExecCompatibilityObserved'])
        cases = progress_evidence()
        self.event(cases, stage='S4')['clock'] = 'python.monotonic'
        cases[-1] = observe_progress(cases)
        self.assertFalse(self.assess(cases)['tracedExecCompatibilityObserved'])

    def test_progress_clock_and_timestamp_must_be_explicit_native_readings(self):
        changes = [dict(clock='python.monotonic'), dict(clock=None), dict(clock='missing')]
        changes += [dict(time=value) for value in [None, True, '100.0', 0, -1, float('nan'), float('inf')]]
        for change in changes:
            with self.subTest(change=change):
                cases = progress_evidence()
                def mutate(records):
                    marker = next(e for e in records if e['kind'] == 'workerProgress')
                    marker.update(change)
                    if change == dict(clock='missing'):
                        del marker['clock']
                cases[-1] = observe_progress(cases, mutate)
                self.assertFalse(cases[-1]['recordProtocolValid'])
                self.assertFalse(self.assess(cases)['tracedExecCompatibilityObserved'])

    def test_complete_exec_has_separate_bounded_conclusion(self):
        result = self.assess(exec_evidence())
        self.assertEqual(result['result'], 'tracedExecCompatibilityObserved')
        self.assertTrue(result.get('basicCompatibilityObserved'))
        self.assertTrue(result.get('tracedExecCompatibilityObserved'))
        self.assertTrue(result['workerExecPerformed'])
        self.assertFalse(result['nativeLauncherAdmitted'])
        self.assertEqual(result['allVMProtectionsPreserved'], 'unknown')

    def test_missing_stop_or_wrong_signal_and_owner_cannot_pass(self):
        for changes in [None, dict(observed=False), dict(signal=signal.SIGSTOP),
                        dict(waitStatus=0), dict(childPID=999)]:
            cases = exec_evidence()
            stop = self.event(cases, 'execStop')
            if changes is None:
                cases[-1]['events'].remove(stop)
            else:
                stop.update(changes)
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')

    def test_stale_or_wrong_worker_identity_cannot_pass(self):
        for changes in [dict(subjectRole='Stub'), dict(identity='Stub'), dict(hash='wrong'),
                        dict(team='wrong'), dict(source='self'), dict(subjectPID=999),
                        dict(baselineMatched=False)]:
            cases = exec_evidence()
            self.event(cases, stage='S3').update(changes)
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')

    def test_missing_or_failed_external_api_is_unknown_not_authentication(self):
        for field in ['api', 'copyGuestStatus', 'requirementStatus', 'informationStatus', 'validity']:
            for value in [None, -1]:
                cases = exec_evidence()
                event = self.event(cases, stage='S3')
                if value is None:
                    del event[field]
                else:
                    event[field] = value
                result = self.assess(cases)
                self.assertNotEqual(result['result'], 'tracedExecCompatibilityObserved')
                self.assertFalse(result.get('tracedExecCompatibilityObserved', False))

    def test_premature_continuation_or_worker_and_failed_continue_cannot_pass(self):
        for stage in ['continue', 'S4']:
            cases = exec_evidence()
            event = self.event(cases, kind='continue') if stage == 'continue' else self.event(cases, stage='S4')
            event['time'] = self.event(cases, stage='S3')['time'] - 0.1
            if stage == 'continue':
                event['requestTime'] = event['time']
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')
        cases = exec_evidence()
        self.event(cases, 'continue').update(result=-1, errno=1)
        self.assertEqual(self.assess(cases)['result'], 'rejected')

    def test_worker_can_report_before_continue_result_is_written(self):
        cases = exec_evidence()
        self.event(cases, 'continue')['time'] = self.event(cases, stage='S4')['time'] + 0.005
        self.assertEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')

    def test_pre_call_intent_is_required_and_never_substitutes_for_return(self):
        for kind in ['continueIntent', 'continue']:
            cases = exec_evidence()
            cases[-1]['events'].remove(self.event(cases, kind))
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')

    def test_dispatch_stops_on_b_failure_and_success_runs_c_once(self):
        for refusal in [True, False]:
            cases = exec_evidence()
            if refusal:
                next(e for e in cases[2]['events'] if e['kind'] == 'ptrace').update(result=-1, errno=1)
            dispatched = []
            def run_boundary(products, phase, role, listener, foreign_file, artifact_hash, baselines=None):
                dispatched.append((phase, role))
                return copy.deepcopy(cases[len(dispatched) - 1])
            with tempfile.TemporaryDirectory(prefix='cascade-tracing-exec-offline-') as directory:
                products = Path(directory)
                for role in ['Supervisor', 'Stub', 'Worker']:
                    (products / ('Trace' + role)).write_bytes(b'offline fixture placeholder')
                with patch.object(tracing, 'run_case', side_effect=run_boundary), \
                     patch.object(tracing.socket, 'socket', return_value=MagicMock()), \
                     patch.object(tracing.sys, 'argv', ['run.py', str(products)]), \
                     contextlib.redirect_stdout(io.StringIO()):
                    code = tracing.main()
                report = json.loads((products / 'report.json').read_text())
            expected = [('A', 'Stub'), ('A', 'Worker'), ('B', 'Stub')]
            self.assertEqual(dispatched, expected if refusal else expected + [('C', 'Stub')])
            self.assertEqual(code, 1 if refusal else 0)
            self.assertEqual(report['result'], 'rejected' if refusal else 'tracedExecCompatibilityObserved')

    def test_partial_exec_requires_owned_stop_and_valid_protocol(self):
        for target, changes in [
            ('snapshot', dict(subjectPID=999)),
            ('snapshot', dict(subjectPID=203.0)),
            ('snapshot', dict(subjectRole='Stub')),
            ('stop', None),
            ('stop', dict(childPID=999)),
            ('stop', dict(childPID=203.0)),
            ('stop', dict(observed=False)),
            ('stop', dict(waitStatus=0)),
            ('stop', dict(signal=signal.SIGSTOP)),
            ('case', dict(recordProtocolValid=False)),
            ('case', dict(recordProtocolValid=None)),
            ('case', dict(recordProtocolValid=1)),
            ('case', dict(matchedArtifacts='b' * 64)),
        ]:
            with self.subTest(target=target, changes=changes):
                cases = exec_evidence()
                event = (self.event(cases, stage='S3') if target == 'snapshot' else
                         self.event(cases, 'execStop') if target == 'stop' else cases[-1])
                if changes is None:
                    cases[-1]['events'].remove(event)
                else:
                    event.update(changes)
                self.assertFalse(self.assess(cases)['workerExecPerformed'])

    def test_partial_exec_requires_fresh_matching_worker_and_strict_api_success(self):
        changes = [dict(hash='wrong'), dict(team='wrong'), dict(identity='Stub'),
                   dict(source='self'), dict(fieldsAvailable=False), dict(baselineMatched=False)]
        for field in ['api', 'validity', 'copyGuestStatus', 'requirementStatus', 'informationStatus']:
            changes += [{field: value} for value in [None, False, 0.0, -1]]
        for change in changes:
            with self.subTest(change=change):
                cases = exec_evidence()
                self.event(cases, stage='S3').update(change)
                self.assertFalse(self.assess(cases)['workerExecPerformed'])

    def test_partial_exec_requires_s3_after_stop_in_native_clock_domain(self):
        for changes in [dict(time=99.0), dict(time=None), dict(time=float('nan')),
                        dict(clock='python.monotonic')]:
            with self.subTest(changes=changes):
                cases = exec_evidence()
                self.event(cases, stage='S3').update(changes)
                self.assertFalse(self.assess(cases)['workerExecPerformed'])

    def test_owned_partial_exec_survives_missing_continue_s4_and_cleanup(self):
        cases = exec_evidence()
        cases[-1]['events'] = [e for e in cases[-1]['events'] if e.get('kind') not in
                              ['continueIntent', 'continue', 'childExit'] and e.get('role') != 'Worker']
        cases[-1].update(cleanupObserved=False, childWaitObserved=False,
                         supervisorWaitObserved=False, guardrailUsed=True)
        result = self.assess(cases)
        self.assertTrue(result['workerExecPerformed'])
        self.assertFalse(result['tracedExecCompatibilityObserved'])
        self.assertFalse(result['nativeLauncherAdmitted'])
        self.assertEqual(result['result'], 'unknown')

    def test_post_exec_weakening_and_inherited_limit_loss_cannot_pass(self):
        for changes in [dict(debugged=True), dict(hard=False), dict(kill=False), dict(flags=0),
                        dict(entitlements='none'), dict(status=1)]:
            cases = exec_evidence()
            self.event(cases, stage='S4').update(changes)
            self.assertEqual(self.assess(cases)['result'], 'weakened')
        for changes in [dict(inherited=False), dict(hardNproc=1), dict(softNproc=1),
                        dict(raiseDenied=False), dict(fileDenied=False), dict(socketDenied=False)]:
            cases = exec_evidence()
            next(e for e in cases[-1]['events'] if e['kind'] == 'controls' and e['role'] == 'Worker').update(changes)
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')

    def test_positive_c_requires_explicit_false_guardrail_flag(self):
        values = [('absent', None), ('null', None), ('integer zero', 0), ('float zero', 0.0),
                  ('empty string', ''), ('empty list', []), ('empty dictionary', {}),
                  ('integer one', 1), ('string false', 'false'), ('true', True)]
        for label, value in values:
            with self.subTest(value=label):
                cases = exec_evidence()
                if label == 'absent':
                    del cases[-1]['guardrailUsed']
                else:
                    cases[-1]['guardrailUsed'] = value
                result = self.assess(cases)
                self.assertFalse(result['tracedExecCompatibilityObserved'])
                self.assertNotEqual(result['result'], 'tracedExecCompatibilityObserved')
                # Guard evidence is needed for compatibility, not the earlier owned replacement fact.
                self.assertTrue(result['workerExecPerformed'])

    def test_guard_cleanup_and_clock_domain_are_required(self):
        for changes in [dict(armed=False), dict(defaultSignal=False), dict(unblocked=False),
                        dict(lowerBound=103.0), dict(remainingSeconds=0), dict(clock='python.monotonic')]:
            cases = exec_evidence()
            self.event(cases, 'guardInherited').update(changes)
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')
        for changes in [dict(cleanupObserved=False), dict(guardrailUsed=True), dict(returncode=-signal.SIGALRM)]:
            cases = exec_evidence()
            cases[-1].update(changes)
            self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')
        cases = exec_evidence()
        self.event(cases, stage='S3')['clock'] = 'python.monotonic'
        self.assertNotEqual(self.assess(cases)['result'], 'tracedExecCompatibilityObserved')


if __name__ == '__main__':
    unittest.main()
