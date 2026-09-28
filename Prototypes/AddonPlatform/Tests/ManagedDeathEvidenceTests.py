"""Offline death diagnostic tests script OS endpoints around the real observer/driver."""
import contextlib
import copy
import hashlib
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
import run as tracing
import death_run as death
spec = importlib.util.spec_from_file_location('owner_test_fixtures', Path(__file__).with_name('OwnerBootstrapEvidenceTests.py'))
owner_fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(owner_fixtures)


def manifest_at(products):
    manifest = owner_fixtures.manifest_at(products)
    manifest.update(schema='managed-death-build-v1', prefix='hylo.Cascade.DeathFixture.' + 'a'*32)
    manifest['products'] = {k: manifest['products'][k] for k in death.PRODUCTS}
    for key, item in manifest['products'].items():
        item.update(identity=manifest['prefix'] + '.' + key, infoIdentifier=manifest['prefix'] + '.' + key,
            path=str(products / ('Death' + key.replace('.', ''))), signerLeafSHA1='4A857D842A5406C2D3071776FDE7B27B3098FE63')
        Path(item['path']).write_bytes(key.encode())
    return manifest


def native_records(manifest, phase, supervisor, child):
    records = owner_fixtures.native_records(manifest, 'O1' if phase == 'D0' else 'O4', supervisor, child)
    records = [e for e in records if e['kind'] not in ['storageOwn', 'storageCross']]
    if phase == 'D2':
        index = next(i for i, e in enumerate(records) if e.get('stage') == 'S3')
        records = records[:index+1] + [dict(kind='heldStop', role='Supervisor', childPID=child, terminal=True)]
    if phase == 'D3':
        records = records[:-1] + [dict(kind='idleReady', role='Worker', terminal=True)]
    for index, event in enumerate(records):
        event.update(clock='CLOCK_MONOTONIC', time=100+index*.01, owner='A', pgid=supervisor, sid=supervisor)
        if event['kind'] == 'continue':
            event['requestTime'] = event['time']
    return records


def observe(*, mutation=None, scenario=None, target='D2', child_status=None, reverse=False):
    """Run the real finite dispatcher, record parser, injection, cleanup and reducer."""
    state = dict(clock=1000.0, calls=[], lifecycle=[], cases=[], raw=[], queuedRaw=[], queueReads=0)
    active = {}
    with tempfile.TemporaryDirectory(prefix='cascade-death-offline-') as directory, contextlib.ExitStack() as stack:
        products = Path(directory).resolve()
        manifest = manifest_at(products)
        foreign = products / 'control'
        foreign.write_bytes(b'x')
        listener = MagicMock()
        listener.getsockname.return_value = ('127.0.0.1', 1234)
        listener.accept.return_value = (MagicMock(), None)
        stack.enter_context(patch.object(tracing.socket, 'create_connection', return_value=MagicMock()))
        def now():
            state['clock'] += .001
            return state['clock']
        stack.enter_context(patch.object(tracing.time, 'monotonic', side_effect=now))
        def popen(arguments, **kwargs):
            index = len(state['calls'])
            if index >= 4:
                raise AssertionError('fifth native dispatch')
            phase = arguments[1]
            state['calls'].append(dict(arguments=arguments, options=kwargs))
            state['lifecycle'].append((phase, 'Popen'))
            if scenario == 'popen-failure' and phase == target:
                raise OSError('private session setup failed')
            pid, child = 110+index, 210+index
            records = native_records(manifest, phase, pid, child)
            seq = {}
            for e in records:
                ep = pid if e['role'] == 'Supervisor' else child
                seq[ep] = seq.get(ep, 0)+1
                e.update(pid=ep, sequence=seq[ep], nonce=arguments[2], phase=phase)
            if mutation:
                mutation(phase, records)
            if scenario == 'lost-spawn' and phase == target:
                records = [e for e in records if e['kind'] != 'spawn']
            stream = tempfile.TemporaryFile()
            # Split the launch hold from all later records: no native S0 before token.
            first = [e for e in records if e['kind'] == 'spawn' or (e['role'] == 'Supervisor' and e.get('stage') == 'S0') or (e['role'] == 'Supervisor' and e['kind'] == 'guard')]
            rest = [e for e in records if e not in first]
            if scenario in ['provisional-guard', 'provisional-wrong', 'premature-child'] and phase == target:
                guard = next(e for e in rest if e['role']=='Stub' and e['kind']=='guard')
                rest.remove(guard)
                first.insert(2, guard)
                if scenario == 'provisional-wrong': guard['pid'] += 10
                if scenario == 'premature-child':
                    snapshot = next(e for e in rest if e['role']=='Stub' and e.get('stage')=='S0')
                    rest.remove(snapshot)
                    first.append(snapshot)
            def encode(rows):
                return b''.join(json.dumps(e).encode()+b'\n' for e in rows)
            prefix, suffix = encode(first), encode(rest)
            if scenario == 'malformed-after-gate' and phase == target:
                suffix += b'{invalid}\n'
            if scenario == 'oversized-raw' and phase == target:
                suffix += b'x' * 270000
            if scenario == 'partial-after-gate' and phase == target:
                suffix += b'{partial'
            if scenario == 'missing-gate-eof' and phase == target:
                suffix = encode([e for e in rest if e['kind'] not in ['heldStop','idleReady']])
            state['queuedRaw'].append(prefix+suffix)
            stream.write(prefix+suffix)
            size = stream.tell()
            stream.seek(0)
            active.clear()
            active.update(phase=phase, pid=pid, child=child, stream=stream, prefixSize=len(prefix), size=size,
                token=False, procRegistered=set(), exitsSent=False, injected=False, fallback=False, eof=False, reads=0)
            class Input(io.BytesIO):
                def write(self, content):
                    state['lifecycle'].append((phase, 'token'))
                    if child not in active['procRegistered']:
                        raise AssertionError('start token before child registration')
                    active['token'] = True
                    return super().write(content)
            def forbidden(*args, **kwargs):
                raise AssertionError('early Popen poll/signal helper')
            def wait(timeout):
                state['lifecycle'].append((phase, 'wait'))
                if not active['fallback'] and not (active['exitsSent'] and active['eof']):
                    raise AssertionError('reap before cleanup authority closed')
                if scenario == 'late-wait' and phase == target:
                    state['clock'] += 2
                if scenario == 'wait-timeout' and phase == target:
                    raise subprocess.TimeoutExpired('offline', timeout)
                return -9 if phase in ['D2', 'D3'] or active['fallback'] else 0
            return SimpleNamespace(pid=pid, stdin=Input(), stdout=stream, wait=wait,
                poll=forbidden, kill=forbidden, terminate=forbidden, send_signal=forbidden, communicate=forbidden)
        stack.enter_context(patch.object(tracing.subprocess, 'Popen', side_effect=popen))
        def kill(pid, sig):
            state['lifecycle'].append((active['phase'], 'kill'))
            if pid != active['pid'] or sig != signal.SIGKILL or active['injected']:
                raise AssertionError('not one exact direct-child injection')
            active['injected'] = True
        def killpg(pid, sig):
            state['lifecycle'].append((active['phase'], 'killpg'))
            if pid != active['pid'] or sig != signal.SIGKILL or active['fallback']:
                raise AssertionError('not one exact reserved-group fallback')
            active['fallback'] = True
            if scenario in ['killpg-failure','queue-after-injection-killpg-failure'] and active['phase'] == target:
                raise PermissionError(1, 'group signal refused')
        stack.enter_context(patch.object(tracing.os, 'kill', side_effect=kill))
        stack.enter_context(patch.object(tracing.os, 'killpg', side_effect=killpg))
        constants = dict(KQ_FILTER_READ=-1, KQ_FILTER_PROC=-5, KQ_EV_ADD=1, KQ_EV_DELETE=2,
            KQ_NOTE_EXIT=0x80000000, KQ_EV_ERROR=0x4000, KQ_EV_EOF=0x8000, KQ_EV_ONESHOT=0x10)
        for key, value in constants.items():
            stack.enter_context(patch.object(tracing.select, key, value, create=True))
        def kevent(ident, **fields):
            return SimpleNamespace(ident=ident, flags=fields.pop('flags', 0), fflags=fields.pop('fflags', 0), data=fields.pop('data', 0), **fields)
        stack.enter_context(patch.object(tracing.select, 'kevent', side_effect=kevent, create=True))
        def proc(pid, raw):
            return kevent(pid, filter=-5, flags=0x8010, fflags=0x84000000, data=raw)
        class Queue:
            def control(self, changes, count, timeout=None):
                if changes is not None:
                    for e in changes:
                        if e.filter == -5:
                            state['lifecycle'].append((active['phase'], 'register', e.ident, e.fflags))
                            if scenario == 'registration-failure' and active['phase'] == target:
                                raise PermissionError('proc registration refused')
                            active['procRegistered'].add(e.ident)
                    return []
                state['queueReads'] += 1
                active['reads'] += 1
                state['clock'] += .005
                phase = active['phase']
                if scenario in ['queue-after-injection','queue-after-injection-killpg-failure'] and phase == target and active['injected']:
                    raise OSError('queue failed after injection')
                if active['stream'].tell() < active['size']:
                    events = [kevent(active['stream'].fileno(), filter=-1)]
                    if scenario == 'exit-after-gate-batch' and phase == target and active['size']-active['stream'].tell() <= 4096 and active['child'] in active['procRegistered']:
                        events.append(proc(active['child'], 9))
                    return events
                if not active['exitsSent']:
                    active['exitsSent'] = True
                    raw = 9 if phase in ['D2', 'D3'] or active['fallback'] else 0
                    child_raw = child_status if child_status is not None and phase == target else raw
                    child_event = proc(active['child'], child_raw)
                    if phase == target:
                        if scenario == 'status-less': child_event.fflags = 0x80000000
                        if scenario == 'ev-error': child_event.flags |= 0x4000
                        if scenario == 'bool-status': child_event.data = True
                        if scenario == 'negative-status': child_event.data = -9
                        if scenario == 'large-status': child_event.data = 65536
                        if scenario == 'bool-ident': child_event.ident = True
                        if scenario == 'bool-flags': child_event.flags = True
                        if scenario == 'bool-fflags': child_event.fflags = True
                        if scenario == 'wrong-filter': child_event.filter = True
                        if scenario == 'late-exit': state['clock'] += 2
                        if scenario == 'receipt': child_event.flags |= 0x40
                        if scenario == 'extra-fflags': child_event.fflags |= 1
                    events = [proc(active['pid'], raw), child_event]
                    if reverse: events.reverse()
                    if scenario == 'missing-child-exit' and phase == target:
                        events = [events[0]]
                    if scenario == 'contradictory-exit' and phase == target:
                        events.append(proc(active['child'], 0 if child_raw != 0 else 9))
                    events.append(kevent(active['stream'].fileno(), filter=-1, flags=0x8000))
                    return events
                state['clock'] += .5
                return []
            def close(self):
                pass
        stack.enter_context(patch.object(tracing.select, 'kqueue', side_effect=Queue, create=True))
        real_read = tracing.os.read
        def read(fd, count):
            if fd == active.get('stream', SimpleNamespace(fileno=lambda: -1)).fileno():
                position = active['stream'].tell()
                if position < active['prefixSize']:
                    count = min(count, active['prefixSize']-position)
                data = real_read(fd, count)
                if not data: active['eof'] = True
                return data
            return real_read(fd, count)
        stack.enter_context(patch.object(tracing.os, 'read', side_effect=read))
        fingerprint = hashlib.sha256(json.dumps({k: manifest['products'][k]['hash'] for k in death.PRODUCTS}, sort_keys=True).encode()).hexdigest()
        cases = death.drive_cases(products, manifest, listener, foreign, fingerprint)
        state['cases'] = cases
        state['raw'] = [Path(c['rawLog']).read_bytes() for c in cases]
        state['manifest'] = manifest
        return state


class DeathObserverTests(unittest.TestCase):
    def test_all_four_cases_same_bytes_private_session_status_crosschecks(self):
        result = observe()
        self.assertEqual(len(result['calls']), 4, result['cases'])
        self.assertTrue(all(c['assessment']['accepted'] for c in result['cases']), result['cases'])
        self.assertTrue(all(call['options']['start_new_session'] for call in result['calls']))
        self.assertEqual([step for step in result['lifecycle'] if step[1]=='kill'], [('D2','kill'), ('D3','kill')])
        self.assertFalse(any(step[1]=='killpg' for step in result['lifecycle']))
        self.assertTrue(all(c['childWaitObserved'] for c in result['cases'][:2]))
        self.assertTrue(all(not c['childWaitObserved'] for c in result['cases'][2:]))
        self.assertTrue(all(step[3] == 0x84000000 for step in result['lifecycle'] if step[1]=='register'))

    def test_both_proc_status_orders(self):
        self.assertTrue(all(c['assessment']['accepted'] for c in observe(reverse=True)['cases']))

    def test_registration_failure_group_fallback_precedes_wait(self):
        result = observe(scenario='registration-failure', target='D0')
        steps = [e[1] for e in result['lifecycle']]
        self.assertEqual(steps.count('killpg'), 1)
        self.assertLess(steps.index('killpg'), steps.index('wait'))
        self.assertNotIn('token', steps)
        self.assertFalse(result['cases'][0]['cleanupObserved'])
        self.assertEqual(len(result['calls']), 1)

    def test_popen_private_session_setup_failure_creates_no_cleanup_target(self):
        result = observe(scenario='popen-failure', target='D0')
        case = result['cases'][0]
        self.assertFalse(case['processCreated'])
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(any(e[1] in ['kill', 'killpg', 'wait'] for e in result['lifecycle']))

    def test_lost_spawn_never_rediscovered(self):
        result = observe(scenario='lost-spawn', target='D0')
        self.assertFalse(result['cases'][0]['assessment']['accepted'])
        self.assertFalse(any(e[1]=='token' for e in result['lifecycle']))
        self.assertEqual(sum(e[1]=='killpg' for e in result['lifecycle']), 1)

    def test_same_batch_late_child_exit_prevents_injection(self):
        result = observe(scenario='exit-after-gate-batch')
        case = result['cases'][-1]
        self.assertEqual(case['phase'], 'D2')
        self.assertFalse(case['injectionAttempted'])
        self.assertFalse(case['assessment']['accepted'])

    def test_same_read_malformed_after_gate_prevents_injection_and_drains_exits(self):
        result = observe(scenario='malformed-after-gate')
        case = result['cases'][-1]
        self.assertFalse(case['injectionAttempted'])
        self.assertTrue(case['fallbackAttempted'])
        self.assertTrue(case['cleanupObserved'])
        self.assertIn(b'{invalid}', result['raw'][-1])

    def test_queue_failure_after_injection_falls_back_and_keeps_child_unknown(self):
        case = observe(scenario='queue-after-injection')['cases'][-1]
        self.assertTrue(case['injectionAttempted'])
        self.assertTrue(case['fallbackAttempted'])
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(case['assessment']['accepted'])

    def test_statusless_exact_exit_retains_occurrence_without_status(self):
        case = observe(scenario='status-less')['cases'][-1]
        self.assertTrue(case['procExits']['Child']['exitObserved'])
        self.assertFalse(case['procExits']['Child']['statusValid'])
        self.assertTrue(case['cleanupObserved'])
        self.assertFalse(case['assessment']['accepted'])

    def test_bad_proc_types_statuses_and_error_receipts_fail_closed(self):
        for scenario in ['ev-error','bool-status','negative-status','large-status','bool-ident','bool-flags','bool-fflags','wrong-filter']:
            with self.subTest(scenario=scenario):
                case = observe(scenario=scenario)['cases'][-1]
                self.assertEqual(case['phase'], 'D2')
                self.assertFalse(case['assessment']['accepted'])

    def test_normal_alarm_and_stop_are_not_injected_death(self):
        for status in [0, signal.SIGALRM, 1407]:
            with self.subTest(status=status):
                self.assertFalse(observe(child_status=status)['cases'][-1]['assessment']['accepted'])

    def test_alarm_exclusion_covers_exit_and_final_direct_wait(self):
        for scenario in ['late-exit','late-wait','wait-timeout']:
            with self.subTest(scenario=scenario):
                self.assertFalse(observe(scenario=scenario)['cases'][-1]['assessment']['accepted'])

    def test_baseline_event_and_native_wait_status_must_agree(self):
        case = observe(child_status=256, target='D0')['cases'][0]
        self.assertFalse(case['assessment']['childStatusAgreesWithNativeWait'])
        self.assertEqual(case['phase'], 'D0')

    def test_stale_boolean_and_duplicate_spawn_fail_before_token(self):
        for replacement in [True, -1, 2**31, 999]:
            def mutate(phase, records):
                if phase != 'D0': return
                spawn = next(e for e in records if e['kind']=='spawn')
                spawn['childPID'] = replacement
                # Put the real provisional guard in the same read before spawn.
                guard = next(e for e in records if e['kind']=='guard' and e['role']=='Stub')
                if replacement == 999:
                    spawn['result'] = True
            with self.subTest(replacement=replacement):
                result=observe(mutation=mutate)
                self.assertFalse(result['cases'][0]['assessment']['accepted'])
                self.assertFalse(any(e[1]=='token' for e in result['lifecycle']))

    def test_gate_requires_unique_stop_identity_continue_and_controls(self):
        mutations = [('D2','snapshot','S3','hash','f'*40), ('D2','heldStop',None,'terminal',False),
            ('D3','controls',None,'fileDenied',False), ('D3','continue',None,'result',-1),
            ('D3','idleReady',None,'terminal',False)]
        for target,kind,stage,key,value in mutations:
            def mutate(phase, records):
                if phase == target:
                    e = next(e for e in records if e['kind']==kind and (stage is None or e.get('stage')==stage) and (kind!='controls' or e['role']=='Worker'))
                    e[key]=value
            with self.subTest(kind=kind, target=target):
                case=observe(mutation=mutate)['cases'][-1]
                self.assertEqual(case['phase'],target)
                self.assertFalse(case['injectionAttempted'])

    def test_record_types_and_group_binding(self):
        for key,value in [('pid',True),('sequence',True),('nonce',[]),('role',[]),('pgid',True),('sid',999),('time',float('nan'))]:
            def mutate(phase, records):
                if phase=='D2': next(e for e in records if e['kind']=='heldStop')[key]=value
            with self.subTest(key=key):
                self.assertFalse(observe(mutation=mutate)['cases'][-1]['assessment']['accepted'])

    def test_guard_cleanup_and_hold_failure_contaminate_injection(self):
        for kind in ['cleanupRequest','signalStop','holdFailure']:
            def mutate(phase, records):
                if phase=='D2':
                    hold=next(e for e in records if e['kind']=='heldStop')
                    extra=dict(hold,kind=kind,sequence=hold['sequence']+1,time=hold['time']+.01)
                    records.append(extra)
            with self.subTest(kind=kind):
                case=observe(mutation=mutate)['cases'][-1]
                self.assertFalse(case['injectionAttempted'])
                self.assertFalse(case['assessment']['accepted'])

    def test_adverse_security_survives_malformed_source_and_later_parser_error(self):
        for source in [[],{}]:
            def mutate(phase,records):
                if phase=='D2':
                    snap=next(e for e in records if e.get('stage')=='S3')
                    snap.update(source=source,valid=False)
            with self.subTest(source=source):
                case=observe(mutation=mutate,scenario='malformed-after-gate')['cases'][-1]
                self.assertTrue(case['assessment']['regressions'])
                self.assertEqual(case['assessment']['result'],'weakened')

    def test_group_signal_failure_preserves_unknown_not_fake_cleanup(self):
        def mutate(phase, records):
            if phase=='D2': next(e for e in records if e['kind']=='heldStop')['terminal']=False
        result=observe(mutation=mutate,scenario='killpg-failure')
        case=result['cases'][-1]
        self.assertTrue(case['fallbackAttempted'])
        self.assertFalse(case['fallback']['succeeded'])
        self.assertFalse(case['assessment']['accepted'])

    def test_provisional_guard_is_bound_before_registration(self):
        result=observe(scenario='provisional-guard',target='D0')
        self.assertEqual(len(result['calls']),4)
        self.assertTrue(all(c['assessment']['accepted'] for c in result['cases']))
        for scenario in ['provisional-wrong','premature-child']:
            with self.subTest(scenario=scenario):
                result=observe(scenario=scenario,target='D0')
                self.assertFalse(any(e[1]=='token' for e in result['lifecycle']))
                self.assertEqual(len(result['calls']),1)

    def test_missing_child_exit_keeps_registration_alive_until_one_fallback(self):
        result=observe(scenario='missing-child-exit')
        case=result['cases'][-1]
        self.assertFalse(case['cleanupObserved'])
        self.assertTrue(case['fallbackAttempted'])
        self.assertFalse(case['assessment']['accepted'])
        steps=[e[1] for e in result['lifecycle'] if e[0]=='D2']
        self.assertEqual(steps.count('killpg'),1)
        self.assertLess(steps.index('killpg'),steps.index('wait'))

    def test_receipt_unrequested_bits_and_contradictory_duplicate_are_not_success(self):
        for scenario in ['receipt','extra-fflags','contradictory-exit']:
            with self.subTest(scenario=scenario):
                self.assertFalse(observe(scenario=scenario)['cases'][-1]['assessment']['accepted'])

    def test_partial_and_missing_gate_eof_never_inject_or_continue(self):
        for scenario in ['partial-after-gate','missing-gate-eof']:
            with self.subTest(scenario=scenario):
                case=observe(scenario=scenario)['cases'][-1]
                self.assertFalse(case['injectionAttempted'])
                self.assertFalse(any(e['kind'] in ['continueIntent','continue'] for e in case['events']))
                self.assertFalse(case['assessment']['accepted'])

    def test_raw_output_is_bounded_and_preserved_on_failure(self):
        result=observe(scenario='oversized-raw')
        self.assertEqual(len(result['raw'][-1]),262144)
        self.assertFalse(result['cases'][-1]['assessment']['accepted'])

    def test_missing_or_duplicate_milestones_prevent_successor(self):
        for target,kind,stage in [('D1','snapshot','S3'),('D1','continue',None),('D2','heldStop',None),('D3','idleReady',None)]:
            for duplicate in [False,True]:
                def mutate(phase,records):
                    if phase!=target:return
                    found=next(e for e in records if e['kind']==kind and (stage is None or e.get('stage')==stage))
                    if duplicate:
                        index=records.index(found)
                        records.insert(index+1,dict(found))
                    else:
                        records.remove(found)
                    sequences={}
                    for e in records:
                        sequences[e['pid']]=sequences.get(e['pid'],0)+1
                        e['sequence']=sequences[e['pid']]
                with self.subTest(target=target,kind=kind,duplicate=duplicate):
                    case=observe(mutation=mutate)['cases'][-1]
                    self.assertEqual(case['phase'],target)
                    self.assertFalse(case['assessment']['accepted'])

    def test_d2_rejects_any_continue_or_worker_record(self):
        for kind,role in [('continueIntent','Supervisor'),('workerProgress','Worker')]:
            def mutate(phase,records):
                if phase!='D2':return
                hold=next(e for e in records if e['kind']=='heldStop')
                pid=hold['pid'] if role=='Supervisor' else hold['childPID']
                sequence=max(e['sequence'] for e in records if e['pid']==pid)+1
                records.append(dict(hold,kind=kind,role=role,pid=pid,sequence=sequence,time=hold['time']+.01))
            with self.subTest(kind=kind):
                case=observe(mutation=mutate)['cases'][-1]
                self.assertFalse(case['injectionAttempted'])

    def test_d3_idle_cannot_precede_controls(self):
        def mutate(phase,records):
            if phase=='D3':
                idle=next(e for e in records if e['kind']=='idleReady')
                controls=next(e for e in records if e['kind']=='controls' and e['role']=='Worker')
                idle['time']=controls['time']-.01
        self.assertFalse(observe(mutation=mutate)['cases'][-1]['injectionAttempted'])

    def test_no_reentry_or_fifth_dispatch_on_existing_sequence(self):
        with self.assertRaises(ValueError):
            death.drive_cases(None,None,None,None,None,cases=[{}])

    def test_frozen_spec_contains_no_mutable_policy_members(self):
        specification=tracing.DeathRecordSpec(('fixed',), '{}', '[]')
        with self.assertRaises(__import__('dataclasses').FrozenInstanceError):
            specification.owner='B'
        self.assertIsInstance(specification.manifest_json,str)
        self.assertIsInstance(specification.predecessors_json,str)

    def test_failed_group_signal_with_broken_queue_retains_unknown_child_cleanup(self):
        result=observe(scenario='queue-after-injection-killpg-failure')
        case=result['cases'][-1]
        self.assertTrue(case['fallbackAttempted'])
        self.assertFalse(case['fallback']['succeeded'])
        self.assertFalse(case['cleanupObserved'])
        self.assertFalse(case['assessment']['accepted'])
        steps=[e[1] for e in result['lifecycle'] if e[0]=='D2']
        self.assertEqual(steps.count('killpg'),1)
        self.assertLess(steps.index('killpg'),steps.index('wait'))
        self.assertNotIn('killpg',steps[steps.index('wait')+1:])

    def test_static_manifest_rejects_changed_bytes_or_weakened_profile_before_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            products=Path(directory)
            manifest=manifest_at(products)
            self.assertTrue(death.manifest_valid(manifest,products))
            manifest['products']['A.Worker']['entitlements']['com.apple.security.inherit']=1
            self.assertFalse(death.manifest_valid(manifest,products))
            manifest['products']['A.Worker']['entitlements']['com.apple.security.inherit']=True
            Path(manifest['products']['A.Worker']['path']).write_bytes(b'changed')
            cases=death.drive_cases(products,manifest,None,None,'a'*64)
            self.assertEqual(len(cases),1)
            self.assertFalse(cases[0]['processCreated'])
            self.assertFalse(cases[0]['assessment']['accepted'])

    def test_setup_failure_writes_unconditional_unknown_report(self):
        with tempfile.TemporaryDirectory() as directory, contextlib.redirect_stdout(io.StringIO()), patch.object(sys,'argv',['death_run.py',directory]):
            self.assertEqual(death.main(),1)
            report=json.loads((Path(directory)/'death-report.json').read_text())
            self.assertEqual(report['result'],'unknown')
            self.assertEqual(report['cases'],[])
            self.assertFalse(report['nativeLauncherAdmitted'])

    def test_initial_proc_refusal_preserves_available_raw_and_adverse_evidence(self):
        def mutate(phase, records):
            if phase == 'D0':
                snapshot = next(e for e in records if e['role'] == 'Supervisor' and e.get('stage') == 'S0')
                snapshot['valid'] = False
                # The child is still held. Only already available startup records
                # belong to this refused-registration scenario.
                records[:] = [e for e in records if e['role'] == 'Supervisor' and
                    (e['kind'] in ['guard', 'spawn'] or e.get('stage') == 'S0')]
        result = observe(mutation=mutate, scenario='registration-failure', target='D0')
        case = result['cases'][0]
        self.assertEqual(result['raw'][0], result['queuedRaw'][0])
        self.assertTrue(result['raw'][0])
        self.assertTrue(case['stdoutEOFObserved'])
        self.assertTrue(case['assessment']['regressions'])
        self.assertEqual(case['assessment']['result'], 'weakened')
        self.assertFalse(case['cleanupObserved'])
        self.assertEqual(len(result['calls']), 1)
        steps = [e[1] for e in result['lifecycle']]
        self.assertEqual(steps.count('register'), 1)
        self.assertEqual(steps.count('killpg'), 1)
        self.assertLess(steps.index('killpg'), steps.index('wait'))
        self.assertNotIn('token', steps)
        self.assertFalse(case['injectionAttempted'])

    def test_native_driver_unconditionally_refuses_before_any_setup(self):
        script = TRACING.parents[2] / 'scripts/test-addon-managed-death.sh'
        with tempfile.TemporaryDirectory(prefix='cascade-death-hold-test-') as directory:
            directory = Path(directory)
            marker = directory / 'mktemp-was-called'
            stub = directory / 'mktemp'
            # This is the only executable on PATH. The old driver may reach this
            # harmless stub, which records the attempt and exits before setup.
            stub.write_text('#!/bin/zsh\nprint -r -- attempted > "' + str(marker) + '"\nexit 79\n')
            stub.chmod(0o700)
            result = subprocess.run(['/bin/zsh', str(script)], env={'PATH': str(directory)},
                capture_output=True, text=True, timeout=2)
            self.assertEqual(result.returncode, 78, result.stdout + result.stderr)
            self.assertFalse(marker.exists())
            self.assertIn('pre-trace', result.stderr)

    def test_no_production_qualification_fields(self):
        report=death.empty_report()
        self.assertTrue(all(report[k] is False for k in ['nativeLauncherAdmitted','productionTemplateVerifierQualified','hostDeathQualified','startupRaceQualified']))
        self.assertEqual(report['allVMProtectionsPreserved'],'unknown')


if __name__ == '__main__':
    unittest.main()
