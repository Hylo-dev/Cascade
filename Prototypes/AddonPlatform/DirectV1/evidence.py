"""Separate direct-control admission. Historical strict evidence is never rewritten."""
REQUIRED = ('managedStop', 'hostExitCleanup', 'hostCrashCleanup',
            'supervisorDeathStopsWorker', 'identitySafe', 'sessionInvalidatedAfterExec',
            'cpuReadable', 'footprintReadable')

def validate(record):
    errors = []
    for key, expected in [('schemaVersion', 1), ('scenario', 'launcher-admission-direct-v1'),
                          ('policyID', 'native-direct-control-v1'),
                          ('acceptedLimitations', ['autonomousOSDelegation']), ('unverified', [])]:
        if type(record.get(key)) is not type(expected) or record.get(key) != expected:
            errors.append(key)
    checks = record.get('checks', {})
    if not isinstance(checks, dict): checks = {}
    errors.extend(key for key in REQUIRED if checks.get(key) is not True)
    return errors

def cleanup_check(observation):
    import math
    kill_time = observation.get("helperKillTime")
    guard_deadline = observation.get("guardDeadlineLowerBound")
    if any(type(value) not in (int, float) or not math.isfinite(value)
           for value in (kill_time, guard_deadline)):
        return False
    # The trusted pre-exec shim records the earliest possible guard firing time.
    # Leave the entire one-second qualification window before that lower bound.
    if kill_time + 1.0 >= guard_deadline:
        return False
    if observation.get("observationError") or observation.get("cleanupError"):
        return False
    duration = observation.get('exitAfterKillSeconds')
    return (all(observation.get(key) is True for key in
                ('workerReady', 'sandboxVerified', 'helperKilled', 'helperExitObserved', 'exitObserved'))
            and type(duration) in (float, int) and 0 <= duration < 1.0)

def audit_check(record):
    """A scoped component proof, never sufficient to admit a launcher."""
    if any(record.get(key) != 0 for key in ('bootstrapReturnCode', 'bootoutReturnCode', 'workerReturnCode')):
        return False
    if record.get('error') or record.get('cleanupErrors'): return False
    messages = [event for event in record.get('serverEvents', []) if event.get('event') == 'authenticated-message']
    if len(messages) != 3 or [m.get('operation') for m in messages] != [1, 2, 3]: return False
    initial, stale, replacement = messages
    if [m.get('authStatus') for m in messages] != [0, -67065, -67050]: return False
    if initial.get('accepted') is not True or initial.get('sessionActive') is not True: return False
    if any(m.get('accepted') is not False or m.get('sessionActive') is not False for m in (stale, replacement)): return False
    if stale.get('sameAuditToken') is not True or replacement.get('sameAuditToken') is not False: return False
    if not (type(initial.get('auditPID')) is int and initial['auditPID'] > 0
            and initial['auditPID'] == stale.get('auditPID') == replacement.get('auditPID')): return False
    if not (type(initial.get('auditVersion')) is int and type(replacement.get('auditVersion')) is int
            and initial['auditVersion'] == stale.get('auditVersion') != replacement['auditVersion']): return False
    clients = [event for event in record.get('workerEvents', []) if event.get('event') == 'client']
    if [c.get('mode') for c in clients] != ['original', 'replacement']: return False
    if not all(c.get('foreignFileDenied') is True for c in clients): return False
    replies = [event for event in record.get('workerEvents', []) if event.get('event') == 'replacement-reply']
    return len(replies) == 1 and type(replies[0].get('accepted')) is int and replies[0]['accepted'] == 0

def make_record(groups, audit):
    """Produce explicitly blocked admission until one integrated launcher is proven."""
    return dict(schemaVersion=1, scenario='launcher-admission-direct-v1',
        policyID='native-direct-control-v1', acceptedLimitations=['autonomousOSDelegation'],
        checks={key: False for key in REQUIRED},
        observations=dict(launcher='unqualified launchd-owned direct-child group prototype',
            isolatedAuditProofPassed=audit_check(audit), groupCases=groups, auditProof=audit,
            measuredPlatform='macOS 27.0 beta 26A5425a arm64, SDK 27, Apple Development team A6A5HQL6K4',
            historicalStrictAdmission='unchanged, negative; autonomous OS delegation counterexample remains separate'),
        unverified=['No integrated launcher satisfies helper-death cleanup and authenticated session control.',
            'Fresh normal/host-exit/host-crash lifecycle, metrics, 20-cycle cost/reuse qualification for any replacement launcher.',
            'Other macOS versions, Intel and another publisher.'])

if __name__ == '__main__':
    import json
    import sys
    try:
        if sys.argv[1] == '--compose':
            with open(sys.argv[2]) as source: groups = json.load(source)
            with open(sys.argv[3]) as source: audit = json.load(source)
            record = make_record(groups, audit)
            with open(sys.argv[4], 'w') as output: json.dump(record, output, indent=2); output.write('\n')
        else:
            with open(sys.argv[1]) as source: record = json.load(source)
        errors = validate(record)
    except (IndexError, OSError, ValueError, AttributeError, TypeError) as error:
        errors = [str(error)]
    print(('FAIL: ' + ', '.join(errors)) if errors else 'PASS')
    sys.exit(bool(errors))
