import copy
import unittest
from recovery_evidence import classify


class RecoveryEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.record = dict(mode="normal", authenticated=True, registered=True,
            sameInstance=True, invalidationObserved=True, stillAliveAfterInvalidation=True,
            trigger=10.0, guardDeadline=30.0, hostStatus=0, hostExitObserved=10.02,
            serviceExit=10.03, serviceStatus=9, restartStarted=11.0,
            freshAuthenticated=True, freshInstance=True, freshRegistered=True,
            freshConfirmed=True, freshGuardDeadline=40.0, freshStopTrigger=12.0,
            freshHostStatus=0, freshExit=12.02, freshStatus=9)

    def test_requires_both_host_and_provider_exit_before_restart(self):
        self.assertEqual(classify(self.record), "PASS")
        self.assertEqual(classify(self.record | {"restartStarted":10.01}), "FAIL")
        self.assertEqual(classify(self.record | {"serviceExit":None}), "UNKNOWN")
        self.assertEqual(classify(self.record | {"hostStatus":None}), "UNKNOWN")

    def test_guard_fault_or_late_exit_cannot_qualify(self):
        for patch in [{"serviceStatus":14},{"serviceStatus":11},{"serviceExit":18.01},
                      {"freshStatus":14},{"freshExit":40.0}]:
            self.assertEqual(classify(self.record | patch), "FAIL")

    def test_authentication_and_freshness_must_be_observed(self):
        for key in ("authenticated","registered","sameInstance","freshAuthenticated",
                    "freshInstance","freshRegistered","freshConfirmed","invalidationObserved",
                    "stillAliveAfterInvalidation"):
            self.assertEqual(classify(self.record | {key:False}), "UNKNOWN")

    def test_crash_and_normal_have_distinct_host_status(self):
        self.assertEqual(classify(self.record | {"mode":"crash","hostStatus":-9}), "PASS")
        self.assertEqual(classify(self.record | {"mode":"crash"}), "UNKNOWN")
        self.assertEqual(classify(self.record | {"observationError":"lost event"}), "UNKNOWN")


if __name__ == "__main__": unittest.main()
