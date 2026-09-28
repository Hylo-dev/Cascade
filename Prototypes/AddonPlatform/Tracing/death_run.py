"""Finite fixed-code managed-death diagnostic. No production launch authority."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import select
import signal
import socket
import sys
import time
import owner_run as owner
import run as tracing

PHASES = ('D0', 'D1', 'D2', 'D3')
PRODUCTS = ('Supervisor', 'A.Stub', 'A.Worker')
NOTE_EXITSTATUS = 0x04000000
MAX_PID = 2**31 - 1


def integer(value, low=0, high=2**32-1):
    return type(value) is int and low <= value <= high


def exact_profile(key):
    return owner.exact_profile(key)


def manifest_valid(manifest, products):
    try:
        if (manifest['schema'] != 'managed-death-build-v1' or
            type(manifest['runID']) is not str or not re.fullmatch('[0-9a-f]{32}', manifest['runID']) or
            manifest['prefix'] != 'hylo.Cascade.DeathFixture.' + manifest['runID'] or
            set(manifest['products']) != set(PRODUCTS) or type(manifest['team']) is not str or
            not re.fullmatch('[A-Z0-9]+', manifest['team'])):
            return False
        for key in PRODUCTS:
            item = manifest['products'][key]
            if (item['identity'] != manifest['prefix'] + '.' + key or item['infoIdentifier'] != item['identity'] or
                item['path'] != str(products / ('Death' + key.replace('.', ''))) or
                item['team'] != manifest['team'] or item['signerLeafSHA1'] != '4A857D842A5406C2D3071776FDE7B27B3098FE63' or
                item['strictVerified'] is not True or not integer(item['flags']) or item['flags'] != 65536 or
                not integer(item['runtime'], 1) or item['entitlements'] != exact_profile(key) or
                any(type(v) is not bool or v is not True for v in item['entitlements'].values()) or
                type(item['cdhash']) is not str or not re.fullmatch('[0-9a-f]{40,128}', item['cdhash']) or
                hashlib.sha256(Path(item['path']).read_bytes()).hexdigest() != item['hash']):
                return False
        return True
    except (KeyError, TypeError, ValueError, OSError):
        return False


def termination(status):
    result = dict(kind='unknown', rawWaitStatus=status)
    if not integer(status, 0, 65535):
        return result
    if os.WIFEXITED(status):
        result.update(kind='exited', exitCode=os.WEXITSTATUS(status))
    elif os.WIFSIGNALED(status):
        result.update(kind='signaled', signal=os.WTERMSIG(status))
    return result


def death_termination(case):
    """Proc status, direct wait and native wait remain distinct observations."""
    exits = case.get('procExits', {})
    result = {}
    for role in ['Supervisor', 'Child']:
        event = exits.get(role, {})
        result[role.lower() + 'Termination'] = termination(event.get('rawWaitStatus')) if event.get('statusValid') is True else dict(kind='unknown')
    code = case.get('returncode')
    direct = dict(kind='unknown', rawReturncode=code)
    if case.get('supervisorWaitObserved') is True and integer(code, -127, 255):
        direct.update(kind='signaled', signal=-code) if code < 0 else direct.update(kind='exited', exitCode=code)
    result['directSupervisorWait'] = direct
    sup = result['supervisorTermination']
    result['supervisorStatusAgreesWithWait'] = (sup.get('kind') != 'unknown' and
        all(sup.get(key) == direct.get(key) for key in ['kind', 'signal', 'exitCode']))
    native = owner.one(case, 'childExit', 'Supervisor')
    result['nativeChildWaitObserved'] = bool(native and native.get('observed') is True and
        integer(native.get('childPID'), 1, MAX_PID) and native['childPID'] == case.get('childPID') and
        termination(native.get('waitStatus'))['kind'] != 'unknown')
    result['childStatusAgreesWithNativeWait'] = bool(result['nativeChildWaitObserved'] and
        exits.get('Child', {}).get('statusValid') is True and native['waitStatus'] == exits['Child']['rawWaitStatus'])
    result['normalCompletionObserved'] = all(result[key].get('kind') == 'exited' and result[key].get('exitCode') == 0
        for key in ['supervisorTermination', 'childTermination', 'directSupervisorWait'])
    result['guardTerminationObserved'] = any(result[key].get('kind') == 'signaled' and result[key].get('signal') == signal.SIGALRM
        for key in ['supervisorTermination', 'childTermination', 'directSupervisorWait'])
    return result


def adverse(case):
    """Preserve independently authenticated adverse API observations despite later gaps."""
    regressions, refusals = [], []
    for event in case.get('events', []):
        if event.get('kind') in ['ptrace', 'continue', 'execFailure'] and type(event.get('result')) is int and event['result'] == -1:
            refusals.append(dict(kind=event['kind'], errno=event.get('errno')))
        if event.get('kind') != 'snapshot':
            continue
        source = event.get('source')
        reference = {'self': 'copySelfStatus', 'guest': 'copyGuestStatus'}.get(source) if type(source) is str else None
        if reference and all(type(event.get(k)) is int and event[k] == 0 for k in [reference, 'requirementStatus']) and tracing.snapshot_field_valid(event, 'validity') and event['validity'] != 0:
            regressions.append(dict(stage=event.get('stage'), field='validity', value=event['validity']))
        if type(event.get('api')) is int and event['api'] == 0:
            for key, bad in [('valid', False), ('hard', False), ('kill', False), ('debugged', True)]:
                if event.get(key) is bad:
                    regressions.append(dict(stage=event.get('stage'), field=key, value=bad))
    return regressions, refusals


def controls_valid(event, inherited):
    return bool(event and event.get('inherited') is inherited and
        all(type(event.get(k)) is int and event[k] == 0 for k in ['hardNproc', 'softNproc', 'setResult', 'setErrno']) and
        all(event.get(k) is True for k in ['fileDenied', 'socketDenied', 'raiseDenied']) and
        all(type(event.get(k)) is int and event[k] in [1, 13] for k in ['fileErrno', 'socketErrno']) and
        type(event.get('socketResult')) is int and event['socketResult'] == -1 and
        type(event.get('raiseErrno')) is int and event['raiseErrno'] == 1)


def prefix_valid(case, accepted, manifest, *, gate=False):
    """Authenticate the finite native prefix before allowing any injection."""
    phase = case.get('phase')
    if phase not in PHASES or PHASES.index(phase) != len(accepted) or any(c.get('assessment', {}).get('accepted') is not True for c in accepted):
        return False
    if (case.get('recordProtocolValid') is not True or case.get('positiveControls') is not True or case.get('owner') != 'A' or
        case.get('guardrailUsed') is not False or case.get('errors') or case.get('fallbackAttempted') is not False):
        return False
    sup, child = case.get('supervisorPID'), case.get('childPID')
    if not integer(sup, 1, MAX_PID) or not integer(child, 1, MAX_PID) or sup == child:
        return False
    events = case.get('events', [])
    counts = {}
    for e in events:
        pid = e.get('pid')
        if not integer(pid, 1, MAX_PID):
            return False
        counts[pid] = counts.get(pid, 0) + 1
        if (e.get('nonce') != case.get('nonce') or e.get('phase') != phase or e.get('owner') != 'A' or
            type(e.get('sequence')) is not int or e['sequence'] != counts[pid] or counts[pid] > 32 or
            e.get('role') not in ['Supervisor', 'Stub', 'Worker'] or
            pid != (sup if e['role'] == 'Supervisor' else child) or
            not integer(e.get('pgid'), 1, MAX_PID) or e['pgid'] != sup or
            not integer(e.get('sid'), 1, MAX_PID) or e['sid'] != sup or
            e.get('clock') != 'CLOCK_MONOTONIC' or not tracing.native_time(e.get('time'))):
            return False
    if len(events) > 96 or any(e.get('kind') in ['cleanupRequest', 'signalStop', 'execFailure', 'holdFailure'] for e in events):
        return False
    one = lambda kind, role, stage=None: owner.one(case, kind, role, stage)
    spawn = one('spawn', 'Supervisor')
    if not spawn or type(spawn.get('result')) is not int or spawn['result'] != 0 or type(spawn.get('childPID')) is not int or spawn['childPID'] != child:
        return False
    stages = {}
    for role in ['Supervisor', 'Stub']:
        product = manifest['products']['Supervisor' if role == 'Supervisor' else 'A.Stub']
        stages[role] = [one('snapshot', role, stage) for stage in ['S0', 'S1', 'S2']]
        if not all(owner.snapshot_valid(e, product, role, sup if role == 'Supervisor' else child) for e in stages[role]):
            return False
        if not all(owner.same_fields(stages[role][0], e) for e in stages[role][1:]):
            return False
        if accepted and not owner.same_fields(stages[role][0], owner.one(accepted[0], 'snapshot', role, 'S0')):
            return False
    guard, super_guard = one('guard', 'Stub'), one('guard', 'Supervisor')
    grant, intent = one('execGrant', 'Supervisor'), one('execIntent', 'Stub')
    stub_controls = one('controls', 'Stub')
    if (not guard or not super_guard or type(guard.get('seconds')) is not int or guard['seconds'] != 2 or
        type(super_guard.get('seconds')) is not int or super_guard['seconds'] != 3 or
        not tracing.native_time(guard.get('lowerBound')) or not tracing.native_time(super_guard.get('lowerBound')) or
        not grant or type(grant.get('childPID')) is not int or grant['childPID'] != child or
        not intent or intent.get('targetRole') != 'Worker' or not controls_valid(stub_controls, False)):
        return False
    ordered = [super_guard, stages['Supervisor'][0], guard, stages['Stub'][0], stub_controls,
        stages['Stub'][1], stages['Supervisor'][1], stages['Stub'][2], stages['Supervisor'][2], grant, intent]
    if phase != 'D0':
        trace, stop = one('ptrace', 'Stub'), one('execStop', 'Supervisor')
        s3 = one('snapshot', 'Supervisor', 'S3')
        baseline = owner.one(accepted[0], 'snapshot', 'Worker', 'S4')
        if (not trace or any(type(trace.get(k)) is not int or trace[k] != 0 for k in ['result', 'errno']) or
            not stop or type(stop.get('childPID')) is not int or stop['childPID'] != child or
            type(stop.get('waitStatus')) is not int or stop['waitStatus'] != 1407 or
            type(stop.get('signal')) is not int or stop['signal'] != signal.SIGTRAP or stop.get('observed') is not True or
            not owner.snapshot_valid(s3, manifest['products']['A.Worker'], 'Worker', child, True) or
            not owner.same_fields(s3, baseline) or not stages['Supervisor'][1]['time'] <= trace['time'] <= stages['Stub'][2]['time']):
            return False
        ordered += [stop, s3]
        if phase == 'D2':
            hold = one('heldStop', 'Supervisor')
            if (not hold or type(hold.get('childPID')) is not int or hold['childPID'] != child or hold.get('terminal') is not True or
                any(e.get('kind') in ['continueIntent', 'continue'] or e.get('role') == 'Worker' for e in events)):
                return False
            ordered += [hold]
        else:
            pre, continued = one('continueIntent', 'Supervisor'), one('continue', 'Supervisor')
            if (not pre or not continued or any(type(e.get('childPID')) is not int or e['childPID'] != child for e in [pre, continued]) or
                any(type(continued.get(k)) is not int or continued[k] != 0 for k in ['result', 'errno']) or
                not tracing.native_time(continued.get('requestTime')) or continued['requestTime'] > continued['time']):
                return False
            ordered += [pre, dict(time=continued['requestTime'])]
    elif any(e.get('kind') in ['ptrace', 'execStop', 'continueIntent', 'continue', 'heldStop'] or e.get('stage') == 'S3' for e in events):
        return False
    if phase != 'D2':
        main = [e for e in events if e.get('kind') == 'workerProgress' and e.get('point') == 'mainEntry']
        worker, inherited, controls = one('snapshot', 'Worker', 'S4'), one('guardInherited', 'Worker'), one('controls', 'Worker')
        if (len(main) != 1 or main[0].get('role') != 'Worker' or main[0].get('boundary') != 'reached' or
            not owner.snapshot_valid(worker, manifest['products']['A.Worker'], 'Worker', child) or
            (accepted and not owner.same_fields(worker, owner.one(accepted[0], 'snapshot', 'Worker', 'S4'))) or
            not inherited or inherited.get('lowerBound') != guard['lowerBound'] or
            not tracing.native_time(inherited.get('remainingSeconds')) or
            any(inherited.get(k) is not True for k in ['armed', 'defaultSignal', 'unblocked']) or not controls_valid(controls, True)):
            return False
        ordered += [main[0], worker, inherited, controls]
        if phase == 'D3':
            idle = one('idleReady', 'Worker')
            if not idle or idle.get('terminal') is not True:
                return False
            ordered += [idle]
        elif any(e.get('kind') == 'idleReady' for e in events):
            return False
    if phase != 'D2' and any(e.get('kind') == 'heldStop' for e in events):
        return False
    if gate and any(e.get('kind') == 'childExit' for e in events):
        return False
    if (any(left['time'] > right['time'] for left, right in zip(ordered, ordered[1:])) or
        any(e['time'] >= guard['lowerBound'] - .4 for e in ordered[2:]) or
        ordered[-1]['time'] >= super_guard['lowerBound'] or ordered[-1]['time'] - super_guard['time'] >= 1.5):
        return False
    regressions, refusals = adverse(case)
    return not regressions and not refusals


def assess_case(case, accepted, manifest, artifact_hash):
    regressions, refusals = adverse(case)
    result = dict(accepted=False, result='weakened' if regressions else 'rejected' if refusals else 'unknown',
        regressions=regressions, refusals=refusals, unavailableEvidence=[], **death_termination(case))
    def missing(reason):
        result['unavailableEvidence'].append(reason)
        return result
    if case.get('matchedArtifacts') != artifact_hash or not prefix_valid(case, accepted, manifest):
        return missing('finite authenticated native prefix')
    exits = case.get('procExits', {})
    if (any(exits.get(role, {}).get('statusValid') is not True for role in ['Supervisor', 'Child']) or
        case.get('cleanupObserved') is not True or case.get('stdoutEOFObserved') is not True or
        result['supervisorStatusAgreesWithWait'] is not True):
        return missing('complete exact exits, valid statuses, EOF and direct wait')
    if case['phase'] in ['D0', 'D1']:
        if (not result['normalCompletionObserved'] or not result['childStatusAgreesWithNativeWait'] or
            case.get('injectionAttempted') is not False):
            return missing('normal baseline status cross-check')
        child_exit = owner.one(case, 'childExit', 'Supervisor')
        if child_exit['time'] >= owner.one(case, 'guard', 'Stub')['lowerBound']:
            return missing('native baseline exit deadline')
    else:
        injection = case.get('injection', {})
        deadline = case.get('prePopenMonotonic', float('-inf')) + 1.5
        if (case.get('injectionAttempted') is not True or injection.get('succeeded') is not True or
            case.get('fallbackAttempted') is not False or result['nativeChildWaitObserved'] or
            any(result[key].get('kind') != 'signaled' or result[key].get('signal') != signal.SIGKILL for key in ['supervisorTermination', 'childTermination']) or
            not tracing.native_time(injection.get('requestMonotonic')) or not tracing.native_time(injection.get('resultMonotonic')) or
            injection['requestMonotonic'] > injection['resultMonotonic'] or
            any(not tracing.native_time(exits[role].get('receiptMonotonic')) or
                not injection['requestMonotonic'] <= exits[role]['receiptMonotonic'] < deadline for role in ['Supervisor', 'Child']) or
            not tracing.native_time(case.get('directWaitMonotonic')) or not injection['requestMonotonic'] <= case['directWaitMonotonic'] < deadline):
            return missing('injected causal sequence or conservative alarm exclusion')
    result.update(accepted=True, result='fixedDeathCaseObserved')
    return result


class DeathObserver:
    """Bounded policy for the one shared loop; owns no alternate process loop."""
    def __init__(self, case, spec):
        self.case, self.spec = case, spec
        self.manifest = json.loads(spec.manifest_json)
        self.predecessors = json.loads(spec.predecessors_json)
        self.registered = set()
        self.child = None
        self.provisional = None
        self.sequences = {}
        self.last_times = {}
        self.process = None
        self.reserved = False
        self.queue_usable = True
        self.pending_registration = False
        case.update(owner='A', fallbackAttempted=False, injectionAttempted=False, procExits={}, procNotifications=[], registrationEvents=[])

    def created(self, process):
        if not integer(process.pid, 1, MAX_PID) or process.pid == os.getpid():
            raise ValueError('invalid direct Popen PID')
        self.process, self.reserved = process, True
        self.case['privateSessionLeaderPID'] = process.pid

    def register(self, queue, pid, role):
        if not self.reserved or pid in self.registered:
            raise ValueError('invalid proc registration lifecycle')
        request = dict(pid=pid, role=role, succeeded=False, observerMonotonic=time.monotonic(),
            filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD, fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)
        self.case['registrationEvents'].append(request)
        try:
            queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC, flags=select.KQ_EV_ADD,
                fflags=select.KQ_NOTE_EXIT | NOTE_EXITSTATUS)], 0)
        except OSError as error:
            request.update(errno=error.errno, error=str(error), resultMonotonic=time.monotonic())
            raise
        self.registered.add(pid)
        request.update(succeeded=True, resultMonotonic=time.monotonic())

    def fail(self, error):
        self.case['recordProtocolValid'] = False
        if len(self.case['errors']) < 16:
            self.case['errors'].append(type(error).__name__ + ': ' + str(error))
        self.fallback('observer failure')

    def fallback(self, reason):
        if self.case['fallbackAttempted'] or not self.reserved:
            return
        self.case['fallbackAttempted'] = True
        self.case['guardrailUsed'] = True
        request = dict(pid=self.process.pid, signal=signal.SIGKILL, reason=reason,
                       requestMonotonic=time.monotonic(), succeeded=False)
        self.case['fallback'] = request
        try:
            os.killpg(self.process.pid, signal.SIGKILL)
            request['succeeded'] = True
        except OSError as error:
            request['errno'] = error.errno
            request['error'] = str(error)
        request['resultMonotonic'] = time.monotonic()

    def notification(self, event):
        """Status-less exact NOTE_EXIT preserves occurrence, never status success."""
        receipt = time.monotonic()
        if len(self.case['procNotifications']) < 32:
            raw = {key: getattr(event, key, None) for key in ['ident', 'filter', 'flags', 'fflags', 'data']}
            raw = {key: value if type(value) in [int, bool, type(None)] else repr(value)[:128] for key, value in raw.items()}
            self.case['procNotifications'].append(dict(raw, receiptMonotonic=receipt))
        if (not integer(event.ident, 1, MAX_PID) or event.ident not in self.registered or
            type(event.filter) is not int or event.filter != select.KQ_FILTER_PROC or
            not integer(event.flags, 0, 65535) or not integer(event.fflags) or
            not integer(event.data, -(2**63), 2**63-1) or event.flags & (select.KQ_EV_ERROR | 0x40) or
            event.fflags & ~(select.KQ_NOTE_EXIT | NOTE_EXITSTATUS) or
            not event.fflags & select.KQ_NOTE_EXIT):
            raise ValueError('invalid registered proc exit notification')
        role = 'Supervisor' if event.ident == self.process.pid else 'Child'
        previous = self.case['procExits'].get(role)
        status = termination(event.data)
        valid = bool(event.fflags & NOTE_EXITSTATUS) and status['kind'] != 'unknown'
        current = dict(pid=event.ident, filter=event.filter, flags=event.flags, fflags=event.fflags,
            rawWaitStatus=event.data, exitObserved=True, statusValid=valid, receiptMonotonic=receipt)
        if previous:
            if any(previous[k] != current[k] for k in ['pid', 'rawWaitStatus', 'statusValid']):
                raise ValueError('contradictory duplicate exit')
            return
        self.case['procExits'][role] = current
        if not valid:
            raise ValueError('exit status unavailable or invalid')

    def record(self, event):
        if type(event) is not dict:
            raise ValueError('non-object record')
        pid, role = event.get('pid'), event.get('role')
        kind_roles = {'guard': ('Supervisor','Stub'), 'snapshot': self.spec.roles,
            'spawn': ('Supervisor',), 'controls': ('Stub','Worker'), 'ptrace': ('Stub',),
            'execGrant': ('Supervisor',), 'execIntent': ('Stub',), 'execStop': ('Supervisor',),
            'continueIntent': ('Supervisor',), 'continue': ('Supervisor',),
            'heldStop': ('Supervisor',), 'holdFailure': ('Supervisor',),
            'workerProgress': ('Worker',), 'guardInherited': ('Worker',), 'idleReady': ('Worker',),
            'childExit': ('Supervisor',), 'cleanupRequest': ('Supervisor',),
            'signalStop': ('Supervisor',), 'execFailure': ('Stub',)}
        if type(event.get('kind')) is not str or event['kind'] not in kind_roles or role not in kind_roles[event['kind']]:
            raise ValueError('unknown or misplaced native record kind')
        if (not integer(pid, 1, MAX_PID) or type(role) is not str or role not in self.spec.roles or
            type(event.get('nonce')) is not str or event['nonce'] != self.case['nonce'] or
            event.get('phase') != self.case['phase'] or event.get('owner') != 'A' or
            type(event.get('sequence')) is not int or event['sequence'] != self.sequences.get(pid, 0) + 1 or
            not 1 <= event['sequence'] <= 32 or
            event.get('clock') != 'CLOCK_MONOTONIC' or not tracing.native_time(event.get('time')) or
            event['time'] < self.last_times.get(pid, 0) or
            not integer(event.get('pgid'), 1, MAX_PID) or event['pgid'] != self.process.pid or
            not integer(event.get('sid'), 1, MAX_PID) or event['sid'] != self.process.pid):
            raise ValueError('death record identity, group, sequence or clock')
        if role == 'Supervisor':
            if pid != self.process.pid:
                raise ValueError('wrong owned Supervisor')
        elif self.child is not None:
            if pid != self.child:
                raise ValueError('wrong owned child')
        elif self.provisional is None and role == 'Stub' and event.get('kind') == 'guard' and event['sequence'] == 1 and pid not in [self.process.pid, os.getpid()]:
            self.provisional = pid
        else:
            raise ValueError('unexpected provisional child record')
        if event.get('kind') == 'spawn':
            child = event.get('childPID')
            if (role != 'Supervisor' or self.child is not None or type(event.get('result')) is not int or event['result'] != 0 or
                not integer(child, 1, MAX_PID) or child in [self.process.pid, os.getpid()] or
                (self.provisional is not None and self.provisional != child)):
                raise ValueError('invalid unique direct spawn')
            self.child = child
            self.case['childPID'] = child
            self.pending_registration = True
        if event.get('kind') in ['signalStop', 'cleanupRequest', 'holdFailure']:
            self.case['guardrailUsed'] = True
        self.last_times[pid] = event['time']
        self.sequences[pid] = event['sequence']
        self.case['events'].append(event)

    def after_batch(self, queue):
        if not self.case['recordProtocolValid'] or self.case['guardrailUsed'] or self.case['fallbackAttempted']:
            return
        if self.pending_registration:
            # Consume the complete batch before admitting the child; late cleanup or
            # provisional mismatch must not release a stale launch prefix.
            guard = owner.one(self.case, 'guard', 'Supervisor')
            if (self.case['procExits'] or not guard or type(guard.get('seconds')) is not int or guard['seconds'] != 3 or
                not tracing.native_time(guard.get('lowerBound')) or
                time.monotonic() >= self.case['prePopenMonotonic'] + 1.5):
                raise ValueError('stale registration prefix')
            spawn = owner.one(self.case, 'spawn', 'Supervisor')
            snapshot = owner.one(self.case, 'snapshot', 'Supervisor', 'S0')
            if (not spawn or not owner.snapshot_valid(snapshot, self.manifest['products']['Supervisor'], 'Supervisor', self.process.pid) or
                not guard['time'] <= snapshot['time'] <= spawn['time'] < guard['time'] + 1.5 or
                (self.predecessors and not owner.same_fields(snapshot, owner.one(self.predecessors[0], 'snapshot', 'Supervisor', 'S0'))) or
                any(not ((e['role'] == 'Supervisor' and (e['kind'] in ['guard', 'spawn'] or
                    (e['kind'] == 'snapshot' and e.get('stage') == 'S0'))) or
                    (e['role'] == 'Stub' and e['kind'] == 'guard' and e['sequence'] == 1)) for e in self.case['events'])):
                raise ValueError('unaccepted initial ownership hold')
            self.register(queue, self.child, 'Child')
            self.pending_registration = False
            self.process.stdin.write((self.case['nonce'] + ':' + self.case['phase'] + ':registered').encode())
            self.process.stdin.flush()
            self.case['registrationTokenMonotonic'] = time.monotonic()
        if self.case['phase'] not in ['D2', 'D3'] or self.case['injectionAttempted']:
            return
        marker = 'heldStop' if self.case['phase'] == 'D2' else 'idleReady'
        if not any(e.get('kind') == marker for e in self.case['events']):
            return
        if (self.case['procExits'] or not prefix_valid(self.case, self.predecessors, self.manifest, gate=True) or
            time.monotonic() >= self.case['prePopenMonotonic'] + 1.5):
            raise ValueError('invalid or expired death injection prefix')
        if not self.reserved or self.child not in self.registered:
            raise ValueError('missing unreaped ownership reservation')
        self.case['injectionAttempted'] = True
        injection = dict(pid=self.process.pid, signal=signal.SIGKILL, requestMonotonic=time.monotonic(), succeeded=False)
        self.case['injection'] = injection
        try:
            os.kill(self.process.pid, signal.SIGKILL)
            injection['succeeded'] = True
        except OSError as error:
            injection.update(errno=error.errno, error=str(error))
            raise
        finally:
            injection['resultMonotonic'] = time.monotonic()

    def exits_observed(self):
        return all(self.case['procExits'].get(role, {}).get('exitObserved') is True for role in ['Supervisor', 'Child'])

    def finish_reservation(self, eof):
        # The shared loop has ended: either all exact exits arrived or its original
        # observation interval/queue ended. The single fallback precedes any reap.
        if not self.exits_observed() or not eof:
            self.fallback('incomplete final observation')
        self.reserved = False
        self.case['reservationReleasedMonotonic'] = time.monotonic()


def launch_spec(products, manifest, phase, cases, listener, foreign):
    prior = cases[0] if cases else None
    baseline = lambda role, stage: owner.baseline(owner.one(prior, 'snapshot', role, stage)) if prior else '-'
    table = manifest['products']
    return tracing.DeathRecordSpec(arguments=(table['Supervisor']['path'], phase, '', table['A.Stub']['path'],
        str(foreign), str(listener.getsockname()[1]), table['A.Worker']['path'],
        baseline('Supervisor', 'S0'), baseline('Stub', 'S0'), baseline('Worker', 'S4')),
        manifest_json=json.dumps(manifest, sort_keys=True), predecessors_json=json.dumps(cases, sort_keys=True))


def drive_cases(products, manifest, listener, foreign, artifact_hash, *, cases=None):
    cases = [] if cases is None else cases
    if cases:
        raise ValueError('fresh finite sequence required')
    for phase in PHASES:
        if not manifest_valid(manifest, products):
            cases.append(dict(phase=phase, events=[], processCreated=False, cleanupObserved=False,
                assessment=dict(accepted=False, result='unknown', regressions=[], refusals=[],
                    unavailableEvidence=['same-build bytes changed before launch'])))
            break
        case = tracing.run_case(products, phase, 'Stub', listener, foreign, artifact_hash,
            death_spec=launch_spec(products, manifest, phase, cases, listener, foreign))
        predecessors = list(cases)
        cases.append(case)
        if not manifest_valid(manifest, products):
            case['recordProtocolValid'] = False
            case['errors'].append('same-build bytes changed during observation')
        try:
            case['assessment'] = assess_case(case, predecessors, manifest, artifact_hash)
        except Exception as error:
            regressions, refusals = adverse(case)
            case['assessment'] = dict(accepted=False, result='weakened' if regressions else 'rejected' if refusals else 'unknown',
                regressions=regressions, refusals=refusals,
                unavailableEvidence=['assessment error: ' + type(error).__name__ + ': ' + str(error)])
        if not case['assessment']['accepted']:
            break
    return cases


def empty_report():
    return dict(schema='managed-death-observation-v1', characterization='fixed-development-managed-death',
        complete=False, result='unknown', nativeLauncherAdmitted=False, productionTemplateVerifierQualified=False,
        hostDeathQualified=False, startupRaceQualified=False, allVMProtectionsPreserved='unknown',
        stoppedWorkerDeathObserved=False, runningWorkerDeathObserved=False, cases=[],
        observerExecutable=sys.executable, maximumNativeParticipants=8, maximumConcurrentNativeParticipants=2,
        externalDeadlineSeconds=5, explicitRecordAllocationLimitBytes=262144, totalRawLogLimitBytes=1048576,
        specimenPayloadBytesMaximum=64, diagnosticResidue=[], OSContainerMetadataAllocation='unmeasured',
        causalLimit='Fixed code and no external intervention assumed; signal status does not identify its sender; no atomic liveness proof.',
        cleanupLimit='Owned-group request is safe only for this fixed unchanged private session; missing exit evidence remains unknown.',
        omittedOwnerOperations='No specimen creation, cross-owner operation or container traversal; Foundation and Objective-C linkage retained.')


def main():
    products = Path(sys.argv[1]).resolve(strict=True)
    report = empty_report()
    foreign = directory = None
    foreign_created = directory_created = False
    try:
        manifest = json.loads((products / 'manifest.json').read_text())
        report['build'] = manifest
        if not manifest_valid(manifest, products):
            raise ValueError('static death fixture manifest rejected')
        artifacts = {key: manifest['products'][key]['hash'] for key in PRODUCTS}
        report['artifacts'] = artifacts
        fingerprint = hashlib.sha256(json.dumps(artifacts, sort_keys=True).encode()).hexdigest()
        directory = Path(manifest['userHome']) / 'Library/Application Support' / ('CascadeDeath-' + manifest['runID'])
        directory.mkdir(mode=0o700)
        directory_created = True
        foreign = directory / 'control'
        fd = os.open(foreign, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC, 0o600)
        foreign_created = True
        try:
            if os.write(fd, b'C0d-control'.ljust(64, b'.')) != 64:
                raise OSError('short synthetic control write')
        finally:
            os.close(fd)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(4)
            listener.settimeout(.2)
            drive_cases(products, manifest, listener, foreign, fingerprint, cases=report['cases'])
        report['complete'] = len(report['cases']) == 4 and all(c['assessment']['accepted'] for c in report['cases'])
        report['stoppedWorkerDeathObserved'] = len(report['cases']) >= 3 and report['cases'][2]['assessment']['accepted']
        report['runningWorkerDeathObserved'] = report['complete']
        if report['complete']:
            report['result'] = 'fixedManagedDeathObserved'
        elif any(c['assessment']['regressions'] for c in report['cases']):
            report['result'] = 'weakened'
        elif any(c['assessment']['refusals'] for c in report['cases']):
            report['result'] = 'rejected'
    except Exception as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
    finally:
        # Only the exclusive run-owned control is removed, never an OS container.
        if foreign_created:
            try:
                foreign.unlink()
            except OSError as error:
                report['diagnosticResidue'].append(dict(path=str(foreign), error=str(error)))
        if directory_created:
            try:
                directory.rmdir()
            except OSError as error:
                report['diagnosticResidue'].append(dict(path=str(directory), error=str(error)))
        path = products / 'death-report.json'
        path.write_text(json.dumps(report, indent=2) + '\n')
        print(path)
        print(report['result'])
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    sys.exit(main())
