# Bounded U observer tests; native OS endpoints alone are replaced.
import contextlib
import copy
import io
import json
from pathlib import Path
import signal
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch
from TracingExecEvidenceTests import progress_evidence, tracing


def untraced_evidence():
    cases = progress_evidence()
    untraced = copy.deepcopy(cases[-1])
    untraced['phase'] = 'U'
    untraced['events'] = [e for e in untraced['events'] if e.get('kind') not in
                          ['ptrace', 'execStop', 'continueIntent', 'continue'] and e.get('stage') != 'S3']
    cases[-1]['events'] = [e for e in cases[-1]['events'] if e.get('role') != 'Worker']
    cases[-1].update(returncode=25, guardrailUsed=True)
    next(e for e in cases[-1]['events'] if e['kind'] == 'childExit')['waitStatus'] = int(signal.SIGKILL)
    cases[-1]['events'].append(dict(kind='signalStop', role='Supervisor', signal=int(signal.SIGTRAP),
                                    ptraceOperation='PT_KILL', ptraceResult=0, continueResult=0, errno=0))
    cases.append(untraced)
    for index, case in enumerate(cases):
        child = 200 + index
        case.update(supervisorPID=100 + index, childPID=child)
        events = case['events']
        # Child exit follows the native operation records in the synthetic stream.
        exits = [e for e in events if e['kind'] == 'childExit']
        events[:] = [e for e in events if e['kind'] != 'childExit'] + exits
        for offset, event in enumerate(events):
            event.setdefault('role', 'Stub' if event['kind'] == 'ptrace' else 'Supervisor')
            event.update(clock='CLOCK_MONOTONIC', time=100.0 + offset * 0.01)
            if 'childPID' in event:
                event['childPID'] = child
            if event['kind'] == 'execIntent':
                event['targetRole'] = 'Worker'
            if event['kind'] == 'continue':
                event['requestTime'] = event['time']
            if event['kind'] == 'snapshot':
                guest = event.get('stage') == 'S3'
                event.update(subjectRole='Worker' if guest else event['role'],
                             subjectPID=child if guest or event['role'] != 'Supervisor' else 100 + index,
                             source='guest' if guest else 'self', fieldsAvailable=True, baselineMatched=True,
                             copySelfStatus=-1 if guest else 0, copyGuestStatus=0 if guest else -1,
                             requirementStatus=0, informationStatus=0)
            if event['kind'] == 'controls':
                event.update(softNproc=0, setResult=0, setErrno=0)
    return cases


def observe(cases, mutation=None):
    """Run the real finite dispatcher, parser, cleanup and reducer with no fixture processes."""
    dispatched, active = [], {}
    with tempfile.TemporaryDirectory(prefix='cascade-tracing-untraced-offline-') as directory, contextlib.ExitStack() as stack:
        products = Path(directory)
        (products / '.zshrc').touch()
        for role in ['Supervisor', 'Stub', 'Worker']:
            (products / ('Trace' + role)).write_bytes(b'fixed signed artifact stand-in')
        def spawn(arguments, **kwargs):
            index = len(dispatched)
            dispatched.append((arguments[1], Path(arguments[3]).name))
            case = cases[index]
            if arguments[1] != case['phase']:
                raise AssertionError('wrong phase dispatch')
            pid, child = 100 + index, 200 + index
            records = [dict(kind='spawn', role='Supervisor', result=0, childPID=child,
                            clock='CLOCK_MONOTONIC', time=99.9)] + copy.deepcopy(case['events'])
            sequences = {}
            for event in records:
                owner = pid if event['role'] == 'Supervisor' else child
                sequences[owner] = sequences.get(owner, 0) + 1
                event.update(pid=owner, sequence=sequences[owner], nonce=arguments[2], phase=arguments[1])
            if mutation:
                mutation(index, records)
            stream = tempfile.TemporaryFile()
            stream.write(b''.join(json.dumps(e).encode() + b'\n' for e in records))
            stream.seek(0)
            active.update(pid=pid, child=child, descriptor=stream.fileno())
            return SimpleNamespace(pid=pid, stdin=io.BytesIO(), stdout=stream, kill=lambda: None,
                                   wait=lambda timeout: case.get('returncode', 0))
        class Queue:
            def control(self, changes, maximum, timeout=None):
                return [] if changes is not None else [
                    SimpleNamespace(filter=tracing.select.KQ_FILTER_PROC, ident=active['pid']),
                    SimpleNamespace(filter=tracing.select.KQ_FILTER_PROC, ident=active['child']),
                    SimpleNamespace(filter=tracing.select.KQ_FILTER_READ, ident=active['descriptor'])]
            def close(self):
                pass
        listener = MagicMock()
        listener.__enter__.return_value = listener
        listener.getsockname.return_value = ('127.0.0.1', 12345)
        listener.accept.return_value = (MagicMock(), ('127.0.0.1', 12345))
        stack.enter_context(patch.object(tracing.subprocess, 'Popen', side_effect=spawn))
        stack.enter_context(patch.object(tracing.select, 'kqueue', side_effect=Queue))
        stack.enter_context(patch.object(tracing.socket, 'socket', return_value=listener))
        stack.enter_context(patch.object(tracing.socket, 'create_connection', return_value=contextlib.nullcontext()))
        stack.enter_context(patch.object(Path, 'home', return_value=products))
        stack.enter_context(patch.object(tracing.sys, 'argv', ['run.py', str(products)]))
        stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
        code = tracing.main()
        report = json.loads((products / 'report.json').read_text())
        return report, dispatched, code


class TracingUntracedEvidenceTests(unittest.TestCase):
    def test_complete_u_preserves_unknown_authenticated_c_prefix(self):
        report, dispatched, code = observe(untraced_evidence())
        self.assertEqual(dispatched, [('A', 'TraceStub'), ('A', 'TraceWorker'), ('B', 'TraceStub'),
                                      ('C', 'TraceStub'), ('U', 'TraceStub')])
        self.assertEqual(code, 1)
        self.assertEqual(report['result'], 'unknown')
        self.assertTrue(report['basicCompatibilityObserved'])
        self.assertTrue(report['workerExecPerformed'])
        self.assertTrue(report.get('untracedExecCompatibilityObserved'))
        self.assertFalse(report['tracedExecCompatibilityObserved'])
        self.assertFalse(report['nativeLauncherAdmitted'])
        self.assertFalse(report['managedDeathCharacterizationPerformed'])
        self.assertEqual(report['allVMProtectionsPreserved'], 'unknown')
        self.assertEqual(len(report['terminations']), 4)  # C prefix remains independent.

    def test_missing_main_or_s4_cannot_claim_u_success(self):
        for target in ['mainEntry', 'S4']:
            cases = untraced_evidence()
            cases[-1]['events'] = [e for e in cases[-1]['events'] if e.get('point') != target and e.get('stage') != target]
            report, calls, _ = observe(cases)
            self.assertEqual(len(calls), 5)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))
            self.assertTrue(report['workerExecPerformed'])

    def test_u_protocol_rejects_role_clock_sequence_owner(self):
        for change in [dict(role='Foreign'), dict(clock='other'), dict(sequence=0), dict(pid=999),
                       dict(time=True), dict(time=float('nan'))]:
            def mutate(index, records):
                if index == 4:
                    next(e for e in records if e['kind'] == 'workerProgress').update(change)
            report, calls, _ = observe(untraced_evidence(), mutate)
            self.assertEqual(len(calls), 5)
            self.assertFalse(report['cases'][-1]['recordProtocolValid'])
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))

    def test_u_wrong_identity_profile_owner_or_api_cannot_pass(self):
        for change in [dict(hash='wrong'), dict(entitlements='none'), dict(subjectPID=999),
                       dict(source='guest'), dict(fieldsAvailable=False), dict(copySelfStatus=False),
                       dict(validity=-1), dict(status=1), dict(team='wrong'), dict(baselineMatched=False)]:
            cases = untraced_evidence()
            next(e for e in cases[-1]['events'] if e.get('stage') == 'S4').update(change)
            report, calls, _ = observe(cases)
            self.assertEqual(len(calls), 5)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))

    def test_u_failed_signaled_unknown_and_guard_exit_cannot_pass(self):
        for status in [256, int(signal.SIGTRAP), int(signal.SIGALRM), 0x7f]:
            cases = untraced_evidence()
            next(e for e in cases[-1]['events'] if e['kind'] == 'childExit')['waitStatus'] = status
            report, calls, _ = observe(cases)
            self.assertEqual(len(calls), 5)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))
            if status == signal.SIGTRAP:
                self.assertEqual(report['cases'][-1]['childTermination']['kind'], 'signaled')

    def test_u_inherited_controls_guard_and_explicit_false_required(self):
        for kind, change in [('controls', dict(softNproc=1)), ('controls', dict(inherited=False)),
                             ('controls', dict(fileDenied=False)), ('guardInherited', dict(armed=False)),
                             ('guardInherited', dict(lowerBound=103.0))]:
            cases = untraced_evidence()
            next(e for e in cases[-1]['events'] if e['kind'] == kind and e['role'] == 'Worker').update(change)
            report, _, _ = observe(cases)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))
        report, _, _ = observe(untraced_evidence())
        for value in [None, 0, '', True]:
            cases = copy.deepcopy(report['cases'])
            cases[-1]['guardrailUsed'] = value
            self.assertFalse(tracing.reduce_evidence(cases).get('untracedExecCompatibilityObserved', False))
        cases = copy.deepcopy(report['cases'])
        cases[-1]['matchedArtifacts'] = 'b' * 64
        self.assertFalse(tracing.reduce_evidence(cases).get('untracedExecCompatibilityObserved', False))

    def test_c_progress_normal_completion_or_incomplete_cleanup_stops_before_u(self):
        for mode in ['main', 'normal', 'missingExit', 'continueFailure', 'missingContinue', 'wrongS3', 'badClock']:
            cases = untraced_evidence()
            c = cases[3]
            if mode == 'main':
                c['events'].append(dict(kind='workerProgress', role='Worker', point='mainEntry', boundary='reached',
                                        clock='CLOCK_MONOTONIC', time=100.8))
            elif mode == 'normal':
                c['returncode'] = 0
                next(e for e in c['events'] if e['kind'] == 'childExit')['waitStatus'] = 0
            elif mode in ['missingExit', 'missingContinue']:
                kind = 'childExit' if mode == 'missingExit' else 'continue'
                c['events'] = [e for e in c['events'] if e['kind'] != kind]
            elif mode == 'continueFailure':
                next(e for e in c['events'] if e['kind'] == 'continue')['result'] = -1
            elif mode == 'wrongS3':
                next(e for e in c['events'] if e.get('stage') == 'S3')['hash'] = 'wrong'
            else:
                next(e for e in c['events'] if e['kind'] == 'continue')['clock'] = 'other'
            report, calls, _ = observe(cases)
            self.assertEqual(len(calls), 4, mode)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))

    def test_c_guard_controls_and_protocol_gate_the_one_u_dispatch(self):
        for mode in ['guardMissing', 'guardExpired', 'controls', 'wrongOwner', 'sequence', 'clock', 'unknownExit']:
            cases = untraced_evidence()
            c = cases[3]
            if mode == 'guardMissing':
                c['events'] = [e for e in c['events'] if e['kind'] != 'guard']
            elif mode == 'guardExpired':
                next(e for e in c['events'] if e['kind'] == 'guard')['lowerBound'] = 100.01
            elif mode == 'controls':
                next(e for e in c['events'] if e['kind'] == 'controls')['softNproc'] = 1
            elif mode == 'unknownExit':
                next(e for e in c['events'] if e['kind'] == 'childExit')['waitStatus'] = 0x7f
            def mutate(index, records):
                if index == 3 and mode in ['wrongOwner', 'sequence', 'clock']:
                    event = next(e for e in records if e['kind'] == 'continue')
                    event.update({'wrongOwner': dict(pid=999), 'sequence': dict(sequence=0),
                                  'clock': dict(clock='other')}[mode])
            report, calls, _ = observe(cases, mutate)
            self.assertEqual(len(calls), 4, mode)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))

    def test_prior_control_failure_stops_finite_progression(self):
        for index in [0, 1, 2]:
            cases = untraced_evidence()
            cases[index]['returncode'] = 1
            report, calls, _ = observe(cases)
            self.assertEqual(len(calls), index + 1)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))

    def test_no_duplicate_continue_or_u_trace_records_can_pass(self):
        for target in ['C', 'U']:
            cases = untraced_evidence()
            if target == 'C':
                cases[3]['events'].append(copy.deepcopy(next(e for e in cases[3]['events'] if e['kind'] == 'continue')))
            else:
                cases[4]['events'].append(dict(kind='ptrace', role='Stub', result=0, errno=0,
                                              clock='CLOCK_MONOTONIC', time=100.8))
            report, calls, _ = observe(cases)
            self.assertEqual(len(calls), 4 if target == 'C' else 5)
            self.assertFalse(report.get('untracedExecCompatibilityObserved', False))


if __name__ == '__main__':
    unittest.main()
