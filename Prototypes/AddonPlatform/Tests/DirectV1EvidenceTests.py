import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'DirectV1/evidence.py'
spec = importlib.util.spec_from_file_location('direct_v1_evidence', path)
module = importlib.util.module_from_spec(spec)
if path.exists(): spec.loader.exec_module(module)

class DirectV1EvidenceTests(unittest.TestCase):
    def valid(self):
        return dict(schemaVersion=1, scenario='launcher-admission-direct-v1',
                    policyID='native-direct-control-v1', acceptedLimitations=['autonomousOSDelegation'],
                    checks={key: True for key in ('managedStop', 'hostExitCleanup', 'hostCrashCleanup',
                        'supervisorDeathStopsWorker', 'identitySafe', 'sessionInvalidatedAfterExec',
                        'cpuReadable', 'footprintReadable')}, unverified=[])
    def validate(self, record):
        self.assertTrue(hasattr(module, 'validate'), 'direct-v1 policy validator is missing')
        return module.validate(record)
    def test_complete_exact_policy_passes(self): self.assertEqual(self.validate(self.valid()), [])
    def test_every_required_false_missing_or_truthy_check_fails(self):
        for key in self.valid()['checks']:
            for value in [False, None, 1]:
                record = self.valid()
                if value is None: del record['checks'][key]
                else: record['checks'][key] = value
                self.assertIn(key, self.validate(record))
    def test_policy_and_limitations_are_exact(self):
        for key, value in [('policyID', 'other'), ('acceptedLimitations', []),
                           ('acceptedLimitations', ['autonomousOSDelegation', 'orphanWorkers']),
                           ('scenario', 'launcher-admission'), ('schemaVersion', True)]:
            record = self.valid(); record[key] = value
            self.assertIn(key, self.validate(record))
    def test_unknown_case_blocks(self):
        record = self.valid(); record['unverified'] = ['post-exec late message']
        self.assertIn('unverified', self.validate(record))
    def test_missing_observation_never_proves_exit(self):
        self.assertTrue(hasattr(module, 'cleanup_check'), 'cleanup evidence evaluator is missing')
        self.assertFalse(module.cleanup_check({'workerReady': True}))
    def test_alarm_or_observation_error_cannot_qualify_cleanup(self):
        self.assertTrue(hasattr(module, 'cleanup_check'), 'cleanup evidence evaluator is missing')
        for delta in [None, 2.5]:
            self.assertFalse(module.cleanup_check(dict(workerReady=True, sandboxVerified=True,
                helperKilled=True, helperExitObserved=True, exitObserved=True, exitAfterKillSeconds=delta)))
    def test_prompt_observed_exit_can_qualify_case_only(self):
        self.assertTrue(hasattr(module, 'cleanup_check'), 'cleanup evidence evaluator is missing')
        self.assertTrue(module.cleanup_check(dict(workerReady=True, sandboxVerified=True,
            helperKilled=True, helperExitObserved=True, exitObserved=True, exitAfterKillSeconds=0.05,
            helperKillTime=100.5, guardDeadlineLowerBound=103.0)))

    def test_printed_kill_intent_without_helper_exit_is_not_cleanup(self):
        self.assertTrue(hasattr(module, 'cleanup_check'))
        self.assertFalse(module.cleanup_check(dict(workerReady=True, sandboxVerified=True,
            helperKilled=True, exitObserved=True, exitAfterKillSeconds=.01)))

    def test_delayed_crash_cannot_turn_guard_alarm_into_cleanup(self):
        observation = dict(workerReady=True, sandboxVerified=True, helperKilled=True,
            helperExitObserved=True, exitObserved=True, exitAfterKillSeconds=.2,
            helperKillTime=102.8, guardDeadlineLowerBound=103.0)
        self.assertFalse(module.cleanup_check(observation))

    def test_missing_guard_evidence_never_qualifies_prompt_exit(self):
        self.assertFalse(module.cleanup_check(dict(workerReady=True, sandboxVerified=True,
            helperKilled=True, helperExitObserved=True, exitObserved=True, exitAfterKillSeconds=.01)))

    def audit_record(self):
        return dict(bootstrapReturnCode=0, bootoutReturnCode=0, workerReturnCode=0,
                    serverEvents=[dict(event='authenticated-message', operation=1, authStatus=0,
                        accepted=True, sessionActive=True, auditPID=123, auditVersion=10),
                        dict(event='authenticated-message', operation=2, authStatus=-67065,
                        accepted=False, sessionActive=False, sameAuditToken=True, auditPID=123, auditVersion=10),
                        dict(event='authenticated-message', operation=3, authStatus=-67050,
                        accepted=False, sessionActive=False, sameAuditToken=False, auditPID=123, auditVersion=11)],
                    workerEvents=[dict(event='client', mode=mode, foreignFileDenied=True)
                                  for mode in ['original', 'replacement']]
                                  + [dict(event='replacement-reply', accepted=0)])
    def audit_check(self, record):
        self.assertTrue(hasattr(module, 'audit_check'), 'audit evidence evaluator is missing')
        return module.audit_check(record)
    def test_authentic_exec_and_stale_message_fixture_passes(self):
        self.assertTrue(self.audit_check(self.audit_record()))
    def test_missing_auth_message_or_sandbox_denial_blocks(self):
        record = self.audit_record(); record['serverEvents'].pop()
        self.assertFalse(self.audit_check(record))
        record = self.audit_record(); record['workerEvents'][1]['foreignFileDenied'] = False
        self.assertFalse(self.audit_check(record))
    def test_auth_api_error_is_not_proof_of_stale_identity(self):
        record = self.audit_record(); record['serverEvents'][1]['authStatus'] = -1
        self.assertFalse(self.audit_check(record))
    def test_reused_audit_version_or_active_session_blocks(self):
        record = self.audit_record(); record['serverEvents'][2]['auditVersion'] = 10
        self.assertFalse(self.audit_check(record))
        record = self.audit_record(); record['serverEvents'][1]['sessionActive'] = True
        self.assertFalse(self.audit_check(record))

    def test_audit_cleanup_error_prevents_component_pass(self):
        record = self.audit_record()
        record['cleanupErrors'] = ['worker drain timed out']
        self.assertFalse(self.audit_check(record))

    def test_component_identity_success_does_not_admit_an_integrated_launcher(self):
        self.assertTrue(hasattr(module, 'make_record'), 'scoped admission producer is missing')
        record = module.make_record([], self.audit_record())
        self.assertTrue(record['observations']['isolatedAuditProofPassed'])
        self.assertEqual(record['scenario'], 'launcher-admission-direct-v1')
        self.assertEqual(record['policyID'], 'native-direct-control-v1')
        self.assertEqual(record['acceptedLimitations'], ['autonomousOSDelegation'])
        self.assertTrue(all(value is False for value in record['checks'].values()))
        self.assertTrue(module.validate(record))

if __name__ == '__main__': unittest.main()
