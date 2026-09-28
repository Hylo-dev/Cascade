import copy
import unittest
from startup_evidence import classify


class StartupEvidenceTests(unittest.TestCase):
    def record(self):
        return dict(mode="broker-stop", authenticated=True, registered=True, confirmed=True,
                    phaseBefore="initializer-pending", phaseAfter="initializer-pending",
                    observerAlive=True, rootAlive=True, trigger=10., providerGuard=35., brokerGuard=40.,
                    observerGuard=45., windowEnd=11.,
                    exits=dict(broker=dict(time=10.1, status=0), provider=dict(time=10.2, status=9)))

    def test_exact_exits_during_blocked_init(self):
        self.assertEqual(classify(self.record()), "PASS")
        record = self.record(); record.update(mode="broker-crash")
        record['exits']['broker']['status'] = 9
        self.assertEqual(classify(record), "PASS")

    def test_broker_crash_requires_injected_sigkill(self):
        record = dict(self.record(), mode='broker-crash')
        record['exits']['broker']['status'] = 15
        self.assertEqual(classify(record), 'FAIL')

    def test_framework_may_return_before_provider_init_finishes(self):
        record = dict(self.record(), phaseAfter="process-ready")
        self.assertEqual(classify(record), "PASS")
        record['phaseAfter'] = 'channel-ready'
        self.assertEqual(classify(record), "UNKNOWN")

    def test_missing_authentication_registration_or_observer_cannot_pass(self):
        for key in ('authenticated', 'registered', 'confirmed', 'observerAlive'):
            self.assertEqual(classify(dict(self.record(), **{key:False})), 'UNKNOWN')

    def test_guard_exit_or_cleanup_after_window_cannot_pass(self):
        for event in (dict(time=10.2, status=14), dict(time=19., status=9)):
            record = copy.deepcopy(self.record()); record['exits']['provider'] = event
            self.assertEqual(classify(record), 'FAIL')
        record = self.record(); record['exits'].pop('provider')
        self.assertEqual(classify(record), 'UNKNOWN')

    def test_global_recovery_needs_expected_root_exit(self):
        record = dict(self.record(), mode='root-crash', rootStatus=-9, rootExit=10.05)
        record['exits']['broker']['status'] = 9
        self.assertEqual(classify(record), 'PASS')
        record['rootStatus'] = 0
        self.assertEqual(classify(record), 'UNKNOWN')


if __name__ == '__main__': unittest.main()
