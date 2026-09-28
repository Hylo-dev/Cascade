#
# run.py
# Cascade
#
from dataclasses import dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import time
import uuid


def snapshot_field_valid(event, field):
    """snapshot_field_valid rejects Python's bool-as-int coercion and absent status fields."""
    value = event.get(field)
    if field in ['api', 'validity']:
        return type(value) is int and -(2 ** 31) <= value < 2 ** 31
    if field in ['status', 'flags', 'runtime']:
        return type(value) is int and 0 <= value < 2 ** 32
    if field in ['valid', 'hard', 'kill', 'debugged', 'platform']:
        return type(value) is bool
    return type(value) is str and bool(value)


def termination_evidence(case):
    """termination_evidence separates an observed exit from normal fixture completion."""
    supervisor = dict(kind='unknown', rawReturncode=case.get('returncode'))
    code = case.get('returncode')
    if case.get('supervisorWaitObserved') is True and type(code) is int:
        supervisor = (dict(kind='signaled', signal=-code, rawReturncode=code) if code < 0 else
                      dict(kind='exited', exitCode=code, rawReturncode=code))
    child = dict(kind='unknown')
    child_pid = case.get('childPID')
    waits = [event for event in case.get('events', []) if event.get('kind') == 'childExit' and
             type(child_pid) is int and child_pid > 0 and event.get('childPID') == child_pid]
    if case.get('childWaitObserved') is True and len(waits) == 1 and waits[0].get('observed') is True:
        status = waits[0].get('waitStatus')
        if type(status) is int and 0 <= status <= 65535:
            child = dict(kind='unknown', rawWaitStatus=status)
            if os.WIFEXITED(status):
                child.update(kind='exited', exitCode=os.WEXITSTATUS(status))
            elif os.WIFSIGNALED(status):
                child.update(kind='signaled', signal=os.WTERMSIG(status))
    successful = all(exit_info.get('kind') == 'exited' and exit_info.get('exitCode') == 0
                     for exit_info in [supervisor, child])
    guarded = any(exit_info.get('kind') == 'signaled' and exit_info.get('signal') == signal.SIGALRM
                  for exit_info in [supervisor, child])
    return dict(supervisorTermination=supervisor, childTermination=child,
                normalCompletionObserved=successful, guardTerminationObserved=guarded)


def reduce_evidence(cases):
    """reduce_evidence fails closed while preserving observed protection regressions."""
    if len(cases) == 5 and cases[-1].get('phase') == 'U':
        # Appending the diagnostic never erases or promotes the independent C prefix.
        result = reduce_evidence(cases[:4])
        result.update(untraced_assessment(cases))
        return result
    result = dict(result='unknown', characterization='development',
                  nativeLauncherAdmitted=False, allVMProtectionsPreserved='unknown',
                  workerExecPerformed=False, basicCompatibilityObserved=False, tracedExecCompatibilityObserved=False)
    result.update(refusals=[], regressions=[], unavailableEvidence=[], terminations=[])
    for case in cases:
        termination = dict(phase=case.get('phase'), role=case.get('role'), **termination_evidence(case))
        result['terminations'].append(termination)
        if not termination['normalCompletionObserved']:
            result['unavailableEvidence'].append(dict(phase=case.get('phase'), role=case.get('role'),
                                                       stage='exit', field='normalCompletionObserved'))
    snapshots = {}
    for case in cases:
        for event in case.get('events', []):
            location = dict(phase=case.get('phase'), role=event.get('role', case.get('role')),
                            stage=event.get('stage', event.get('kind')))
            if event.get('kind') == 'controls' and (type(event.get('hardNproc')) is not int or event['hardNproc'] != 0):
                result['unavailableEvidence'].append(dict(location, field='hardNproc'))
            if event.get('kind') in ['ptrace', 'continue', 'execFailure']:
                for field in ['result', 'errno']:
                    value = event.get(field)
                    if type(value) is not int or (field == 'result' and value not in [-1, 0]) or (field == 'errno' and value < 0):
                        result['unavailableEvidence'].append(dict(location, field=field))
                if type(event.get('result')) is int and event['result'] == -1:
                    result['refusals'].append(dict(location, errno=event.get('errno')))
                continue
            if event.get('kind') != 'snapshot':
                continue
            for field in ['api', 'validity', 'status', 'flags', 'runtime', 'valid', 'hard', 'kill',
                          'debugged', 'platform', 'identity', 'hash', 'team', 'entitlements']:
                if not snapshot_field_valid(event, field):
                    result['unavailableEvidence'].append(dict(location, field=field))
            validity = event.get('validity')
            api_available = snapshot_field_valid(event, 'api') and event['api'] == 0
            validity_observed = api_available or all(type(event.get(key)) is int and event[key] == 0
                                                    for key in (['copyGuestStatus', 'requirementStatus'] if event.get('source') == 'guest' else ['copySelfStatus', 'requirementStatus']))
            if snapshot_field_valid(event, 'validity') and validity_observed and validity != 0:
                result['regressions'].append(dict(location, field='validity', value=validity))
            if not api_available:
                result['unavailableEvidence'].append(dict(location, field='api'))
                continue
            for field, bad_value in [('valid', False), ('debugged', True)]:
                if event.get(field) is bad_value:
                    result['regressions'].append(dict(location, field=field, value=bad_value))
            key = event.get('subjectRole', event.get('role'))
            previous = snapshots.get(key)
            if previous:
                fields = ['status', 'flags', 'identity', 'hash', 'team', 'entitlements', 'runtime']
                for field in fields:
                    before, after = previous.get(field), event.get(field)
                    if snapshot_field_valid(previous, field) and snapshot_field_valid(event, field) and before != after:
                        result['regressions'].append(dict(location, field=field, before=before, after=after))
                for field in ['hard', 'kill']:
                    if previous.get(field) is True and event.get(field) is False:
                        result['regressions'].append(dict(location, field=field, before=True, after=False))
            snapshots[key] = event
    for case in cases:
        fingerprint = case.get('matchedArtifacts')
        if type(fingerprint) is not str or len(fingerprint) != 64 or any(c not in '0123456789abcdef' for c in fingerprint):
            result['unavailableEvidence'].append(dict(phase=case.get('phase'), role=case.get('role'),
                                                       stage='case', field='matchedArtifacts'))
    if len(cases) == 4 and cases[-1].get('phase') == 'C':
        result.update(exec_assessment(cases))
    # Independently observed facts survive incomplete records. Their summary has
    # explicit precedence; missing values are never evidence of invalidity.
    if result['regressions']:
        result['tracedExecCompatibilityObserved'] = False
        return dict(result, result='weakened')
    if result['refusals']:
        result['tracedExecCompatibilityObserved'] = False
        return dict(result, result='rejected')
    if result['unavailableEvidence']:
        result['tracedExecCompatibilityObserved'] = False
        return result
    if len(cases) == 4 and result['tracedExecCompatibilityObserved']:
        return dict(result, result='tracedExecCompatibilityObserved')
    if [(c.get('phase'), c.get('role')) for c in cases] != [('A', 'Stub'), ('A', 'Worker'), ('B', 'Stub')]:
        return result
    for case in cases:
        if not all(case.get(key) is True for key in ['cleanupObserved', 'positiveControls', 'recordProtocolValid']):
            return result
        if case.get('guardrailUsed') is not False or case.get('matchedArtifacts') != cases[0].get('matchedArtifacts'):
            return result
        events = case.get('events', [])
        for role in ['Supervisor', case['role']]:
            for stage in ['S0', 'S1', 'S2']:
                found = [e for e in events if e.get('kind') == 'snapshot' and
                         e.get('role') == role and e.get('stage') == stage]
                if len(found) != 1:
                    return result
                event = found[0]
                if any(event.get(key) is None for key in ['status', 'flags', 'identity', 'hash', 'team',
                                                         'entitlements', 'runtime', 'hard', 'kill']):
                    return result
                if event.get('valid') is not True or not event['flags'] & 65536:
                    return result
                expected = 'none' if role == 'Supervisor' else 'sandbox'
                if event['entitlements'] != expected:
                    return result
        controls = [e for e in events if e.get('kind') == 'controls' and e.get('role') == case['role']]
        if len(controls) != 1 or any(controls[0].get(k) is not True
                                   for k in ['fileDenied', 'socketDenied', 'raiseDenied']) or controls[0].get('hardNproc') != 0:
            return result
    trace = [e for e in cases[-1]['events'] if e.get('kind') == 'ptrace']
    if len(trace) != 1 or trace[0].get('result') != 0:
        return result
    return dict(result, result='basicCompatibilityObserved', basicCompatibilityObserved=True)


def exec_assessment(cases):
    """exec_assessment requires fresh stopped-image validation before one successful release."""
    basic = reduce_evidence(cases[:3])['result'] == 'basicCompatibilityObserved'
    outcome = dict(basicCompatibilityObserved=basic, tracedExecCompatibilityObserved=False,
                   workerExecPerformed=False)
    case = cases[-1]
    events = case.get('events', [])
    def one(kind, role, stage=None):
        found = [e for e in events if e.get('kind') == kind and e.get('role') == role and
                 (stage is None or e.get('stage') == stage)]
        return found[0] if len(found) == 1 else {}
    def native_number(value):
        return type(value) in [int, float] and math.isfinite(value) and value > 0
    external = one('snapshot', 'Supervisor', 'S3')
    worker = one('snapshot', 'Worker', 'S4')
    baseline = next((e for e in cases[1]['events'] if e.get('kind') == 'snapshot' and
                     e.get('role') == 'Worker' and e.get('stage') == 'S0'), {})
    stop = one('execStop', 'Supervisor')
    child_pid = case.get('childPID')
    if (not basic or case.get('role') != 'Stub' or
        case.get('matchedArtifacts') != cases[0]['matchedArtifacts'] or
        case.get('recordProtocolValid') is not True):
        return outcome
    if (type(child_pid) is not int or child_pid <= 0 or
        type(stop.get('childPID')) is not int or stop['childPID'] != child_pid or
        stop.get('observed') is not True or type(stop.get('waitStatus')) is not int or
        not 0 <= stop['waitStatus'] <= 65535 or not os.WIFSTOPPED(stop['waitStatus']) or
        os.WSTOPSIG(stop['waitStatus']) != signal.SIGTRAP or
        type(stop.get('signal')) is not int or stop['signal'] != signal.SIGTRAP):
        return outcome
    if (external.get('subjectRole') != 'Worker' or
        type(external.get('subjectPID')) is not int or external['subjectPID'] != child_pid or
        external.get('source') != 'guest' or external.get('fieldsAvailable') is not True or
        external.get('baselineMatched') is not True or
        any(type(external.get(k)) is not int or external[k] != 0 for k in
            ['api', 'copyGuestStatus', 'requirementStatus', 'informationStatus', 'validity']) or
        any(not snapshot_field_valid(external, k) or external[k] != baseline.get(k)
            for k in ['identity', 'hash', 'team'])):
        return outcome
    if (any(e.get('clock') != 'CLOCK_MONOTONIC' or not native_number(e.get('time'))
            for e in [stop, external]) or stop['time'] > external['time']):
        return outcome
    # An authenticated replacement is already an observed fact while stopped.
    # Later continuation, S4, guard use or cleanup cannot erase that partial fact.
    outcome['workerExecPerformed'] = True
    if case.get('guardrailUsed') is not False:
        return outcome
    # Reuse the established setup gates without counting S3 as a Supervisor self snapshot.
    setup = dict(case, phase='A', events=[e for e in events if e.get('stage') not in ['S3', 'S4'] and
                                        e.get('role') != 'Worker'])
    if not baseline_ready(setup):
        return outcome
    grant = one('execGrant', 'Supervisor')
    intent = one('execIntent', 'Stub')
    continue_intent = one('continueIntent', 'Supervisor')
    continued = one('continue', 'Supervisor')
    inherited = one('guardInherited', 'Worker')
    guard = one('guard', 'Stub')
    controls = one('controls', 'Worker')
    trace = one('ptrace', 'Stub')
    if not all([stop, grant, intent, external, continue_intent, continued, worker, inherited, guard, controls, trace]):
        return outcome
    if any(type(e.get('childPID')) is not int or e['childPID'] != child_pid
           for e in [grant, continue_intent, continued]):
        return outcome
    fields = ['status', 'flags', 'runtime', 'identity', 'hash', 'team', 'entitlements',
              'valid', 'hard', 'kill', 'debugged', 'platform']
    if any(e.get(k) != baseline.get(k) for e in [external, worker] for k in fields):
        return outcome
    if any(type(e.get(k)) is not int or e[k] != 0 for e in [trace, continued] for k in ['result', 'errno']):
        return outcome
    if (controls.get('inherited') is not True or
        any(type(controls.get(k)) is not int or controls[k] != 0 for k in ['hardNproc', 'softNproc']) or
        any(controls.get(k) is not True for k in ['fileDenied', 'socketDenied', 'raiseDenied']) or
        any(inherited.get(k) is not True for k in ['armed', 'defaultSignal', 'unblocked'])):
        return outcome
    ordered = [grant, intent, stop, external, continue_intent, continued, worker, inherited, controls]
    if any(e.get('clock') != 'CLOCK_MONOTONIC' or not native_number(e.get('time')) for e in ordered + [guard]):
        return outcome
    if not native_number(continued.get('requestTime')) or continued['requestTime'] > continued['time']:
        return outcome
    ordering_times = [e['requestTime'] if e is continued else e['time'] for e in ordered]
    if any(a > b for a, b in zip(ordering_times, ordering_times[1:])):
        return outcome
    lower = guard.get('lowerBound')
    if (not native_number(lower) or inherited.get('lowerBound') != lower or
        not native_number(inherited.get('remainingSeconds')) or controls['time'] >= lower or
        guard.get('seconds') != 2):
        return outcome
    return dict(outcome, tracedExecCompatibilityObserved=True)


def native_time(value):
    """native_time rejects foreign-clock payloads and bool masquerading as a number."""
    return type(value) in [int, float] and math.isfinite(value) and value > 0


def one_event(case, kind, role, stage=None):
    """one_event requires exactly one record for a protocol milestone."""
    found = [e for e in case.get('events', []) if e.get('kind') == kind and e.get('role') == role and
             (stage is None or e.get('stage') == stage)]
    return found[0] if len(found) == 1 else {}


def matched_self(event, baseline, role, pid):
    """matched_self accepts actual successful self fields for the owned same-build image."""
    fields = ['status', 'flags', 'runtime', 'identity', 'hash', 'team', 'entitlements',
              'valid', 'hard', 'kill', 'debugged', 'platform']
    return (event.get('role') == role and event.get('subjectRole') == role and
            type(event.get('subjectPID')) is int and event['subjectPID'] == pid and
            event.get('source') == 'self' and event.get('fieldsAvailable') is True and
            event.get('baselineMatched') is True and
            all(type(event.get(k)) is int and event[k] == 0 for k in
                ['api', 'copySelfStatus', 'requirementStatus', 'informationStatus', 'validity']) and
            all(snapshot_field_valid(event, k) and event[k] == baseline.get(k) for k in fields))


def exec_setup_matches(cases, case):
    """exec_setup_matches validates the unchanged pre-exec public fields and controls."""
    if (case.get('role') != 'Stub' or case.get('matchedArtifacts') != cases[0].get('matchedArtifacts') or
        any(case.get(k) is not True for k in ['cleanupObserved', 'positiveControls', 'recordProtocolValid',
                                             'supervisorWaitObserved', 'childWaitObserved'])):
        return False
    for role, pid_key, baseline_case in [('Supervisor', 'supervisorPID', cases[0]),
                                         ('Stub', 'childPID', cases[0])]:
        baseline = one_event(baseline_case, 'snapshot', role, 'S0')
        for stage in ['S0', 'S1', 'S2']:
            if not matched_self(one_event(case, 'snapshot', role, stage), baseline, role, case.get(pid_key)):
                return False
    controls = one_event(case, 'controls', 'Stub')
    return (all(type(controls.get(k)) is int and controls[k] == 0 for k in ['hardNproc', 'softNproc']) and
            all(controls.get(k) is True for k in ['fileDenied', 'socketDenied', 'raiseDenied']))


def untraced_control_ready(cases):
    """untraced_control_ready admits one contrast only after the exact pre-marker C failure."""
    if [(c.get('phase'), c.get('role')) for c in cases] != [
            ('A', 'Stub'), ('A', 'Worker'), ('B', 'Stub'), ('C', 'Stub')]:
        return False
    assessment = reduce_evidence(cases)
    case = cases[3]
    termination = termination_evidence(case)
    if (assessment['result'] != 'unknown' or assessment['workerExecPerformed'] is not True or
        assessment['basicCompatibilityObserved'] is not True or not exec_setup_matches(cases, case) or
        termination['normalCompletionObserved'] or
        any(termination[k].get('kind') not in ['exited', 'signaled']
            for k in ['supervisorTermination', 'childTermination']) or
        any(e.get('role') == 'Worker' or e.get('stage') == 'S4' for e in case['events'])):
        return False
    trace = one_event(case, 'ptrace', 'Stub')
    grant = one_event(case, 'execGrant', 'Supervisor')
    intent = one_event(case, 'execIntent', 'Stub')
    stop = one_event(case, 'execStop', 'Supervisor')
    external = one_event(case, 'snapshot', 'Supervisor', 'S3')
    pre_call = one_event(case, 'continueIntent', 'Supervisor')
    continued = one_event(case, 'continue', 'Supervisor')
    if (not all([trace, grant, intent, stop, external, pre_call, continued]) or
        intent.get('targetRole') != 'Worker' or
        any(type(e.get(k)) is not int or e[k] != 0 for e in [trace, continued] for k in ['result', 'errno']) or
        any(type(e.get('childPID')) is not int or e['childPID'] != case['childPID']
            for e in [grant, pre_call, continued])):
        return False
    baseline = one_event(cases[1], 'snapshot', 'Worker', 'S0')
    fields = ['status', 'flags', 'runtime', 'identity', 'hash', 'team', 'entitlements',
              'valid', 'hard', 'kill', 'debugged', 'platform']
    if any(not snapshot_field_valid(external, k) or external[k] != baseline.get(k) for k in fields):
        return False
    guard = one_event(case, 'guard', 'Stub')
    child_exit = one_event(case, 'childExit', 'Supervisor')
    ordered = [guard, trace, grant, intent, stop, external, pre_call, continued, child_exit]
    if (any(e.get('clock') != 'CLOCK_MONOTONIC' or not native_time(e.get('time')) for e in ordered) or
        not native_time(continued.get('requestTime')) or continued['requestTime'] > continued['time']):
        return False
    lower = guard.get('lowerBound')
    if (not native_time(lower) or type(guard.get('seconds')) is not int or guard['seconds'] != 2 or
        continued['time'] >= lower):
        return False
    times = [e['requestTime'] if e is continued else e['time'] for e in ordered]
    return all(a <= b for a, b in zip(times, times[1:]))


def untraced_assessment(cases):
    """untraced_assessment is separate from C authentication and production admission."""
    case = cases[-1]
    termination = termination_evidence(case)
    local = reduce_evidence([case])
    outcome = dict(untracedExecCompatibilityObserved=False,
                   untracedControl=dict(result='unknown', **termination,
                       **{key: local[key] for key in ['refusals', 'regressions', 'unavailableEvidence']}))
    if (case.get('phase') != 'U' or not untraced_control_ready(cases[:4]) or
        not exec_setup_matches(cases, case) or case.get('guardrailUsed') is not False or
        not termination['normalCompletionObserved'] or
        any(e.get('kind') in ['ptrace', 'execStop', 'continueIntent', 'continue', 'signalStop', 'cleanupRequest', 'execFailure'] or
            e.get('stage') == 'S3' for e in case['events'])):
        return outcome
    # Actual U observations retain their own refusals/regressions, never overwrite C.
    if local['refusals'] or local['regressions'] or local['unavailableEvidence']:
        return outcome
    worker = one_event(case, 'snapshot', 'Worker', 'S4')
    baseline = one_event(cases[1], 'snapshot', 'Worker', 'S0')
    if not matched_self(worker, baseline, 'Worker', case['childPID']):
        return outcome
    main = [e for e in case['events'] if e.get('kind') == 'workerProgress' and e.get('point') == 'mainEntry']
    if len(main) != 1 or main[0].get('role') != 'Worker' or main[0].get('boundary') != 'reached':
        return outcome
    grant = one_event(case, 'execGrant', 'Supervisor')
    intent = one_event(case, 'execIntent', 'Stub')
    inherited = one_event(case, 'guardInherited', 'Worker')
    guard = one_event(case, 'guard', 'Stub')
    controls = one_event(case, 'controls', 'Worker')
    if (type(grant.get('childPID')) is not int or grant['childPID'] != case['childPID'] or
        intent.get('targetRole') != 'Worker' or controls.get('inherited') is not True or
        any(type(controls.get(k)) is not int or controls[k] != 0 for k in ['hardNproc', 'softNproc']) or
        any(controls.get(k) is not True for k in ['fileDenied', 'socketDenied', 'raiseDenied']) or
        any(inherited.get(k) is not True for k in ['armed', 'defaultSignal', 'unblocked'])):
        return outcome
    ordered = [guard, grant, intent, main[0], worker, inherited, controls]
    if (any(e.get('clock') != 'CLOCK_MONOTONIC' or not native_time(e.get('time')) for e in ordered) or
        any(a['time'] > b['time'] for a, b in zip(ordered, ordered[1:]))):
        return outcome
    lower = guard.get('lowerBound')
    if (not native_time(lower) or inherited.get('lowerBound') != lower or
        not native_time(inherited.get('remainingSeconds')) or controls['time'] >= lower or
        type(guard.get('seconds')) is not int or guard['seconds'] != 2):
        return outcome
    outcome['untracedControl']['result'] = 'untracedExecCompatibilityObserved'
    outcome['untracedExecCompatibilityObserved'] = True
    return outcome


def baseline_argument(cases, role):
    """baseline_argument binds native phase gates to this build's accepted public snapshot."""
    snapshot = next(e for c in cases for e in c['events'] if e.get('kind') == 'snapshot' and
                    e.get('role') == role and e.get('stage') == 'S0')
    return ':'.join(str(snapshot[k]) for k in ['status', 'flags', 'runtime', 'hash', 'team', 'entitlements'])


def baseline_ready(case):
    """baseline_ready requires a complete individual baseline before the next fixture."""
    if case.get('phase') != 'A' or case.get('role') not in ['Stub', 'Worker']:
        return False
    assessment = reduce_evidence([case])
    if assessment['result'] in ['weakened', 'rejected'] or assessment['unavailableEvidence']:
        return False
    if not all(case.get(k) is True for k in ['cleanupObserved', 'positiveControls', 'recordProtocolValid']):
        return False
    if case.get('guardrailUsed') or case.get('returncode') != 0:
        return False
    for role in ['Supervisor', case['role']]:
        for stage in ['S0', 'S1', 'S2']:
            found = [e for e in case['events'] if e.get('kind') == 'snapshot' and
                     e.get('role') == role and e.get('stage') == stage]
            if len(found) != 1:
                return False
            event = found[0]
            if (event.get('api') != 0 or event.get('validity') != 0 or event.get('valid') is not True or
                event.get('debugged') is not False or not event.get('flags', 0) & 65536 or
                event.get('entitlements') != ('none' if role == 'Supervisor' else 'sandbox')):
                return False
    controls = [e for e in case['events'] if e.get('kind') == 'controls']
    return (len(controls) == 1 and controls[0].get('hardNproc') == 0 and
            all(controls[0].get(k) is True for k in ['fileDenied', 'socketDenied', 'raiseDenied']))


def baseline_sequence_ready(cases):
    """baseline_sequence_ready prevents a fresh case from masking prior incompatibility."""
    expected = [('A', 'Stub'), ('A', 'Worker')]
    if len(cases) not in [1, 2] or [(c.get('phase'), c.get('role')) for c in cases] != expected[:len(cases)]:
        return False
    assessment = reduce_evidence(cases)
    if assessment['result'] in ['weakened', 'rejected'] or assessment['unavailableEvidence']:
        return False
    if any(case['matchedArtifacts'] != cases[0]['matchedArtifacts'] for case in cases):
        return False
    return all(baseline_ready(case) for case in cases)


@dataclass(frozen=True)
class LaunchRecordSpec:
    """LaunchRecordSpec carries fixed diagnostic arguments and stricter record binding."""
    arguments: tuple
    owner: str
    log_name: str
    roles: tuple = ('Supervisor', 'Stub', 'Worker')


@dataclass(frozen=True)
class DeathRecordSpec:
    """Fixed death diagnostic; never an addon launch authority."""
    arguments: tuple
    manifest_json: str
    predecessors_json: str
    owner: str = 'A'
    roles: tuple = ('Supervisor', 'Stub', 'Worker')


def run_case(products, phase, role, listener, foreign_file, artifact_hash, baselines=None, *, launch_spec=None, death_spec=None):
    """run_case observes only its direct supervisor and the supervisor's registered fixture child."""
    nonce = uuid.uuid4().hex
    case = dict(phase=phase, role=role, nonce=nonce, events=[], errors=[],
                cleanupObserved=False, guardrailUsed=False, positiveControls=False,
                matchedArtifacts=artifact_hash, recordProtocolValid=True)
    started = time.monotonic()
    process = None
    queue = None
    child_pid = None
    child_exit = False
    supervisor_exit = False
    eof = False
    buffer = b''
    raw = bytearray()
    sequences = {}
    death = None
    try:
        if death_spec is not None:
            from death_run import DeathObserver
            if launch_spec is not None or not isinstance(death_spec, DeathRecordSpec):
                raise ValueError('mutually exclusive death specification')
            death = DeathObserver(case, death_spec)
            if (phase not in ('D0', 'D1', 'D2', 'D3') or role != 'Stub' or death_spec.owner != 'A' or
                death_spec.roles != ('Supervisor', 'Stub', 'Worker') or type(death_spec.arguments) is not tuple or
                len(death_spec.arguments) != 10 or any(type(a) is not str for a in death_spec.arguments) or
                death_spec.arguments[1:3] != (phase, '') or
                any(death_spec.arguments[index] != death.manifest['products'][key]['path']
                    for index, key in [(0, 'Supervisor'), (3, 'A.Stub'), (6, 'A.Worker')])):
                raise ValueError('invalid frozen death specification')
        # The file is opened, never read. Successful connect is paired with accept.
        descriptor = os.open(foreign_file, os.O_RDONLY | os.O_CLOEXEC)
        os.close(descriptor)
        with socket.create_connection(listener.getsockname(), timeout=0.2):
            accepted, _ = listener.accept()
            accepted.close()
        case['positiveControls'] = True
        arguments = [str(products / 'TraceSupervisor'), phase, nonce, str(products / ('Trace' + role)),
                     str(foreign_file), str(listener.getsockname()[1])]
        if phase in ['C', 'U']:
            arguments += [str(products / 'TraceWorker')] + [baseline_argument(baselines, participant)
                                                         for participant in ['Supervisor', 'Stub', 'Worker']]
        if launch_spec is not None:
            if (not isinstance(launch_spec, LaunchRecordSpec) or
                launch_spec.owner not in ('A', 'B') or
                launch_spec.log_name != phase + '-owner.jsonl' or
                len(launch_spec.arguments) != 12 or launch_spec.arguments[1] != phase):
                raise ValueError('invalid frozen launch specification')
            arguments = list(launch_spec.arguments)
            arguments[2] = nonce
            case['owner'] = launch_spec.owner
        if death is not None:
            arguments = list(death_spec.arguments)
            arguments[2] = nonce
        case['command'] = arguments
        # Queue failure creates no fixture process; every later operation is now
        # inside owned cleanup, so setup exceptions retain the case and exact PID.
        queue = select.kqueue()
        case['prePopenMonotonic'] = time.monotonic()
        process = subprocess.Popen(arguments, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, close_fds=True,
                                   **({'start_new_session': True} if death is not None else {}))
        case['supervisorPID'] = process.pid
        if death is not None:
            death.created(process)
            queue.control([select.kevent(process.stdout.fileno(), filter=select.KQ_FILTER_READ, flags=select.KQ_EV_ADD)], 0)
            try:
                death.register(queue, process.pid, 'Supervisor')
            except OSError as error:
                # A refused proc attachment does not invalidate the successfully
                # attached stdout filter. Fail admission and retain one bounded
                # drain loop; no token or further registration may follow.
                death.fail(error)
        else:
            queue.control([select.kevent(process.stdout.fileno(), filter=select.KQ_FILTER_READ,
                                          flags=select.KQ_EV_ADD),
                           select.kevent(process.pid, filter=select.KQ_FILTER_PROC,
                                          flags=select.KQ_EV_ADD, fflags=select.KQ_NOTE_EXIT)], 0)
        while time.monotonic() - started < 5 and not ((death.exits_observed() if death is not None else supervisor_exit) and eof):
            remaining = 4 - (time.monotonic() - started)
            if remaining <= 0 and (not case['guardrailUsed'] or (death is not None and not case['fallbackAttempted'])):
                case['guardrailUsed'] = True
                process.stdin.close()
                if death is not None:
                    death.fallback('external cleanup cutoff')
                elif not supervisor_exit:
                    # This PID is still our unreaped direct child, never a PID lookup.
                    process.kill()
                remaining = 5 - (time.monotonic() - started)
            if case['guardrailUsed']:
                remaining = 5 - (time.monotonic() - started)
            try:
                events = queue.control(None, 8, max(0, remaining))
            except Exception as error:
                if death is None:
                    raise
                death.queue_usable = False
                death.fail(error)
                break
            for notification in events:
                if death is not None:
                    try:
                        if type(notification.filter) is not int:
                            raise ValueError('mistyped notification filter')
                        if notification.filter == select.KQ_FILTER_PROC:
                            death.notification(notification)
                            continue
                        if (type(notification.ident) is not int or notification.ident != process.stdout.fileno() or
                            notification.filter != select.KQ_FILTER_READ or type(notification.flags) is not int or
                            not 0 <= notification.flags <= 65535 or notification.flags & select.KQ_EV_ERROR):
                            raise ValueError('invalid stdout notification')
                    except Exception as error:
                        death.fail(error)
                        continue
                if notification.filter == select.KQ_FILTER_PROC:
                    if notification.ident == process.pid:
                        supervisor_exit = True
                        case['supervisorExitEventTime'] = time.monotonic()
                    elif notification.ident == child_pid:
                        child_exit = True
                        case['childExitEventTime'] = time.monotonic()
                    continue
                try:
                    data = os.read(process.stdout.fileno(), 4096)
                except OSError as error:
                    if death is None:
                        raise
                    death.fail(error)
                    continue
                if not data:
                    eof = True
                    try:
                        queue.control([select.kevent(process.stdout.fileno(), filter=select.KQ_FILTER_READ,
                                                      flags=select.KQ_EV_DELETE)], 0)
                    except Exception as error:
                        if death is None:
                            raise
                        death.queue_usable = False
                        death.fail(error)
                    continue
                if (launch_spec is not None or death is not None) and len(raw) + len(data) > 262144:
                    raw.extend(data[:262144 - len(raw)])
                    if death is not None:
                        death.fail(ValueError('record output limit'))
                        buffer = b''
                        continue
                    raise ValueError('record output limit')
                raw.extend(data)
                if len(raw) > 262144:
                    raise ValueError('record output limit')
                buffer += data
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    if death is not None:
                        try:
                            if len(line) > 4096 or len(case['events']) >= 96:
                                raise ValueError('record count or line limit')
                            death.record(json.loads(line))
                            child_pid = death.child
                        except Exception as error:
                            death.fail(error)
                        continue
                    if len(line) > 4096 or len(case['events']) >= 96:
                        raise ValueError('record count or line limit')
                    event = json.loads(line)
                    pid = event.get('pid')
                    if (event.get('nonce') != nonce or event.get('phase') != phase or
                        event.get('sequence') != sequences.get(pid, 0) + 1 or
                        event.get('role') not in (launch_spec.roles if launch_spec is not None else
                            (['Supervisor', 'Stub', 'Worker'] if phase in ['C', 'U'] else ['Supervisor', role]))):
                        raise ValueError('nonce, phase, role or sequence mismatch')
                    if launch_spec is not None and (
                        event.get('owner') != launch_spec.owner or type(pid) is not int or pid <= 0 or
                        type(event.get('sequence')) is not int or event['sequence'] > 32 or
                        event.get('clock') != 'CLOCK_MONOTONIC' or not native_time(event.get('time'))):
                        raise ValueError('owner, PID, count or native timestamp mismatch')
                    # Ancillary Worker diagnostics use the same explicit native clock;
                    # they never substitute for S4 or any compatibility gate.
                    if event.get('kind') == 'workerProgress' and (
                        event.get('clock') != 'CLOCK_MONOTONIC' or
                        type(event.get('time')) not in [int, float] or
                        not math.isfinite(event['time']) or event['time'] <= 0):
                        raise ValueError('invalid Worker progress clock or timestamp')
                    if event['role'] == 'Supervisor' and pid != process.pid:
                        raise ValueError('wrong owned supervisor')
                    # Child may write its guard before the parent's spawn record arrives.
                    sequences[pid] = event['sequence']
                    case['events'].append(event)
                    if event.get('kind') == 'spawn' and event.get('result') == 0:
                        if child_pid is not None:
                            raise ValueError('duplicate spawn')
                        child_pid = event['childPID']
                        case['childPID'] = child_pid
                        queue.control([select.kevent(child_pid, filter=select.KQ_FILTER_PROC,
                                                      flags=select.KQ_EV_ADD, fflags=select.KQ_NOTE_EXIT)], 0)
                        process.stdin.write((nonce + ':' + phase + ':registered').encode())
                        process.stdin.flush()
                if len(buffer) > 4096:
                    if death is None:
                        raise ValueError('unterminated record limit')
                    death.fail(ValueError('unterminated record limit'))
                    buffer = b''
            if death is not None:
                if not death.queue_usable:
                    break
                if not buffer:
                    try:
                        death.after_batch(queue)
                    except Exception as error:
                        death.fail(error)
        if buffer:
            raise ValueError('partial final record')
        for event in case['events']:
            if event['role'] != 'Supervisor' and event['pid'] != child_pid:
                raise ValueError('wrong registered child')
    except Exception as error:
        if death is not None:
            death.queue_usable = False
            death.fail(error)
        else:
            case['errors'].append(type(error).__name__ + ': ' + str(error))
            case['recordProtocolValid'] = False
    finally:
        case['processCreated'] = process is not None
        if process is not None:
            if death is not None:
                death.finish_reservation(eof)
            try:
                if not process.stdin.closed:
                    process.stdin.close()
            except OSError as error:
                case['errors'].append('close stdin: ' + str(error))
            if death is None and not supervisor_exit:
                try:
                    process.kill()
                    case['guardrailUsed'] = True
                except ProcessLookupError:
                    pass
                except OSError as error:
                    case['errors'].append('owned cleanup request: ' + str(error))
            try:
                case['returncode'] = process.wait(timeout=max(0.001, 5 - (time.monotonic() - started)))
                case['supervisorWaitObserved'] = True
                if death is not None:
                    case['directWaitMonotonic'] = time.monotonic()
            except (subprocess.TimeoutExpired, OSError) as error:
                case['supervisorWaitObserved'] = False
                case['errors'].append('direct-child exit observation failed: ' + str(error))
        # Native direct-child wait is authoritative even if its NOTE_EXIT was
        # coalesced with the supervisor exit. Cleanup is separate from success.
        waits = [e for e in case['events'] if e.get('kind') == 'childExit' and e.get('childPID') == child_pid]
        case['childWaitObserved'] = len(waits) == 1 and waits[0].get('observed') is True
        case['childKqueueExitObserved'] = child_exit
        # Missing child identity after a setup error is not proof that the
        # supervisor never spawned it. Keep descendant cleanup unknown.
        case['cleanupObserved'] = case.get('supervisorWaitObserved', False) and child_pid is not None and (
            case['childWaitObserved'] or child_exit)
        if death is not None:
            from death_run import death_termination
            case['childKqueueExitObserved'] = case['procExits'].get('Child', {}).get('exitObserved') is True
            case['cleanupObserved'] = case.get('supervisorWaitObserved', False) and case['childKqueueExitObserved']
            case['stdoutEOFObserved'] = eof
            case.update(death_termination(case))
        else:
            case.update(termination_evidence(case))
        if case['guardTerminationObserved'] or any(e.get('kind') in ['signalStop', 'cleanupRequest'] for e in case['events']):
            case['guardrailUsed'] = True
        case['elapsedSeconds'] = time.monotonic() - started
        case['externalDeadlineSeconds'] = 5
        for resource in [queue, process.stdout if process is not None else None]:
            if resource is not None:
                try:
                    resource.close()
                except OSError as error:
                    case['errors'].append('close observer resource: ' + str(error))
        case['rawLog'] = str(products / (phase + '-death.jsonl' if death is not None else launch_spec.log_name if launch_spec is not None else phase + '-' + role + '.jsonl'))
        try:
            Path(case['rawLog']).write_bytes(raw)
            if death is not None:
                case['rawLogSHA256'] = hashlib.sha256(raw).hexdigest()
                case['rawLogBytes'] = len(raw)
        except OSError as error:
            case['errors'].append('write raw log: ' + str(error))
        if case['errors']:
            case['recordProtocolValid'] = False
    return case


def main():
    """main executes the finite A/B/C characterization and writes failure evidence unconditionally."""
    products = Path(sys.argv[1]).resolve(strict=True)
    report_path = products / 'report.json'
    report = dict(characterization='development', profile='trusted-supervisor-sandboxed-worker',
                  nativeLauncherAdmitted=False, allVMProtectionsPreserved='unknown',
                  workerExecPerformed=False, cases=[], observerExecutable=sys.executable,
                  observerProfile='existing Python observer; unsandboxed desktop execution; no added entitlements',
                  externalDeadlineSeconds=5, explicitRecordAllocationLimitBytes=262144,
                  managedDeathCharacterizationPerformed=False)
    try:
        artifacts = {role: hashlib.sha256((products / ('Trace' + role)).read_bytes()).hexdigest()
                     for role in ['Supervisor', 'Stub', 'Worker']}
        report['artifacts'] = artifacts
        artifact_hash = hashlib.sha256(json.dumps(artifacts, sort_keys=True).encode()).hexdigest()
        # Existing foreign account file: only the observer opens it, never reads it.
        foreign_file = Path.home() / '.zshrc'
        report['foreignFile'] = str(foreign_file)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(4)
            listener.settimeout(0.2)
            for phase, role in [('A', 'Stub'), ('A', 'Worker'), ('B', 'Stub'), ('C', 'Stub'), ('U', 'Stub')]:
                case = (run_case(products, phase, role, listener, foreign_file, artifact_hash, report['cases'])
                        if phase in ['C', 'U'] else run_case(products, phase, role, listener, foreign_file, artifact_hash))
                report['cases'].append(case)
                report.update(reduce_evidence(report['cases']))
                if phase == 'A' and not baseline_sequence_ready(report['cases']):
                    report['stoppedAt'] = phase + '-' + role
                    break
                if phase == 'B' and report['result'] != 'basicCompatibilityObserved':
                    report['stoppedAt'] = 'B-Stub'
                    break
                if phase == 'C':
                    report['stoppedAt'] = 'C-Stub'
                    if not untraced_control_ready(report['cases']):
                        break
                if phase == 'U':
                    report['stoppedAt'] = 'U-Stub'
    except Exception as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
    finally:
        report.update(reduce_evidence(report['cases']))
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(report_path)
        print(report['result'])
    return 0 if report['result'] == 'tracedExecCompatibilityObserved' else 1


if __name__ == '__main__':
    sys.exit(main())
