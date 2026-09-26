#
# TracingEvidenceTests.py
# Cascade
#
import copy
import contextlib
import io
import json
import os
from types import SimpleNamespace
import importlib.util
from pathlib import Path
import unittest
import signal
import socket
import tempfile
from unittest.mock import patch, MagicMock

MODULE = Path(__file__).parents[1] / 'Tracing' / 'run.py'
spec = importlib.util.spec_from_file_location('tracing', MODULE)
tracing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tracing)


def evidence():
    """evidence supplies independent, hand-checked matched characterization data."""
    snapshot = dict(api=0, validity=0, status=769, flags=65536, valid=True,
                    hard=True, kill=True, debugged=False, platform=False, identity='signed',
                    entitlements='sandbox', hash='abc', team='team', runtime=1)
    cases = []
    for phase, role in [('A', 'Stub'), ('A', 'Worker'), ('B', 'Stub')]:
        events = []
        for participant in ['Supervisor', role]:
            for stage in ['S0', 'S1', 'S2']:
                item = dict(snapshot, kind='snapshot', role=participant, stage=stage)
                item['identity'] = participant
                item['entitlements'] = 'none' if participant == 'Supervisor' else 'sandbox'
                events.append(item)
        events += [dict(kind='childExit', childPID=200 + len(cases), waitStatus=0, observed=True)]
        events += [dict(kind='controls', role=role, fileDenied=True, socketDenied=True,
                        hardNproc=0, raiseDenied=True)]
        if phase == 'B':
            events.append(dict(kind='ptrace', result=0, errno=0))
        cases.append(dict(phase=phase, role=role, nonce=phase+role, events=events,
                          cleanupObserved=True, guardrailUsed=False, positiveControls=True,
                          matchedArtifacts='a' * 64, recordProtocolValid=True, returncode=0, supervisorWaitObserved=True,
                          childPID=200 + len(cases), childWaitObserved=True))
    return cases


class TracingEvidenceTests(unittest.TestCase):
    # Removing phase/identity/status/cleanup gates must break these tests.
    def test_complete_matched_evidence_only_characterizes(self):
        result = tracing.reduce_evidence(evidence())
        self.assertEqual(result['result'], 'basicCompatibilityObserved')
        self.assertFalse(result['nativeLauncherAdmitted'])
        self.assertEqual(result['allVMProtectionsPreserved'], 'unknown')

    def test_missing_or_wrong_phase_never_passes(self):
        for cases in [evidence()[:2], evidence()[1:], []]:
            self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')
        cases = evidence()
        cases[2]['phase'] = 'C'
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')

    def test_missing_parent_after_trace_cannot_pass(self):
        cases = evidence()
        cases[2]['events'] = [e for e in cases[2]['events'] if not
                             (e.get('role') == 'Supervisor' and e.get('stage') == 'S2')]
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')

    def test_debugged_hard_kill_invalidity_and_status_drift_stop(self):
        for changes in [dict(debugged=True), dict(hard=False), dict(kill=False),
                        dict(valid=False), dict(validity=-1), dict(status=1025),
                        dict(hash='changed'), dict(entitlements='changed')]:
            cases = evidence()
            cases[2]['events'][2].update(changes)
            self.assertEqual(tracing.reduce_evidence(cases)['result'], 'weakened', changes)

    def test_ptrace_denial_is_distinct_from_setup_failure(self):
        cases = evidence()
        cases[2]['events'][-1].update(result=-1, errno=1)
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'rejected')
        cases = evidence()[:1]
        cases[0]['events'] = [dict(kind='setup', errno=1)]
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')

    def test_alarm_or_kill_request_is_not_observed_cleanup(self):
        for field, value in [('cleanupObserved', False), ('guardrailUsed', True),
                             ('positiveControls', False), ('recordProtocolValid', False)]:
            cases = evidence()
            cases[2][field] = value
            self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')

    def test_api_unavailable_or_mismatched_bytes_cannot_pass(self):
        cases = evidence()
        cases[2]['events'][2]['api'] = -1
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')
        cases = evidence()
        cases[2]['matchedArtifacts'] = 'other'
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')

    def test_baseline_controls_and_debugged_are_required(self):
        cases = evidence()
        cases[0]['events'][-1]['raiseDenied'] = False
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')
        cases = evidence()
        cases[0]['events'][0]['debugged'] = True
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'weakened')


class PartialObservationTests(unittest.TestCase):
    # An unavailable record must not erase a separately observed refusal/regression.
    def test_refusal_survives_unavailable_post_request_snapshot(self):
        cases = evidence()
        cases[2]['events'][-1].update(result=-1, errno=1)
        cases[2]['events'][2]['api'] = -1
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'rejected')
        self.assertEqual(result['refusals'][0]['phase'], 'B')
        self.assertTrue(result['unavailableEvidence'])

    def test_later_regression_survives_earlier_unavailable_record(self):
        cases = evidence()
        cases[0]['events'][0]['api'] = -1
        cases[2]['events'][2]['debugged'] = True
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'weakened')
        self.assertEqual(result['regressions'][0]['stage'], 'S2')
        self.assertTrue(result['unavailableEvidence'])
        # Changing record order does not alter independently observed facts.
        cases[0]['events'].reverse()
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'weakened')

    def test_absent_validity_is_unknown_not_observed_invalidity(self):
        cases = evidence()
        del cases[2]['events'][2]['validity']
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'unknown')
        self.assertEqual(result['regressions'], [])


    def test_failed_information_query_preserves_independently_observed_invalidity(self):
        cases = evidence()
        cases[2]['events'][2].update(api=-1, copySelfStatus=0, requirementStatus=0, validity=-67050)
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'weakened')
        self.assertTrue(result['unavailableEvidence'])
        cases[2]['events'][2].update(copySelfStatus=-1, requirementStatus=-1, validity=-1, valid=False)
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'unknown')
        self.assertEqual(result['regressions'], [])


class RequiredSchemaTests(unittest.TestCase):
    # Missing or mistyped evidence must never become compatibility or regression.
    def test_missing_debugged_and_artifact_identity_reject_partial_evidence(self):
        cases = evidence()
        del cases[2]['events'][2]['debugged']
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')
        cases = evidence()
        for case in cases:
            del case['matchedArtifacts']
        self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')

    def test_typed_required_fields_do_not_accept_truthy_or_numeric_booleans(self):
        for field, bad_value in [('debugged', 0), ('valid', 1), ('hard', 'true'),
                                 ('kill', None), ('platform', 0), ('status', '769'),
                                 ('flags', True), ('runtime', '1'), ('api', False),
                                 ('validity', False), ('identity', ''), ('team', 7), ('hash', '')]:
            with self.subTest(field=field):
                cases = evidence()
                cases[2]['events'][2][field] = bad_value
                result = tracing.reduce_evidence(cases)
                self.assertEqual(result['result'], 'unknown')
                self.assertTrue(result['unavailableEvidence'])

    def test_partial_schema_does_not_hide_other_observed_regression(self):
        cases = evidence()
        del cases[0]['events'][0]['debugged']
        cases[2]['events'][2]['debugged'] = True
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'weakened')
        self.assertTrue(result['unavailableEvidence'])


    def test_control_and_request_numbers_require_integers(self):
        for kind, field, value in [('controls', 'hardNproc', False), ('ptrace', 'result', False),
                                   ('ptrace', 'errno', False), ('ptrace', 'errno', None)]:
            with self.subTest(kind=kind, field=field):
                cases = evidence()
                event = next(e for e in cases[2]['events'] if e.get('kind') == kind)
                event[field] = value
                self.assertEqual(tracing.reduce_evidence(cases)['result'], 'unknown')


class BaselineProgressionTests(unittest.TestCase):
    # Accepting a wrong phase here would authorize a later native case incorrectly.
    def test_only_complete_baseline_can_release_the_next_case(self):
        cases = evidence()
        for case in cases:
            case['returncode'] = 0
        self.assertTrue(tracing.baseline_ready(cases[0]))
        self.assertFalse(tracing.baseline_ready(cases[2]))
        cases[0]['events'] = cases[0]['events'][1:]
        self.assertFalse(tracing.baseline_ready(cases[0]))


class NativeTerminationTests(unittest.TestCase):
    # A real observed exit can prove cleanup without proving successful completion.
    def test_complete_snapshots_followed_by_alarm_or_nonzero_exit_cannot_pass(self):
        for returncode in [-signal.SIGALRM, 7]:
            with self.subTest(returncode=returncode):
                cases = evidence()
                cases[2]['returncode'] = returncode
                result = tracing.reduce_evidence(cases)
                self.assertEqual(result['result'], 'unknown')
                self.assertTrue(cases[2]['cleanupObserved'])
                termination = result['terminations'][2]
                self.assertFalse(termination['normalCompletionObserved'])
                self.assertEqual(termination['guardTerminationObserved'], returncode == -signal.SIGALRM)

    def test_child_alarm_or_nonzero_wait_is_not_normal_success(self):
        for status in [int(signal.SIGALRM), 3 << 8]:
            cases = evidence()
            cases[2]['events'][6]['waitStatus'] = status
            result = tracing.reduce_evidence(cases)
            self.assertEqual(result['result'], 'unknown')
            self.assertFalse(result['terminations'][2]['normalCompletionObserved'])

    def test_alarm_cleanup_keeps_explicit_refusal(self):
        cases = evidence()
        cases[2]['returncode'] = -signal.SIGALRM
        cases[2]['events'][-1].update(result=-1, errno=1)
        result = tracing.reduce_evidence(cases)
        self.assertEqual(result['result'], 'rejected')
        self.assertIn('terminations', result)
        self.assertTrue(result['terminations'][2]['guardTerminationObserved'])


class ObserverProgressionTests(unittest.TestCase):
    # Exercise the real main loop; only the signed-native boundary is substituted.
    def dispatched_cases(self, cases):
        dispatches = []
        def native_boundary(products, phase, role, listener, foreign_file, artifact_hash):
            dispatches.append((phase, role))
            return copy.deepcopy(cases[len(dispatches) - 1])
        with tempfile.TemporaryDirectory(prefix='cascade-tracing-fix1-') as directory:
            products = Path(directory)
            for role in ['Supervisor', 'Stub', 'Worker']:
                (products / ('Trace' + role)).write_bytes(b'offline fixture placeholder')
            with patch.object(tracing, 'run_case', side_effect=native_boundary), \
                 patch.object(tracing.socket, 'socket', return_value=MagicMock()), \
                 patch.object(tracing.sys, 'argv', ['run.py', str(products)]), \
                 contextlib.redirect_stdout(io.StringIO()):
                tracing.main()
            report = __import__('json').loads((products / 'report.json').read_text())
        return dispatches, report

    def test_cross_case_supervisor_regression_stops_before_trace_dispatch(self):
        cases = evidence()
        for case in cases:
            case['returncode'] = 0
        for event in cases[1]['events']:
            if event.get('role') == 'Supervisor':
                event['status'] = 1025
        self.assertTrue(tracing.baseline_ready(cases[0]))
        self.assertTrue(tracing.baseline_ready(cases[1]))
        dispatches, report = self.dispatched_cases(cases)
        self.assertEqual(dispatches, [('A', 'Stub'), ('A', 'Worker')])
        self.assertEqual(report['result'], 'weakened')

    def test_missing_or_mismatched_artifacts_stop_cumulative_progression(self):
        cases = evidence()
        for case in cases:
            case['returncode'] = 0
        cases[1]['matchedArtifacts'] = 'b' * 64
        dispatches, report = self.dispatched_cases(cases)
        self.assertEqual(dispatches, [('A', 'Stub'), ('A', 'Worker')])
        self.assertEqual(report['result'], 'unknown')
        del cases[0]['matchedArtifacts']
        dispatches, report = self.dispatched_cases(cases)
        self.assertEqual(dispatches, [('A', 'Stub')])


class ObserverLifecycleTests(unittest.TestCase):
    # Real run_case parsing/finalization runs with OS boundaries substituted;
    # no signed fixture or arbitrary process is launched by these fault tests.
    def observer_case(self, returncode=0, queue_failure=False, registration_failure=False):
        nonce = '1' * 32
        supervisor_pid, child_pid = 700, 202
        source = evidence()[2]['events']
        records = [dict(kind='spawn', role='Supervisor', result=0, childPID=child_pid)]
        for original in source:
            event = copy.deepcopy(original)
            event.setdefault('role', 'Supervisor' if event['kind'] == 'childExit' else 'Stub')
            records.append(event)
        sequences = {}
        for event in records:
            pid = supervisor_pid if event['role'] == 'Supervisor' else child_pid
            sequences[pid] = sequences.get(pid, 0) + 1
            event.update(pid=pid, sequence=sequences[pid], nonce=nonce, phase='B')
        reader, writer = os.pipe()
        stream = os.fdopen(reader, 'rb', buffering=0)
        os.write(writer, b''.join(json.dumps(event).encode() + b'\n' for event in records))
        os.close(writer)
        process = SimpleNamespace(pid=supervisor_pid, stdin=io.BytesIO(), stdout=stream,
                                  kill=lambda: None, wait=lambda timeout: returncode)
        started = []
        def spawn(*args, **kwargs):
            started.append(supervisor_pid)
            return process
        class Queue:
            def control(self, changes, maximum, timeout=None):
                if changes is not None:
                    if registration_failure:
                        raise OSError(24, 'registration failed')
                    return []
                return [SimpleNamespace(filter=tracing.select.KQ_FILTER_PROC, ident=supervisor_pid),
                        SimpleNamespace(filter=tracing.select.KQ_FILTER_READ, ident=reader)]
            def close(self):
                pass
        listener = MagicMock()
        listener.getsockname.return_value = ('127.0.0.1', 12345)
        listener.accept.return_value = (MagicMock(), ('127.0.0.1', 12345))
        result, raised = None, None
        with tempfile.TemporaryDirectory(prefix='cascade-tracing-fix1-') as directory:
            products = Path(directory)
            foreign_file = products / 'foreign-existing-file'
            foreign_file.touch()
            queue_effect = OSError(24, 'too many open files') if queue_failure else lambda: Queue()
            with patch.object(tracing.subprocess, 'Popen', side_effect=spawn), \
                 patch.object(tracing.select, 'kqueue', side_effect=queue_effect), \
                 patch.object(tracing.socket, 'create_connection', return_value=contextlib.nullcontext()), \
                 patch.object(tracing.uuid, 'uuid4', return_value=SimpleNamespace(hex=nonce)):
                try:
                    result = tracing.run_case(products, 'B', 'Stub', listener, foreign_file, 'a' * 64)
                except Exception as error:
                    raised = error
        stream.close()
        return result, raised, started

    def test_observer_attributes_alarm_from_wait_not_timer_or_cleanup(self):
        for code in [-signal.SIGALRM, 7, 0]:
            with self.subTest(code=code):
                case, raised, started = self.observer_case(code)
                self.assertIsNone(raised)
                self.assertTrue(case['cleanupObserved'])
                self.assertEqual(case['returncode'], code)
                self.assertEqual(case['guardrailUsed'], code == -signal.SIGALRM)
                self.assertIn('normalCompletionObserved', case)
                self.assertEqual(case['normalCompletionObserved'], code == 0)

    def test_queue_allocation_failure_reports_case_without_spawning(self):
        case, raised, started = self.observer_case(queue_failure=True)
        self.assertIsNone(raised)
        self.assertEqual(started, [])
        self.assertNotIn('supervisorPID', case)
        self.assertTrue(any('too many open files' in error for error in case['errors']))
        self.assertFalse(case['recordProtocolValid'])


    def test_post_spawn_setup_failure_keeps_owned_wait_without_inventing_child_cleanup(self):
        case, raised, started = self.observer_case(-signal.SIGKILL, registration_failure=True)
        self.assertIsNone(raised)
        self.assertEqual(case['supervisorPID'], 700)
        self.assertTrue(case['supervisorWaitObserved'])
        self.assertEqual(case['returncode'], -signal.SIGKILL)
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(case['normalCompletionObserved'])
        self.assertTrue(any('registration failed' in error for error in case['errors']))


if __name__ == '__main__':
    unittest.main()
