#
# owner_run.py
# Cascade
#
"""Finite fixed-code owner inheritance diagnostic; never a native launch authority."""
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sys
import run as tracing

PHASES = ('O1', 'O2', 'O3', 'O4')
PRODUCTS = ('Supervisor', 'A.Stub', 'A.Worker', 'B.Stub', 'B.Worker')
FIELDS = ('status', 'flags', 'runtime', 'identity', 'hash', 'team', 'entitlements',
          'valid', 'hard', 'kill', 'debugged', 'platform')


def exact_profile(key):
    """exact_profile isolates the inherited fixture from the historical sandbox-only gate."""
    if key == 'Supervisor':
        return {}
    result = {'com.apple.security.app-sandbox': True}
    if key.endswith('Worker'):
        result['com.apple.security.inherit'] = True
    return result


def manifest_valid(manifest, products):
    """manifest_valid pins generated fixture bytes and exact typed role dictionaries."""
    try:
        run_id = manifest['runID']
        if (manifest['schema'] != 'owner-bootstrap-build-v1' or
            not re.fullmatch('[0-9a-f]{32}', run_id) or
            manifest['prefix'] != 'hylo.Cascade.OwnerFixture.' + run_id or
            set(manifest['products']) != set(PRODUCTS) or
            not re.fullmatch('[A-Z0-9]+', manifest['team'])):
            return False
        for key in PRODUCTS:
            item = manifest['products'][key]
            expected = exact_profile(key)
            if (item['identity'] != manifest['prefix'] + '.' + key or
                item['infoIdentifier'] != item['identity'] or item['team'] != manifest['team'] or
                item['entitlements'] != expected or
                any(type(value) is not bool or value is not True for value in item['entitlements'].values()) or
                type(item['flags']) is not int or item['flags'] != 65536 or
                type(item['runtime']) is not int or item['runtime'] <= 0 or
                item['strictVerified'] is not True or
                not re.fullmatch('[0-9a-f]{40,128}', item['cdhash']) or
                item['path'] != str(products / ('Owner' + key.replace('.', ''))) or
                hashlib.sha256(Path(item['path']).read_bytes()).hexdigest() != item['hash']):
                return False
        return True
    except (KeyError, TypeError, ValueError, OSError):
        return False


def one(case, kind, role, stage=None):
    """one rejects duplicate protocol milestones instead of selecting the first."""
    found = [event for event in case['events'] if event.get('kind') == kind and
             event.get('role') == role and (stage is None or event.get('stage') == stage)]
    return found[0] if len(found) == 1 else None


def same_fields(left, right):
    return all(tracing.snapshot_field_valid(left, key) and left[key] == right.get(key) for key in FIELDS)


def snapshot_valid(event, product, role, pid, guest=False):
    """snapshot_valid binds actual public observations to this run's exact signed role."""
    if not event:
        return False
    profile = 'none' if role == 'Supervisor' else 'inherit' if role == 'Worker' else 'sandbox'
    return (all(type(event.get(key)) is int and event[key] == 0 for key in
                ['api', 'validity', 'requirementStatus', 'informationStatus',
                 'copyGuestStatus' if guest else 'copySelfStatus']) and
            all(tracing.snapshot_field_valid(event, key) for key in FIELDS) and
            event.get('fieldsAvailable') is True and event.get('baselineMatched') is True and
            event.get('subjectRole') == role and type(event.get('subjectPID')) is int and
            event['subjectPID'] == pid and event.get('source') == ('guest' if guest else 'self') and
            all(event.get(key) == product[value] for key, value in
                [('identity', 'identity'), ('hash', 'cdhash'), ('team', 'team'), ('flags', 'flags'), ('runtime', 'runtime')]) and
            event.get('entitlements') == profile and
            all(event.get(key) is True for key in ['valid', 'hard', 'kill']) and
            all(event.get(key) is False for key in ['debugged', 'platform']))


def assess_case(case, accepted, manifest, artifact_hash):
    """assess_case requires complete causal evidence and retains independent negative observations."""
    result = dict(accepted=False, result='unknown', refusals=[], regressions=[], unavailableEvidence=[],
                  **tracing.termination_evidence(case))
    def missing(reason):
        result['unavailableEvidence'].append(reason)
        return result
    for event in case.get('events', []):
        if event.get('kind') in ['ptrace', 'continue', 'execFailure'] and event.get('result') == -1:
            result['refusals'].append(dict(kind=event['kind'], errno=event.get('errno')))
        if event.get('kind') == 'snapshot':
            # Validity is observed before signing-information lookup. Its typed
            # result survives a later API/field or cleanup failure, while missing
            # or mistyped values never become a fabricated protection regression.
            source = event.get('source')
            reference = {'self': 'copySelfStatus', 'guest': 'copyGuestStatus'}.get(source) if type(source) is str else None
            validity_observed = reference is not None and all(
                type(event.get(key)) is int and event[key] == 0 for key in [reference, 'requirementStatus'])
            if not tracing.snapshot_field_valid(event, 'validity') or not validity_observed:
                result['unavailableEvidence'].append('validity observation unavailable at ' + str(event.get('stage')))
            elif event['validity'] != 0:
                result['regressions'].append(dict(kind='publicProtection', stage=event.get('stage'),
                                                field='validity', value=event['validity']))
            if type(event.get('api')) is int and event['api'] == 0 and (
                event.get('valid') is False or event.get('debugged') is True or
                event.get('hard') is False or event.get('kill') is False):
                result['regressions'].append(dict(kind='publicProtection', stage=event.get('stage')))
        if event.get('kind') == 'storageCross' and (event.get('readResult') == 0 or event.get('writeResult') == 0):
            result['regressions'].append(dict(kind='crossOwnerAccess', path=event.get('path')))
        if event.get('kind') == 'storageOwn' and event.get('contentEqual') is False:
            result['regressions'].append(dict(kind='ownContentMismatch', path=event.get('path')))
        if event.get('promptObserved') is True:
            return missing('unexpected prompt observed; no authorization supplied')
    if result['regressions']:
        result['result'] = 'weakened'
    elif result['refusals']:
        result['result'] = 'rejected'
    index = len(accepted)
    if index >= 4 or case.get('phase') != PHASES[index] or any(c.get('assessment', {}).get('accepted') is not True for c in accepted):
        return missing('finite predecessor sequence')
    who = 'B' if index == 1 else 'A'
    if (case.get('owner') != who or case.get('matchedArtifacts') != artifact_hash or
        any(case.get(key) is not True for key in ['positiveControls', 'recordProtocolValid', 'cleanupObserved',
                                                'supervisorWaitObserved', 'childWaitObserved']) or
        case.get('guardrailUsed') is not False or not result['normalCompletionObserved'] or case.get('errors') or
        result['refusals'] or result['regressions']):
        return missing('protocol, controls, artifact binding or actual successful exits')
    events = case['events']
    counts = {}
    for event in events:
        pid = event.get('pid')
        counts[pid] = counts.get(pid, 0) + 1
        if (event.get('phase') != case['phase'] or event.get('nonce') != case['nonce'] or
            event.get('owner') != who or type(event.get('sequence')) is not int or
            event['sequence'] != counts[pid] or counts[pid] > 32 or
            event.get('clock') != 'CLOCK_MONOTONIC' or not tracing.native_time(event.get('time')) or
            pid != case.get('supervisorPID' if event.get('role') == 'Supervisor' else 'childPID') or
            event.get('role') not in ['Supervisor', 'Stub', 'Worker']):
            return missing('record identity, native clock or sequence')
    if len(events) > 96:
        return missing('record cap')
    snapshots = {}
    for role in ['Supervisor', 'Stub']:
        key = role if role == 'Supervisor' else who + '.' + role
        stages = [one(case, 'snapshot', role, stage) for stage in ['S0', 'S1', 'S2']]
        if not all(snapshot_valid(event, manifest['products'][key], role,
                   case['supervisorPID' if role == 'Supervisor' else 'childPID']) for event in stages):
            return missing(role + ' setup public snapshots')
        if not all(same_fields(stages[0], event) for event in stages[1:]):
            return missing(role + ' setup protection changed')
        previous = next((one(prior, 'snapshot', role, 'S0') for prior in reversed(accepted)
                         if role == 'Supervisor' or prior['owner'] == who), None)
        if previous and not same_fields(stages[0], previous):
            return missing(role + ' same-build baseline mismatch')
        snapshots[role] = stages
    worker = one(case, 'snapshot', 'Worker', 'S4')
    if not snapshot_valid(worker, manifest['products'][who + '.Worker'], 'Worker', case['childPID']):
        return missing('Worker S4')
    previous_worker = next((one(prior, 'snapshot', 'Worker', 'S4') for prior in reversed(accepted) if prior['owner'] == who), None)
    if previous_worker and not same_fields(worker, previous_worker):
        return missing('Worker public baseline mismatch')
    controls = [one(case, 'controls', role) for role in ['Stub', 'Worker']]
    for index_control, control in enumerate(controls):
        if (not control or control.get('inherited') is not bool(index_control) or
            any(type(control.get(key)) is not int or control[key] != 0 for key in ['hardNproc', 'softNproc', 'setResult', 'setErrno']) or
            any(control.get(key) is not True for key in ['fileDenied', 'socketDenied', 'raiseDenied']) or
            any(type(control.get(key)) is not int or control[key] not in [1, 13] for key in ['fileErrno', 'socketErrno']) or
            control.get('socketResult') != -1 or control.get('raiseErrno') != 1):
            return missing('sandbox or inherited NPROC controls')
    guard = one(case, 'guard', 'Stub')
    supervisor_guard = one(case, 'guard', 'Supervisor')
    inherited = one(case, 'guardInherited', 'Worker')
    if (not guard or not supervisor_guard or not inherited or guard.get('seconds') != 2 or supervisor_guard.get('seconds') != 3 or
        not tracing.native_time(guard.get('lowerBound')) or not tracing.native_time(supervisor_guard.get('lowerBound')) or
        inherited.get('lowerBound') != guard['lowerBound'] or not tracing.native_time(inherited.get('remainingSeconds')) or
        any(inherited.get(key) is not True for key in ['armed', 'defaultSignal', 'unblocked'])):
        return missing('original inherited guards')
    grant, intent = one(case, 'execGrant', 'Supervisor'), one(case, 'execIntent', 'Stub')
    main = [event for event in events if event.get('kind') == 'workerProgress' and event.get('point') == 'mainEntry']
    if (not grant or grant.get('childPID') != case['childPID'] or not intent or intent.get('targetRole') != 'Worker' or
        len(main) != 1 or main[0].get('role') != 'Worker' or main[0].get('boundary') != 'reached'):
        return missing('sole grant, exec intent or Worker main marker')
    ordered = [supervisor_guard, snapshots['Supervisor'][0], guard, snapshots['Stub'][0], controls[0],
               snapshots['Stub'][1], snapshots['Supervisor'][1], snapshots['Stub'][2], snapshots['Supervisor'][2], grant, intent]
    if case['phase'] == 'O4':
        trace = one(case, 'ptrace', 'Stub')
        stop = one(case, 'execStop', 'Supervisor')
        external = one(case, 'snapshot', 'Supervisor', 'S3')
        pre_call = one(case, 'continueIntent', 'Supervisor')
        continued = one(case, 'continue', 'Supervisor')
        if (not all([trace, stop, external, pre_call, continued]) or
            any(type(event.get(key)) is not int or event[key] != 0 for event in [trace, continued] for key in ['result', 'errno']) or
            any(event.get('childPID') != case['childPID'] for event in [stop, pre_call, continued]) or
            stop.get('observed') is not True or stop.get('signal') != 5 or stop.get('waitStatus') != 1407 or
            not snapshot_valid(external, manifest['products']['A.Worker'], 'Worker', case['childPID'], True) or
            not same_fields(external, previous_worker) or
            not tracing.native_time(continued.get('requestTime')) or continued['requestTime'] > continued['time'] or
            not snapshots['Supervisor'][1]['time'] <= trace['time'] <= snapshots['Stub'][2]['time']):
            return missing('owned exec stop, fresh S3 or sole successful continue')
        ordered += [stop, external, pre_call, dict(time=continued['requestTime'])]
    elif any(event.get('kind') in ['ptrace', 'execStop', 'continueIntent', 'continue'] or event.get('stage') == 'S3' for event in events):
        return missing('tracing in untraced case')
    if any(event.get('kind') in ['execFailure', 'signalStop', 'cleanupRequest'] for event in events):
        return missing('unexpected stop or failed replacement')
    own = one(case, 'storageOwn', 'Worker')
    expected_home = manifest['userHome'] + '/Library/Containers/' + manifest['prefix'] + '.' + who + '.Stub/Data'
    expected_path = expected_home + '/CascadeOwner-' + manifest['runID'] + '/specimen'
    if (not own or own.get('home') != expected_home or own.get('path') != expected_path or
        len(expected_path.encode()) >= 1024 or own.get('created') is not (case['phase'] in ['O1', 'O2']) or
        any(own.get(key) is not True for key in ['contentEqual', 'regular', 'canonical']) or
        any(type(own.get(key)) is not int or own[key] != value for key, value in [('size', 64), ('result', 0), ('errno', 0)]) or
        any(type(own.get(key)) is not int or own[key] <= 0 for key in ['device', 'inode'])):
        return missing('own specimen exact content, path, type or size')
    previous_own = next((one(prior, 'storageOwn', 'Worker') for prior in accepted if prior['owner'] == who), None)
    if previous_own and any(own[key] != previous_own[key] for key in ['home', 'path', 'device', 'inode', 'size']):
        return missing('same owner specimen continuity')
    ordered += [main[0], worker, inherited, controls[1], own]
    crosses = [event for event in events if event.get('kind') == 'storageCross']
    if case['phase'] != 'O1':
        target = next((one(prior, 'storageOwn', 'Worker') for prior in accepted if prior['owner'] != who), None)
        cross = one(case, 'storageCross', 'Worker')
        if (not target or not cross or len(crosses) != 1 or target['home'] == own['home'] or
            target['path'] == own['path'] or cross.get('path') != target['path'] or cross.get('denied') is not True or
            any(type(cross.get(key)) is not int or cross[key] != -1 for key in ['readResult', 'writeResult']) or
            any(type(cross.get(key)) is not int or cross[key] not in [1, 13] for key in ['readErrno', 'writeErrno'])):
            return missing('positive prior target and both unauthorized cross-owner denials')
        ordered += [cross]
    elif crosses:
        return missing('unexpected O1 cross operation')
    child_exit = one(case, 'childExit', 'Supervisor')
    if not child_exit:
        return missing('owned child exit')
    ordered += [child_exit]
    if (any(left['time'] > right['time'] for left, right in zip(ordered, ordered[1:])) or
        any(event['time'] >= guard['lowerBound'] - .4 for event in events if event['role'] == 'Worker') or
        child_exit['time'] >= guard['lowerBound'] or child_exit['time'] >= supervisor_guard['lowerBound']):
        return missing('causal native order or original deadline')
    result.update(accepted=True, result='fixedOwnerCaseObserved')
    return result


def baseline(event):
    return ':'.join(str(event[key]) for key in ['status', 'flags', 'runtime', 'hash', 'team', 'entitlements']) if event else '-'


def launch_spec(products, manifest, phase, cases, listener, foreign):
    """launch_spec freezes only prior accepted observations and the build's fixed A/B table."""
    who = 'B' if phase == 'O2' else 'A'
    prior = [case for case in cases if case['owner'] == who]
    supervisor = one(cases[-1], 'snapshot', 'Supervisor', 'S0') if cases else None
    stub = one(prior[-1], 'snapshot', 'Stub', 'S0') if prior else None
    worker = one(prior[-1], 'snapshot', 'Worker', 'S4') if prior else None
    own = one(prior[0], 'storageOwn', 'Worker')['path'] if prior else '-'
    others = [case for case in cases if case['owner'] != who]
    cross = one(others[0], 'storageOwn', 'Worker')['path'] if others else '-'
    table = manifest['products']
    return tracing.LaunchRecordSpec(arguments=(table['Supervisor']['path'], phase, '', table[who + '.Stub']['path'],
        str(foreign), str(listener.getsockname()[1]), table[who + '.Worker']['path'],
        baseline(supervisor), baseline(stub), baseline(worker), own, cross), owner=who, log_name=phase + '-owner.jsonl')


def main():
    """main executes at most O1–O4, stopping at the first incomplete or negative case."""
    products = Path(sys.argv[1]).resolve(strict=True)
    report = dict(schema='owner-bootstrap-observation-v1', characterization='fixed-development-owner-inheritance',
                  complete=False, result='unknown', nativeLauncherAdmitted=False,
                  productionTemplateVerifierQualified=False, managedDeathCharacterizationPerformed=False,
                  allVMProtectionsPreserved='unknown', cases=[], untracedCompatibilityObserved=False,
                  tracedCompatibilityObserved=False, crossOwnerDenialObserved=False,
                  sameOwnerContinuityObserved=False, observerExecutable=sys.executable,
                  externalDeadlineSeconds=5, maximumNativeParticipants=8, maximumConcurrentNativeParticipants=2,
                  explicitRecordAllocationLimitBytes=262144, specimenPayloadBytesMaximum=192,
                  diagnosticResidue=[], OSContainerMetadataAllocation='unmeasured',
                  promptObservation='No independent UI prompt observation; blocked syscall remains unknown')
    foreign = None
    foreign_created = False
    foreign_directory = None
    try:
        manifest = json.loads((products / 'manifest.json').read_text())
        report['build'] = manifest
        if not manifest_valid(manifest, products):
            raise ValueError('static fixed fixture manifest/profile/bytes rejected')
        artifacts = {key: manifest['products'][key]['hash'] for key in PRODUCTS}
        artifact_hash = hashlib.sha256(json.dumps(artifacts, sort_keys=True).encode()).hexdigest()
        report['artifacts'] = artifacts
        # Exclusive creation opens no pre-existing user file and searches no alternate location.
        foreign_directory = Path(manifest['userHome']) / 'Library/Application Support' / ('CascadeOwner-' + manifest['runID'])
        foreign_directory.mkdir(mode=0o700)
        foreign = foreign_directory / 'control'
        descriptor = os.open(foreign, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        foreign_created = True
        try:
            if os.write(descriptor, (manifest['runID'] * 2).encode()) != 64:
                raise OSError('short synthetic control write')
        finally:
            os.close(descriptor)
        report['foreignControl'] = str(foreign)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(4)
            listener.settimeout(.2)
            for phase in PHASES:
                spec = launch_spec(products, manifest, phase, report['cases'], listener, foreign)
                case = tracing.run_case(products, phase, 'Stub', listener, foreign, artifact_hash, launch_spec=spec)
                assessment = assess_case(case, report['cases'], manifest, artifact_hash)
                case['assessment'] = assessment
                report['cases'].append(case)
                report['stoppedAt'] = phase
                own = one(case, 'storageOwn', 'Worker')
                if own and own.get('created') is True and own.get('path') not in report['diagnosticResidue']:
                    report['diagnosticResidue'].append(own.get('path'))
                if not assessment['accepted']:
                    break
            complete_count = sum(case['assessment']['accepted'] for case in report['cases'])
            report.update(complete=complete_count == 4, untracedCompatibilityObserved=complete_count >= 3,
                          tracedCompatibilityObserved=complete_count == 4,
                          crossOwnerDenialObserved=complete_count >= 3, sameOwnerContinuityObserved=complete_count >= 3)
            report['result'] = 'fixedOwnerBootstrapObserved' if report['complete'] else 'unknown'
    except Exception as error:
        report['error'] = type(error).__name__ + ': ' + str(error)
    finally:
        # Only this observer's synthetic non-container file can be removed. Owner
        # specimens and OS app containers remain named diagnostic residue.
        if foreign_created:
            try:
                foreign.unlink()
                foreign_directory.rmdir()
                report['foreignControlRemoved'] = True
            except OSError as error:
                report['foreignControlRemoved'] = False
                report['foreignCleanupError'] = str(error)
        report['terminations'] = [dict(phase=case['phase'], **tracing.termination_evidence(case)) for case in report['cases']]
        (products / 'owner-report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(products / 'owner-report.json')
        print(report['result'])
    return 0 if report['complete'] else 1


if __name__ == '__main__':
    sys.exit(main())
